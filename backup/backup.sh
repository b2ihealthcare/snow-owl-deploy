#!/usr/bin/env bash
#
# Copyright 2018 B2i Healthcare Pte Ltd, http://b2i.sg
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Snow Owl terminology server backup script
# See usage or execute the script with the -h flag to get further information.
#
# Version: 1.0
#

# The default deployment folder for Snow Owl terminology servers
DEFAULT_DEPLOYMENT_FOLDER="/opt/snowowl"

JDK_HOME="/opt/jdk-11.0.4+11"

# The default location where dataset SHA1 sum is stored
DEFAULT_DATASET_SHA1_LOCATION="${DEFAULT_DEPLOYMENT_FOLDER}/currentDataset"

# The default deployment folder of the Snow Owl terminology server
DEFAULT_SERVER_PATH="${DEFAULT_DEPLOYMENT_FOLDER}/server/latest"

# The target path of the dataset backup archive
TARGET_ARCHIVE_PATH=""

# Existing username for the Snow Owl terminology server
SNOWOWL_USER=""

# The password for the Snow Owl user specified above
SNOWOWL_USER_PASSWORD=""

# If set the database SHA1 sum will be refreshed at the end of the backup process
REFRESH_SHA1="false"

# Variable used for storing the currently running Snow Owl server's path
RUNNING_SERVER_PATH=""

# The number of retries to wait for e.g. server shutdown or server startup
RETRIES=120

# The number of seconds to wait between retries
RETRY_WAIT_SECONDS=1

# The base URL of the REST services to use
BASE_URL="http://localhost:8080/snowowl"

# The base URL for administrative services
ADMIN_BASE_URL="${BASE_URL}/admin"

# The REST endpoint which provides the list of available repositories
REPOSITORIES_URL="${ADMIN_BASE_URL}/repositories"

# The general info REST endpoint which also provides the list of available repositories
INFO_URL="${ADMIN_BASE_URL}/info"

# Enviromental variable used by Jenkins
export BUILD_ID=dontKillMe

usage() {

	cat <<EOF
NAME:

    Snow Owl terminology server backup script

OPTIONS:
	-h
		Show this help
	-t path
		Define the target path of the backup archive including the desired filename
	-f username
		Define the user for the Snow Owl terminology server which will be used for accessing information through the REST API
	-j password
		Define the password for the above Snow Owl user
	-r true|false
		If set to true the dataset SHA1 file will be updated after the backup process

NOTES:

	All of the above parameters are mandatory except '-r'.

	If there is a running Snow Owl terminology server at the time of script execution, the following will happen:
		- automatically locate the server
		- shut it down gracefully
		- create backup archive
		- update dataset SHA1 file if required
		- restart server and wait for full initialization

	If there are no Snow Owl servers running at the time of script execution, the following will happen:
		- use the configured default server path to locate the Snow Owl terminology server (E.g.: /opt/snowowl/server/latest )
		- create backup archive
		- update dataset SHA1 file if required

	Examples:

	./backup.sh -t /path/to/desired/backup_archive.zip -f username -j password

	OR

	./backup.sh -t /path/to/desired/backup_archive.zip -f username -j password -r true

EOF
}

echo_step() {
	echo_date
	echo_date "#### $@ ####"
}

echo_error() {
	echo_date "ERROR: $@" >&2
}

echo_date() {
	echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] $@"
}

echo_exit() {
	echo_error $@
	exit 1
}

check_if_empty() {

	if [ -z "$1" ]; then
		echo_exit "$2"
	fi

}

check_if_folder_exists() {

	if [ ! -d "$1" ]; then
		echo_exit "$2"
	fi

}

rest_call() {
	CURL_OUTPUT=$(curl -q --fail --silent --connect-timeout 5 --user "$SNOWOWL_USER:$SNOWOWL_USER_PASSWORD" --write-out "\n%{http_code}" "$@")
	CURL_MESSAGE=$(echo "$CURL_OUTPUT" | head -n-1)
	CURL_HTTP_STATUS=$(echo "$CURL_OUTPUT" | tail -n1)
}

