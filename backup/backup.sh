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

# The default deployment folder of the Snow Owl terminology server
DEFAULT_SERVER_PATH="/opt/snowowl/server/latest"

# The target path of the dataset backup archive
TARGET_ARCHIVE_PATH=""

# The type of database which requires a backup, either 'mysql' or 'h2'
DATABASE_TYPE=""

# MySQL user
MYSQL_USER=""

# Password for MySQL user
MYSQL_USER_PASSWORD=""

# Existing username for the Snow Owl terminology server
SNOWOWL_USER=""

# The password for the Snow Owl user specified above
SNOWOWL_USER_PASSWORD=""

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

# List of all known database names used by the Snow Owl terminology server
# This is used only as a fallback
REPOSITORIES=(atcStore icd10Store icd10amStore icd10cmStore icd10ukStore lcsStore
	loincStore mappingsetStore opcsStore sddStore snomedStore umlsStore valuesetStore)

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
	-d type
		Define the database type of the given Snow Owl terminology server. It has to be either 'mysql' or 'h2'
	-u username
		Define a MySQL username which will be used for accessing the database
	-p password
		Define the password for the above MySQL user
	-f username
		Define the user for the Snow Owl terminology server which will be used for accessing information through the REST API
	-j password
		Define the password for the above Snow Owl user

NOTES:

	All of the above parameters are mandatory.

	If there is a running Snow Owl terminology server at the time of script execution, the following will happen:
		- automatically locate the server
		- shut it down gracefully
		- create backup archive (including MySQL dumps in case of 'mysql')
		- restart server and wait for full initialization

	If there are no Snow Owl servers running at the time of script execution, the following will happen:
		- use the configured default server path to locate the Snow Owl terminology server (E.g.: /opt/snowowl/server/latest )
		- create backup archive (including MySQL dumps in case of 'mysql')

	Examples:

	./backup.sh -t /path/to/desired/backup_archive.zip -d mysql -u username -p password -f username2 -j password2

	OR

	./backup.sh -t /path/to/desired/backup_archive.zip -d h2 -u username -p password -f username2 -j password2

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
	echo -e "[`date +\"%Y-%m-%d %H:%M:%S\"`] $@"
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

	check_if_empty "${MYSQL_USER}" "MySQL username must be specified"
	check_if_empty "${MYSQL_USER_PASSWORD}" "MySQL password must be specified"
	check_if_empty "${SNOWOWL_USER}" "A valid username for Snow Owl must be specified"
	check_if_empty "${SNOWOWL_USER_PASSWORD}" "Password for the Snow Owl user must be specified"

	check_if_empty "${TARGET_ARCHIVE_PATH}" "A target path must be specified for the backup archive"
	check_if_folder_exists $(dirname ${TARGET_ARCHIVE_PATH}) "Target directory of the backup archive must exist"

	check_if_empty "${DATABASE_TYPE}" "The type of backup must be specified (mysql or h2)"
	if [ "${DATABASE_TYPE}" != "mysql" ] && [ "${DATABASE_TYPE}" != "h2" ]; then
		echo_exit "Unknown database type: ${DATABASE_TYPE}. Please use either 'mysql' or 'h2'"
	fi

}

find_running_snowowl_servers() {

	echo_step "Searching for running server instances"

	RUNNING_SERVER_PATH=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then
		echo_date "The following Snow Owl server will be used for the backup: '${RUNNING_SERVER_PATH}'"
		SERVER_PATH="${RUNNING_SERVER_PATH}"
	else
		echo_date "No running Snow Owl server found, falling back to the default server path: '${DEFAULT_SERVER_PATH}'"
		SERVER_PATH="${DEFAULT_SERVER_PATH}"
	fi

}

