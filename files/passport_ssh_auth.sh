#!/usr/bin/env bash
#
# Script for SSH user provisioning from passport.hydra database.
# External commands required: jq, curl, sqlite
#
# Passport.hydra users got their keys cached locally in the sqlite database for CACHETTL seconds.
# All incoming user login attempts are cached locally in the sqlite database for CACHETTL seconds.
#
# ivan.savytskyi
#	* 29/12/2020
#       * 30/12/2020
#       * 03/01/2021
#       * 04/01/2021


umask 0007

SUBS="/home/passport/.passport_subs"
CREDS="/home/passport/.passport_creds"

if [ -r "${SUBS}" ]; then
        #
        # source initial values and functions
        #
        . "${SUBS}"
else
        logger "$0 FATAL ERROR: Unable to read ${SUBS} file"
        exit 1
fi

if [ -r "${CREDS}" ]; then
        #
        # source credentails
        #
        . "${CREDS}"
else
        logger "$0 FATAL ERROR: Unable to read ${CREDS} file"
        exit 1
fi

########################################################################
########################## Script starts below #########################
########################################################################

if [ "$1" = "" ]; then
	logger "$0 FATAL ERROR: username is empty"
	exit 1
fi

USERNAME=$1

check_utilities

if [ -d "${WORKDIR}" ]; then
	cd "${WORKDIR}"
	if [ $? -ne 0 ]; then
		logger "$0 ERROR: unable to cd into the working directory ${WORKDIR}. Script execution was interrupted."
		exit 1
	fi
else
	logger "$0 WARNING: no working directory ${WORKDIR}. Script execution was interrupted."
	exit 1
fi

#########################################################################
# Return the key from the cache if it's not expired
#########################################################################

CACHETIME=`sqlite "${USERCACHE}" "SELECT strftime('%s', 'now') - lastaccess FROM ${TABLE} WHERE username='${USERNAME}';"`

#
# check cache
#
if [ -n "${CACHETIME}" ] && [ "${CACHETIME}" -eq "${CACHETIME}" ] 2>/dev/null; then
	#
	# user in cache, check expiration
	#
	if [ ${CACHETIME} -le "${CACHETTL}" ]; then
		#
		# cache is not expired, check grants:
		#
		GRANT=`sqlite "${USERCACHE}" "SELECT isactive * passport FROM ${TABLE} WHERE username='${USERNAME}';"`
		if [ "${GRANT}" -eq 1 ] 2>/dev/null; then
			#
			# return the key
			#
			sqlite "${USERCACHE}" "SELECT sshkey FROM ${TABLE} WHERE username='${USERNAME}';" 2>/dev/null
			if [ $? -ne 0 ]; then
				logger "$0 WARNING: sqlite failure on SELECT sshkey FROM ${TABLE} WHERE username='${USERNAME}'"
			fi
			exit 1
		else
			#
			# user access is not granted
			#
			exit 1
		fi
	else
		:
		#
		# cache expired: refresh the data from passport.hydra
		#
	fi
else
	:
	#
	# user not in cache, request data from passport hydra
	#
fi

#########################################################################
# Check if token file exists and it's not too old,
# otherwise (re)get the token from passport.hydra
#########################################################################

check_token
get_user_data

#########################################################################
# Validate user attributes
#########################################################################
check_user
update_user_cache
check_group_membership
validate_key_format

#########################################################################
# If all above is ok, display the key
#########################################################################
if [ "${KEY_STATUS}" = "ok" ]; then
	echo ${KEY}
else
	logger "$0 NOTICE: invalid ssh public key for user ${USERNAME}"
fi

rm -f ${USERFILE}