check_variables() {

	check_if_empty "${SNOWOWL_USER}" "A valid username for Snow Owl must be specified"
	check_if_empty "${SNOWOWL_USER_PASSWORD}" "Password for the Snow Owl user must be specified"

	check_if_empty "${TARGET_ARCHIVE_PATH}" "A target path must be specified for the backup archive"
	check_if_folder_exists $(dirname ${TARGET_ARCHIVE_PATH}) "Target directory of the backup archive must exist"

}

find_running_snowowl_servers() {

	echo_step "Searching for running server instances"

	RUNNING_SERVER_PATH=$(ps aux | grep java | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then
		echo_date "The following Snow Owl server will be used for the backup: '${RUNNING_SERVER_PATH}'"
		SERVER_PATH="${RUNNING_SERVER_PATH}"
	else
		echo_date "No running Snow Owl server found, falling back to the default server path: '${DEFAULT_SERVER_PATH}'"
		SERVER_PATH="${DEFAULT_SERVER_PATH}"
	fi

}

shutdown_server() {

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then

		echo_step "Shutdown"

		echo_date "Shutting down server @ '${RUNNING_SERVER_PATH}'"

		SERVER_IS_DOWN=false

		if [ -f "${RUNNING_SERVER_PATH}/bin/shutdown.sh" ]; then

			"${RUNNING_SERVER_PATH}/bin/shutdown.sh" >/dev/null

		else

			SERVER_PID=$(ps aux | grep java | grep osgi.install.area | awk '{print $2}')

			kill ${SERVER_PID} >/dev/null

		fi

		for i in $(seq 1 "${RETRIES}"); do

			SERVER_TO_SHUTDOWN=$(ps aux | grep java | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

			if [ ! -z "${SERVER_TO_SHUTDOWN}" ]; then
				sleep "${RETRY_WAIT_SECONDS}"s
			else
				echo_date "Shutdown finished."
				SERVER_IS_DOWN=true
				break
			fi

		done

		if [ "${SERVER_IS_DOWN}" = false ]; then
			echo_exit "Unable to shutdown server @ '${RUNNING_SERVER_PATH}' after $((${RETRIES} * ${RETRY_WAIT_SECONDS})) seconds"
		fi

	fi

}

create_backup() {

	echo_step "Creating backup"

	TMP_DATASET_DIR=$(mktemp -d --tmpdir="${SERVER_PATH}")

	ln -s "${SERVER_PATH}/resources/indexes" "${TMP_DATASET_DIR}/indexes"

	cd "${TMP_DATASET_DIR}"

	echo_date "Creating archive @ '${TARGET_ARCHIVE_PATH}'"

	zip --recurse-paths --quiet --display-globaldots --dot-size 500m "${TARGET_ARCHIVE_PATH}" "indexes"/ &&
		echo_date "Archive is available @ '${TARGET_ARCHIVE_PATH}'" ||
		echo_date "Archive creation failed @ '${TARGET_ARCHIVE_PATH}'"

	if [ -f "${TARGET_ARCHIVE_PATH}" ]; then
		sha1sum "${TARGET_ARCHIVE_PATH}" >"${TARGET_ARCHIVE_PATH}.sha1" && echo_date "SHA1 checksum is @ '${TARGET_ARCHIVE_PATH}.sha1'"
	fi

}

update_dataset_sha1() {

	if [ -f "${DEFAULT_DATASET_SHA1_LOCATION}" ]; then

		INCOMING_DATASET_SHA1=$(cat "${TARGET_ARCHIVE_PATH}.sha1" | sed -e 's/\s.*$//')
		EXISTING_DATASET_SHA1=$(<${DEFAULT_DATASET_SHA1_LOCATION})

		if [ ! -z "${EXISTING_DATASET_SHA1}" ]; then

			if [ "${INCOMING_DATASET_SHA1}" != "${EXISTING_DATASET_SHA1}" ]; then

				touch "${DEFAULT_DATASET_SHA1_LOCATION}"
				echo "${INCOMING_DATASET_SHA1}" >"${DEFAULT_DATASET_SHA1_LOCATION}"

				echo_date "Updated dataset SHA1 file @ '${DEFAULT_DATASET_SHA1_LOCATION}'"

			fi

		else

			touch "${DEFAULT_DATASET_SHA1_LOCATION}"
			echo "${INCOMING_DATASET_SHA1}" >"${DEFAULT_DATASET_SHA1_LOCATION}"

			echo_date "Created dataset SHA1 file @ '${DEFAULT_DATASET_SHA1_LOCATION}'"

		fi

	fi

}

verify_server_startup() {

	SERVER_IS_UP=false

	for i in $(seq 1 "${RETRIES}"); do

		SERVER_TO_START=$(ps aux | grep java | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

		if [ -z "${SERVER_TO_START}" ]; then
			sleep "${RETRY_WAIT_SECONDS}"s
		else
			echo_date "Starting up server @ '${SERVER_TO_START}'"
			SERVER_IS_UP=true
			break
		fi

	done

	if [ "${SERVER_IS_UP}" = true ]; then

		SERVER_IS_UP=false

		for i in $(seq 1 "${RETRIES}"); do

			rest_call "${INFO_URL}"

			if [ "${CURL_HTTP_STATUS}" != "200" ]; then
				sleep "${RETRY_WAIT_SECONDS}"s
			else

				echo "${CURL_MESSAGE}" | grep -Po '"health":.*?[^\\]"' | sed 's/\"health\":\"\(.*\)\"/\1/' | while read -r REPOSITORY_HEALTH_STATE; do
					if [ "${REPOSITORY_HEALTH_STATE}" = "RED" ]; then
						echo_exit "One of the repositories returned RED health state. Check database consistency."
					fi
				done

				echo_date "Server is up @ '${SERVER_TO_START}'"
				SERVER_IS_UP=true
				break

			fi

		done

	fi

	if [ "${SERVER_IS_UP}" = false ]; then
		echo_exit "Unable to start server @ '$1' after $((${RETRIES} * ${RETRY_WAIT_SECONDS})) seconds"
	fi

}

start_server() {

	if [ ! -z "${SERVER_PATH}" ]; then

		echo_step "Starting server"

		chmod +x $SERVER_PATH/bin/*.sh

		export JAVA_HOME="${JDK_HOME}"

		screen -d -m -S "$(basename ${SERVER_PATH})" -t "${SERVER_PATH}" "${SERVER_PATH}/bin/snowowl.sh"

		verify_server_startup "${SERVER_PATH}"

	fi

}

cleanup() {

	if [ -d "${TMP_DATASET_DIR}" ]; then

		echo_step "Clean up"
		if [ -d "${TMP_DATASET_DIR}/indexes" ]; then
			rm --force "${TMP_DATASET_DIR}/indexes" && echo_date "Removed symlink to 'indexes' folder"
		fi

		rm --recursive --force ${TMP_DATASET_DIR} && echo_date "Deleted temporary backup dir @ '${TMP_DATASET_DIR}'"

	fi
}

main() {

	echo_date "################################"
	echo_date "Snow Owl backup script STARTED."

	check_variables

	find_running_snowowl_servers

	shutdown_server

	create_backup

	if [ "${REFRESH_SHA1}" = "true" ]; then
		update_dataset_sha1
	fi

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then
		start_server
	fi

	echo_date
	echo_date "Snow Owl backup script FINISHED."

	exit 0

}

trap cleanup EXIT

while getopts ":ht:f:j:r:" opt; do
	case "$opt" in
	h)
		usage
		exit 0
		;;
	t)
		TARGET_ARCHIVE_PATH=$OPTARG
		;;
	f)
		SNOWOWL_USER=$OPTARG
		;;
	j)
		SNOWOWL_USER_PASSWORD=$OPTARG
		;;
	r)
		REFRESH_SHA1=$OPTARG
		;;
	\?)
		echo_error "Invalid option: $OPTARG" >&2
		usage
		exit 1
		;;
	:)
		echo_error "Option: -$OPTARG requires an argument." >&2
		usage
		exit 1
		;;
	esac
done

main