collect_repositories() {

	COLLECTED_REPOSITORIES=()

	while read -r REPOSITORY; do
		COLLECTED_REPOSITORIES=("${COLLECTED_REPOSITORIES[@]}" "${REPOSITORY}")
	done < <(echo "${CURL_MESSAGE}" | grep -Po '"id":.*?[^\\]",' | sed 's/\"id\":\"\(.*\)\",/\1/')

	if [ ${#COLLECTED_REPOSITORIES[@]} -eq 0 ]; then
		echo_date "Failed to collect available repositories through REST, the default set of repositories will be used"
	else
		REPOSITORIES=("${COLLECTED_REPOSITORIES[@]}")
	fi

	for REPOSITORY in "${REPOSITORIES[@]}"; do
		echo_date "Identified repository: '${REPOSITORY}'"
	done

}

configure_repositories() {

	echo_step "Collecting available repositories"

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then

		EXTRACTED_REPOSITORIES=false

		for i in $(seq 1 "${RETRIES}"); do

			rest_call "${REPOSITORIES_URL}"

			if [ "${CURL_HTTP_STATUS}" != "200" ]; then
				sleep "${RETRY_WAIT_SECONDS}"s
			else

				if [ -z "${CURL_MESSAGE}" ] || [ "${CURL_MESSAGE}" = "{}" ]; then
					break # try other endpoint
				fi

				collect_repositories

				EXTRACTED_REPOSITORIES=true
				break

			fi

		done

		if [ "${EXTRACTED_REPOSITORIES}" = false ]; then

			for i in $(seq 1 "${RETRIES}"); do

				rest_call "${INFO_URL}"

				if [ "${CURL_HTTP_STATUS}" != "200" ]; then
					sleep "${RETRY_WAIT_SECONDS}"s
				else

					if [ -z "${CURL_MESSAGE}" ] || [ "${CURL_MESSAGE}" = "{}" ]; then
						break # fall back to defaults
					fi

					collect_repositories

					EXTRACTED_REPOSITORIES=true
					break

				fi

			done

		fi

		if [ "${EXTRACTED_REPOSITORIES}" = false ]; then
			echo_date "Failed to collect available repositories through REST, the default set of repositories will be used"
		fi

	else

		echo_date "There were no running Snow Owl servers, the default set of repositories will be used"

	fi

	echo_date "Repositories to dump: '${REPOSITORIES[@]}'"

}

shutdown_server() {

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then

		echo_step "Shutdown"

		echo_date "Shutting down server @ '${RUNNING_SERVER_PATH}'"

		"${RUNNING_SERVER_PATH}/bin/shutdown.sh" >/dev/null

		SERVER_IS_DOWN=false

		for i in $(seq 1 "${RETRIES}"); do

			SERVER_TO_SHUTDOWN=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

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

backup_repository() {
	DATABASE_DUMP_FILE="$REPOSITORY.sql"
	echo_date "Creating SQL dump from contents of repository $REPOSITORY to $DATABASE_DUMP_FILE..."
	mysqldump --user="${MYSQL_USER}" --password="${MYSQL_USER_PASSWORD}" "${REPOSITORY}" >"${TMP_DATASET_DIR}/${DATABASE_DUMP_FILE}" >/dev/null 2>&1
}

create_backup() {

	echo_step "Creating backup"

	TMP_DATASET_DIR=$(mktemp -d --tmpdir="${SERVER_PATH}")

	if [ "${DATABASE_TYPE}" = "mysql" ]; then

		echo_date "Initiating backup for database type: '${DATABASE_TYPE}'"

		for REPOSITORY in "${REPOSITORIES[@]}"; do
			backup_repository
		done

		ln -s "${SERVER_PATH}/resources/indexes" "${TMP_DATASET_DIR}/indexes"

		cd "${TMP_DATASET_DIR}"

		echo_date "Creating archive @ '${TARGET_ARCHIVE_PATH}'"

		zip --recurse-paths --quiet --display-globaldots --dot-size 500m "${TARGET_ARCHIVE_PATH}" "indexes"/ *.sql &&
			echo_date "Archive is available @ '${TARGET_ARCHIVE_PATH}'" ||
			echo_date "Archive creation failed @ '${TARGET_ARCHIVE_PATH}'"

	else # h2

		echo_date "Initiating backup for database type: '${DATABASE_TYPE}'"

		ln -s "${SERVER_PATH}/resources/indexes" "${TMP_DATASET_DIR}/indexes"
		ln -s "${SERVER_PATH}/resources/store" "${TMP_DATASET_DIR}/store"

		cd "${TMP_DATASET_DIR}"

		echo_date "Creating archive @ '${TARGET_ARCHIVE_PATH}'"

		zip --recurse-paths --quiet --display-globaldots --dot-size 500m "${TARGET_ARCHIVE_PATH}" "indexes"/ "store"/ &&
			echo_date "Archive is available @ '${TARGET_ARCHIVE_PATH}'" ||
			echo_date "Archive creation failed @ '${TARGET_ARCHIVE_PATH}'"

	fi

}

verify_server_startup() {

	SERVER_IS_UP=false

	for i in $(seq 1 "${RETRIES}"); do

		SERVER_TO_START=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

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

			rest_call "$ADMIN_BASE_URL/info"

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

restart_server() {

	if [ ! -z "${SERVER_PATH}" ]; then

		echo_step "Starting server"

		chmod +x $SERVER_PATH/bin/*.sh

		screen -d -m -S "$(basename ${SERVER_PATH})" -t "${SERVER_PATH}" "${SERVER_PATH}/bin/startup.sh"

		verify_server_startup "${SERVER_PATH}"

	fi

}

cleanup() {

	if [ -d "${TMP_DATASET_DIR}" ]; then

		echo_step "Clean up"
		if [ -d "${TMP_DATASET_DIR}/indexes" ]; then
			rm --force "${TMP_DATASET_DIR}/indexes" && echo_date "Removed symlink to 'indexes' folder"
		fi

		if [ -d "${TMP_DATASET_DIR}/store" ]; then
			rm --force "${TMP_DATASET_DIR}/store" && echo_date "Removed symlink to 'store' folder"
		fi

		rm --recursive --force ${TMP_DATASET_DIR} && echo_date "Deleted temporary backup dir @ '${TMP_DATASET_DIR}'"

	fi
}

main() {

	echo_date "################################"
	echo_date "Snow Owl backup script STARTED."

	check_variables

	find_running_snowowl_servers

	if [ "${DATABASE_TYPE}" = "mysql" ]; then
		configure_repositories
	fi

	shutdown_server

	create_backup

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then
		restart_server
	fi

	echo_date
	echo_date "Snow Owl backup script FINISHED."

	exit 0

}

trap cleanup EXIT

while getopts ":ht:d:u:p:f:j:" opt; do
	case "$opt" in
	h)
		usage
		exit 0
		;;
	t)
		TARGET_ARCHIVE_PATH=$OPTARG
		;;
	d)
		DATABASE_TYPE=$OPTARG
		;;
	u)
		MYSQL_USER=$OPTARG
		;;
	p)
		MYSQL_USER_PASSWORD=$OPTARG
		;;
	f)
		SNOWOWL_USER=$OPTARG
		;;
	j)
		SNOWOWL_USER_PASSWORD=$OPTARG
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
