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
# Snow Owl terminology server install script
# See usage or execute the script with the -h flag to get further information.
#
# Version: 2.0
#

# Determines where the server needs to be deployed, default is /opt/snowowl
DEPLOYMENT_FOLDER="/opt/snowowl"

# The server archive path that needs to be deployed
SERVER_ARCHIVE_PATH=""

# The dataset specifier for installing and configuring locally
DATASET_ARCHIVE_PATH=""

# The path to Snow Owl's config file to override the default
SNOWOWL_CONFIG_PATH=""

# MySQL user with database creation privileges
MYSQL_USERNAME=""

# Password for MySQL user with database creation privileges
MYSQL_PASSWORD=""

# Global path to server deployments
GENERIC_SERVER_PATH=""

# Path to the latest server folder
LATEST_SERVER_SYMLINK_PATH=""

# Variable to store the path of the newly installed server
SERVER_PATH=""

# The containing folder of the server within the provided archive
SERVER_PATH_WITHIN_ARCHIVE=""

# Variable used for storing the currently running Snow Owl server's path
RUNNING_SERVER_PATH=""

# SHA1 value of the existing server
EXISTING_SERVER_SHA1=""

# Path to the sha1 value of the current server
EXISTING_SERVER_SHA1_PATH=""

# SHA1 value of the incoming server
INCOMING_SERVER_SHA1=""

# Global path to resources: indexes, defaults, snomedicons
GENERIC_RESOURCES_PATH=""

# The containing folder of the indexes within the provided dataset archive
INDEXES_FOLDER_WITHIN_ARCHIVE=""

# The containing folder of the SQL files within the provided dataset archive
SQL_FOLDER_WITHIN_ARCHIVE=""

# SHA1 value of the existing dataset
EXISTING_DATASET_SHA1=""

# Path to the sha1 value of the current dataset
EXISTING_DATASET_SHA1_PATH=""

# SHA1 value of the incoming dataset
INCOMING_DATASET_SHA1=""

# Flag to indicate if the dataset needs to reloaded regardless of the existing SHA1 value
FORCE_RELOAD="false"

# Global path to logs
GENERIC_LOG_PATH=""

# The number of retries to wait for e.g. server shutdown or log file creation
RETRIES=15

# The number of seconds to wait between retries
RETRY_WAIT_SECONDS=1

# The default MySQL username for the Snow Owl terminology server
SNOWOWL_MYSQL_USER="snowowl"

# The default MySQL password for the Snow Owl terminology server
SNOWOWL_MYSQL_PASSWORD="snowowl"

# The anchor file in a server archive which is always in the root of the server folder. This is
# used for identifying the server folder inside an archive with subfolders.
SERVER_ANCHOR_FILE="snowowl_config.yml"

# The indexes anchor folder in a dataset archive.
# This is used for identifying the index folder inside an archive with subfolders.
INDEXES_ANCHOR="indexes"

# The anchor file for SQL files.
# This is used for identifying the folder which contains the SQL files inside an archive with subfolders.
SQL_ANCHOR="snomedStore.sql"

# The anchor for identifying the H2 store folder inside a datatset archive
H2_ANCHOR="snomedStore.h2.db"

# Variable to determine the local MySQL instance
MYSQL=$(which mysql)

# The LDAP server's hostname
LDAP_HOST=""

# The LDAP password
LDAP_PASSWORD="secret"

# List of all known database names used by the Snow Owl terminology server
DATABASES=(atcStore icd10Store icd10amStore icd10cmStore icd10ukStore localterminologyStore
	loincStore mappingsetStore opcsStore sddStore snomedStore umlsStore valuesetStore)

# Enviromental variable used by Jenkins
export BUILD_ID=dontKillMe

export JAVA_HOME=/opt/jdk1.7.0_80

usage() {

	cat <<EOF
NAME:

    Snow Owl terminology server install script

OPTIONS:
	This script can be used for deploying Snow Owl terminology server / dataset
	in the following scenarios:
		- clean install of a server with empty dataset
		- clean install of a server with a provided dataset
		- upgrading to a newer server version without modifying the existing dataset
		- upgrading to a newer version of dataset without modifying the currently running server
		- updating MySQL content from a provided dataset.

NOTES:

	Mandatory variables must be filled in before executing the script. These are:
		- MySQL user with root privileges and it's password (to create the necessary
		  SQL user/databases/tables)
		- the desired MySQL user and password for the Snow Owl terminology server
	Optional variables:
		- path to deployment folder default is under /opt/snowowl

    -f      (deployment folder): If set the snowowl server will be deployed under this folder (default /opt/snowowl/)

    -s		(server path): If set the server will be extracted under the deployment folder

    -d		(dataset path): If set the script will try load the dataset specified at the path

    -c		(configuration path): If set the script will try to overwrite the existing configuration file

    -h      (help): displays this help

    -u      (mysql username): username for the mysql user on the server

    -p      (mysql password): password for the mysql user on the server

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

check_not_empty() {

	if [ -z "$1" ]; then
		echo_exit "$2"
	fi

}

check_if_file_exists() {

	if [ ! -f "$1" ]; then
		echo_exit "$2"
	fi

}

execute_mysql_statement() {
	${MYSQL} --user=${MYSQL_USERNAME} --password=${MYSQL_PASSWORD} --execute="$1" >/dev/null 2>&1 && echo_date "$2"
}

check_variables() {

	check_not_empty "${MYSQL_USERNAME}" "MySQL username must be specified"
	check_not_empty "${MYSQL_PASSWORD}" "MySQL password must be specified"
	check_not_empty "${DEPLOYMENT_FOLDER}" "Deployment folder must be specified"
	check_not_empty "${LDAP_HOST}" "LDAP host must be specified"

	if [ ! -z "${SERVER_ARCHIVE_PATH}" ]; then
		check_if_file_exists "${SERVER_ARCHIVE_PATH}" "Server archive does not exist at the specified path: '${SERVER_ARCHIVE_PATH}'"
	fi

	if [ ! -z "${DATASET_ARCHIVE_PATH}" ]; then
		check_if_file_exists "${DATASET_ARCHIVE_PATH}" "Dataset archive does not exist at the specified path: '${DATASET_ARCHIVE_PATH}'"
	elif [ "${FORCE_RELOAD}" = "true" ]; then
		echo_exit "Dataset archive must be specified if force reload is set"
	fi

	if [ ! -z "${SNOWOWL_CONFIG_PATH}" ]; then
		check_if_file_exists "${SNOWOWL_CONFIG_PATH}" "Snow Owl config file does not exist at the specified path: '${SNOWOWL_CONFIG_PATH}'"
	fi

	if [ ! -d "${DEPLOYMENT_FOLDER}" ]; then
		mkdir "${DEPLOYMENT_FOLDER}"
	fi

	GENERIC_SERVER_PATH="${DEPLOYMENT_FOLDER}/server"
	LATEST_SERVER_SYMLINK_PATH="${GENERIC_SERVER_PATH}/latest"
	GENERIC_RESOURCES_PATH="${DEPLOYMENT_FOLDER}/resources"
	GENERIC_LOG_PATH="${DEPLOYMENT_FOLDER}/logs"

	EXISTING_SERVER_SHA1_PATH="${DEPLOYMENT_FOLDER}/currentServer"
	EXISTING_DATASET_SHA1_PATH="${DEPLOYMENT_FOLDER}/currentDataset"

	if [ ! -d "${GENERIC_SERVER_PATH}" ]; then
		mkdir "${GENERIC_SERVER_PATH}"
	fi

	if [ ! -d "${GENERIC_RESOURCES_PATH}" ]; then
		mkdir "${GENERIC_RESOURCES_PATH}"
	fi

	if [ ! -d "${GENERIC_LOG_PATH}" ]; then
		mkdir "${GENERIC_LOG_PATH}"
	fi

}

scan_archives() {

	echo_step "Inspecting archives"

	if [ ! -z "${SERVER_ARCHIVE_PATH}" ]; then

		CONFIG_LOCATION=$(unzip -l $SERVER_ARCHIVE_PATH | grep $SERVER_ANCHOR_FILE | sed 's/ /\n/g' | tail -n1 | sed 's/ //g')

		if [ -z "${CONFIG_LOCATION}" ]; then
			echo_exit "Unable to locate Snow Owl server within '${SERVER_ARCHIVE_PATH}'"
		else
			SERVER_PATH_WITHIN_ARCHIVE=$(dirname "$CONFIG_LOCATION")
			if [ "${SERVER_PATH_WITHIN_ARCHIVE}" = "." ]; then
				echo_date "Found Snow Owl server in the root of '${SERVER_ARCHIVE_PATH}'"
			else
				echo_date "Found Snow Owl server within the provided archive: '${SERVER_ARCHIVE_PATH}/${SERVER_PATH_WITHIN_ARCHIVE}'"
			fi
		fi

	fi

	if [ ! -z "${DATASET_ARCHIVE_PATH}" ]; then

		INDEXES_FOLDER_LOCATION=$(unzip -l $DATASET_ARCHIVE_PATH | grep $INDEXES_ANCHOR/$ | sed 's/ /\n/g' | tail -n1 | sed 's/ //g')

		if [ -z "${INDEXES_FOLDER_LOCATION}" ]; then
			echo_exit "Unable to locate indexes folder within '${DATASET_ARCHIVE_PATH}'"
		else

			INDEXES_FOLDER_WITHIN_ARCHIVE=${INDEXES_FOLDER_LOCATION%/}

			if [ ! -z "${INDEXES_FOLDER_WITHIN_ARCHIVE}" ]; then
				echo_date "Found indexes folder in: '${DATASET_ARCHIVE_PATH}/${INDEXES_FOLDER_WITHIN_ARCHIVE}'"
			fi

			SQL_FOLDER_LOCATION=$(unzip -l $DATASET_ARCHIVE_PATH | grep $SQL_ANCHOR | sed 's/ /\n/g' | tail -n1 | sed 's/ //g')

			if [ ! -z "${SQL_FOLDER_LOCATION}" ]; then

				SQL_FOLDER_WITHIN_ARCHIVE=$(dirname "${SQL_FOLDER_LOCATION}")

				if [ "${SQL_FOLDER_WITHIN_ARCHIVE}" = "." ]; then
					echo_date "Found SQL files in the root of '${DATASET_ARCHIVE_PATH}'"
				else
					echo_date "Found SQL files in: '${DATASET_ARCHIVE_PATH}/${SQL_FOLDER_WITHIN_ARCHIVE}'"
				fi

			else
				echo_date "No SQL files found in the provided dataset archive"
			fi
			
			H2_STORE_LOCATION=$(unzip -l $DATASET_ARCHIVE_PATH | grep $H2_ANCHOR | sed 's/ /\n/g' | tail -n1 | sed 's/ //g')
			
			if [ ! -z "${H2_STORE_LOCATION}" ]; then

				H2_FOLDER_WITHIN_ARCHIVE=$(dirname "${H2_STORE_LOCATION}")

				if [ "${H2_FOLDER_WITHIN_ARCHIVE}" = "." ]; then
					echo_date "Found H2 files in the root of '${DATASET_ARCHIVE_PATH}'"
				else
					echo_date "Found H2 files in: '${DATASET_ARCHIVE_PATH}/${H2_FOLDER_WITHIN_ARCHIVE}'"
				fi
				
			fi

		fi

	fi

}

find_running_snowowl_servers() {

	echo_step "Searching for running server instances"

	RUNNING_SERVER_PATH=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

	if [ ! -z "${RUNNING_SERVER_PATH}" ]; then
		echo_date "Found running Snow Owl server instance @ '${RUNNING_SERVER_PATH}'"
	else
		echo_date "No running Snow Owl server found."
	fi

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

check_server_sha() {

	echo_step "Checking server SHA1 value"

	# Cuts the filename from the sha1
	INCOMING_SERVER_SHA1=$(sha1sum "${SERVER_ARCHIVE_PATH}" | sed -e 's/\s.*$//')

	if [ -f "${EXISTING_SERVER_SHA1_PATH}" ]; then

		# Reads the sha1 value from the file
		EXISTING_SERVER_SHA1=$(<${EXISTING_SERVER_SHA1_PATH})

		if [ ! -z "${EXISTING_SERVER_SHA1}" ]; then
			if [ "${INCOMING_SERVER_SHA1}" != "${EXISTING_SERVER_SHA1}" ]; then
				echo_date "Differing server version found, the provided archive will be installed."
				unzip_server
			else

				echo_date "The specified server archive is already installed."

				if [ ! -z "${RUNNING_SERVER_PATH}" ]; then
					SERVER_PATH="${RUNNING_SERVER_PATH}"
				elif [ -d "${LATEST_SERVER_SYMLINK_PATH}/bin" ]; then
					SERVER_PATH="${LATEST_SERVER_SYMLINK_PATH}"
				fi

			fi
		else
			echo_date "SHA1 value is missing, the provided archive will be installed."
			unzip_server
		fi

	else
		echo_date "SHA1 value is missing, the provided archive will be installed."
		unzip_server
	fi
}

unzip_server() {

	echo_step "Unzipping server archive"

	# create server SHA1 file if not exists
	touch "${EXISTING_SERVER_SHA1_PATH}"

	# copy incoming SHA1 value into existing
	echo "${INCOMING_SERVER_SHA1}" >"${EXISTING_SERVER_SHA1_PATH}"

	TMP_SERVER_DIR=$(mktemp -d --tmpdir="${DEPLOYMENT_FOLDER}")

	unzip -q "${SERVER_ARCHIVE_PATH}" -d "${TMP_SERVER_DIR}"

	FOLDER_NAME=""
	CURRENT_DATE=$(date +%Y%m%d_%H%M%S)

	if [ "${SERVER_PATH_WITHIN_ARCHIVE}" = "." ]; then
		FILENAME=$(basename $SERVER_ARCHIVE_PATH)
		FOLDER_NAME=$(echo ${FILENAME%.*})"_${CURRENT_DATE}"
	else
		FOLDER_NAME=$(basename $SERVER_PATH_WITHIN_ARCHIVE)"_${CURRENT_DATE}"
	fi

	SERVER_PATH="${GENERIC_SERVER_PATH}/${FOLDER_NAME}"

	if [ ! -d "${SERVER_PATH}" ]; then
		mkdir "${SERVER_PATH}"
	fi

	if [ "${SERVER_PATH_WITHIN_ARCHIVE}" = "." ]; then
		mv -t "${SERVER_PATH}" "${TMP_SERVER_DIR}/"*
	else
		mv -t "${SERVER_PATH}" "${TMP_SERVER_DIR}/${SERVER_PATH_WITHIN_ARCHIVE}/"*
	fi

	echo_date "Extracted server files to: '${SERVER_PATH}'"

	# logs

	if [ ! -d "${SERVER_PATH}/serviceability" ]; then
		mkdir "${SERVER_PATH}/serviceability"
	fi

	SERVER_LOG_PATH="${SERVER_PATH}/serviceability/logs"

	if [ -d "${SERVER_LOG_PATH}" ]; then
		rm --recursive --force "${SERVER_LOG_PATH}"
	fi

	ln -sf "${GENERIC_LOG_PATH}" "${SERVER_LOG_PATH}"
	echo_date "Logs symlink points from: '${SERVER_LOG_PATH}' to '${GENERIC_LOG_PATH}'"

	# resources

	SERVER_RESOURCES_PATH="${SERVER_PATH}/resources"

	if [ -d "${SERVER_RESOURCES_PATH}" ]; then
		\cp --recursive --force --target-directory="${GENERIC_RESOURCES_PATH}" "${SERVER_RESOURCES_PATH}/"* && rm --recursive --force "${SERVER_RESOURCES_PATH}"
	fi

	ln -sf "${GENERIC_RESOURCES_PATH}" "${SERVER_RESOURCES_PATH}"
	echo_date "Resources symlink points from '${SERVER_RESOURCES_PATH}' to '${GENERIC_RESOURCES_PATH}'"

	# latest server folder

	rm --recursive --force "${LATEST_SERVER_SYMLINK_PATH}"

	ln -sf "${SERVER_PATH}" "${LATEST_SERVER_SYMLINK_PATH}"

	echo_date "Latest server symlink points from: '${LATEST_SERVER_SYMLINK_PATH}' to '${SERVER_PATH}'"

	configure_ldap_host

}

configure_ldap_host() {

	JAAS_CONFIG_LOCATION=$(find $SERVER_PATH -type f ! -path '*.jar*' -name '*jaas_config*.conf')

	# set LDAP url

	OLD_VALUE=$(grep -Eo 'ldap://[^ ]+/' $JAAS_CONFIG_LOCATION)

	LDAP_URL="ldap://${LDAP_HOST}:10389/"

	sed -i 's,'"$OLD_VALUE"','"$LDAP_URL"',' $JAAS_CONFIG_LOCATION

	echo_date "Setting LDAP host to '$LDAP_URL'"

	# set LDAP password

	if [ "$LDAP_PASSWORD" != "secret" ]; then

		OLD_VALUE=$(grep -Eo 'bindDnPassword="[^ ]+"' $JAAS_CONFIG_LOCATION)

		NEW_VALUE="bindDnPassword=\"$LDAP_PASSWORD\""

		sed -i 's,'"$OLD_VALUE"','"$NEW_VALUE"',' $JAAS_CONFIG_LOCATION

		echo_date "Setting LDAP password to '$LDAP_PASSWORD'"

	fi

}

check_dataset_sha() {

	echo_step "Checking dataset SHA1 value"

	# Cuts the filename from the sha1
	INCOMING_DATASET_SHA1=$(sha1sum "${DATASET_ARCHIVE_PATH}" | sed -e 's/\s.*$//')

	if [ -f "${EXISTING_DATASET_SHA1_PATH}" ]; then

		EXISTING_DATASET_SHA1=$(<${EXISTING_DATASET_SHA1_PATH})

		if [ ! -z "${EXISTING_DATASET_SHA1}" ]; then
			if [ "${FORCE_RELOAD}" = "true" ]; then
				unzip_and_load_dataset
			else
				if [ "${INCOMING_DATASET_SHA1}" != "${EXISTING_DATASET_SHA1}" ]; then
					echo_date "Differing dataset version found, the provided archive will be loaded."
					unzip_and_load_dataset
				else
					echo_date "The specified dataset is already loaded."
				fi
			fi
		else
			echo_date "SHA1 value is missing, the provided archive will be loaded."
			unzip_and_load_dataset
		fi
	else
		echo_date "SHA1 value is missing, the provided archive will be loaded."
		unzip_and_load_dataset
	fi
}

setup_mysql_content() {

	echo_step "Setting up MySQL content..."

	SNOWOWL_USER_EXISTS=false

	while read USER; do
		if [[ "${SNOWOWL_MYSQL_USER}" == "${USER}" ]]; then
			SNOWOWL_USER_EXISTS=true
			break
		fi
	done < <(${MYSQL} --user=${MYSQL_USERNAME} --password=${MYSQL_PASSWORD} \
		--batch --skip-column-names --execute='use mysql; SELECT `user` FROM `user`;' >/dev/null 2>&1)

	if [ "$SNOWOWL_USER_EXISTS" = false ]; then
		execute_mysql_statement "CREATE USER '${SNOWOWL_MYSQL_USER}'@'localhost' identified by '${SNOWOWL_MYSQL_PASSWORD}';" \
			"Created '${SNOWOWL_MYSQL_USER}' MySQL user with password '${SNOWOWL_MYSQL_PASSWORD}'."
	fi

	for i in "${DATABASES[@]}"; do
		execute_mysql_statement "DROP DATABASE \`${i}\`;" "Dropped database ${i}."
	done

	EXISTING_SQL_FILES=$(find "${GENERIC_RESOURCES_PATH}" -type f -name '*.sql')

	if [ ! -n "${EXISTING_SQL_FILES}" ]; then

		echo_date "Creating empty databases..."

		for i in "${DATABASES[@]}"; do

			DATABASE_NAME=${i}

			execute_mysql_statement "CREATE DATABASE \`${DATABASE_NAME}\` DEFAULT CHARSET 'utf8';" "Created database ${DATABASE_NAME}."
			execute_mysql_statement "GRANT ALL PRIVILEGES ON \`${DATABASE_NAME}\`.* to '${SNOWOWL_MYSQL_USER}'@'localhost';" \
				"Granted all privileges on ${DATABASE_NAME} to '${SNOWOWL_MYSQL_USER}@localhost'."

		done

	else

		for i in ${EXISTING_SQL_FILES}; do

			BASENAME=$(basename ${i})
			DATABASE_NAME=${BASENAME%.sql}

			execute_mysql_statement "CREATE DATABASE \`${DATABASE_NAME}\` DEFAULT CHARSET 'utf8';" "Created database ${DATABASE_NAME}."
			execute_mysql_statement "GRANT ALL PRIVILEGES ON \`${DATABASE_NAME}\`.* to '${SNOWOWL_MYSQL_USER}'@'localhost';" \
				"Granted all privileges on ${DATABASE_NAME} to '${SNOWOWL_MYSQL_USER}@localhost'."

			echo_date "Loading ${BASENAME}..."
			${MYSQL} --user=${MYSQL_USERNAME} --password=${MYSQL_PASSWORD} "${DATABASE_NAME}" <"${i}" >/dev/null 2>&1 &&
				echo_date "Loading of ${BASENAME} finished."

		done

	fi

	execute_mysql_statement "FLUSH PRIVILEGES;" "Reloaded grant tables."

}

unzip_and_load_dataset() {

	echo_step "Unzipping dataset"

	# Saving sha1 value of the new dataset
	touch "${EXISTING_DATASET_SHA1_PATH}"
	echo "${INCOMING_DATASET_SHA1}" >"${EXISTING_DATASET_SHA1_PATH}"

	rm --recursive --force "${GENERIC_RESOURCES_PATH}/indexes"
	rm --recursive --force "${GENERIC_RESOURCES_PATH}/store"
	rm --recursive --force "${GENERIC_RESOURCES_PATH}"/*.sql

	mkdir "${GENERIC_RESOURCES_PATH}/indexes"

	TMP_DATASET_DIR=$(mktemp -d --tmpdir="${DEPLOYMENT_FOLDER}")

	if [ ! -z "${INDEXES_FOLDER_WITHIN_ARCHIVE}" ]; then

		unzip -q "${DATASET_ARCHIVE_PATH}" "${INDEXES_FOLDER_WITHIN_ARCHIVE}/"* -d "${TMP_DATASET_DIR}"

		if [ ! -z "$(ls -A ${TMP_DATASET_DIR}/${INDEXES_FOLDER_WITHIN_ARCHIVE})" ]; then
			mv -t "${GENERIC_RESOURCES_PATH}/indexes" "${TMP_DATASET_DIR}/${INDEXES_FOLDER_WITHIN_ARCHIVE}/"*
		fi

		echo_date "Extracted indexes folder to: '${GENERIC_RESOURCES_PATH}/indexes'"
		
	fi

	if [ ! -z "${SQL_FOLDER_WITHIN_ARCHIVE}" ]; then

		if [ "${SQL_FOLDER_WITHIN_ARCHIVE}" = "." ]; then
			unzip -q "${DATASET_ARCHIVE_PATH}" "*.sql" -d "${TMP_DATASET_DIR}"
			mv -t "${GENERIC_RESOURCES_PATH}" "${TMP_DATASET_DIR}/"*.sql
		else
			unzip -q "${DATASET_ARCHIVE_PATH}" "${SQL_FOLDER_WITHIN_ARCHIVE}/"*.sql -d "${TMP_DATASET_DIR}"
			mv -t "${GENERIC_RESOURCES_PATH}" "${TMP_DATASET_DIR}/${SQL_FOLDER_WITHIN_ARCHIVE}/"*.sql
		fi
		
		echo_date "Extracted SQL files to: '${GENERIC_RESOURCES_PATH}'"

	fi

	if [ ! -z "${H2_FOLDER_WITHIN_ARCHIVE}" ]; then
	
		if [ "${H2_FOLDER_WITHIN_ARCHIVE}" = "." ]; then
			unzip -q "${DATASET_ARCHIVE_PATH}" "*.db" -d "${TMP_DATASET_DIR}"
			mv -t "${GENERIC_RESOURCES_PATH}/store" "${TMP_DATASET_DIR}/"*.db
		else
			unzip -q "${DATASET_ARCHIVE_PATH}" "${H2_FOLDER_WITHIN_ARCHIVE}/"*.db -d "${TMP_DATASET_DIR}"
			mv -t "${GENERIC_RESOURCES_PATH}/store" "${TMP_DATASET_DIR}/${H2_FOLDER_WITHIN_ARCHIVE}/"*.db
		fi
		
		echo_date "Extracted H2 database files to: '${GENERIC_RESOURCES_PATH}/store'"
		
	else
	
		# load MySQL content only when there is no H2 database in the dataset archive		
		setup_mysql_content
		
	fi

}

setup_configuration() {

	if [ ! -z "${SERVER_PATH}" ]; then
		echo_step "Configuring Snow Owl"

		\cp --force --target-directory="${DEPLOYMENT_FOLDER}" "${SNOWOWL_CONFIG_PATH}"

		rm --force "$SERVER_PATH/snowowl_config.yml"

		ln -sf "${DEPLOYMENT_FOLDER}/snowowl_config.yml" "${SERVER_PATH}/snowowl_config.yml"
		echo_date "Snow Owl's config symlink points from '${SERVER_PATH}/snowowl_config.yml' to '${DEPLOYMENT_FOLDER}/config.yml'"
	fi

}

verify_server_startup() {

	SERVER_IS_UP=false

	for i in $(seq 1 "${RETRIES}"); do

		SERVER_TO_START=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

		if [ -z "${SERVER_TO_START}" ]; then
			sleep "${RETRY_WAIT_SECONDS}"s
		else
			echo_date "Server started @ '${SERVER_TO_START}'"
			SERVER_IS_UP=true
			break
		fi

	done

	if [ "${SERVER_IS_UP}" = false ]; then
		echo_exit "Unable to start server @ '$1' after $((${RETRIES} * ${RETRY_WAIT_SECONDS})) seconds"
	fi

}

start_server() {

	if [ ! -z "${SERVER_PATH}" ]; then

		echo_step "Starting server"

		chmod +x $SERVER_PATH/bin/*.sh

		screen -d -m -S "$(basename ${SERVER_PATH})" -t "${SERVER_PATH}" "${SERVER_PATH}/bin/startup.sh"

		verify_server_startup "${SERVER_PATH}"

	fi

}

cleanup() {

	if [ -d "${TMP_SERVER_DIR}" ] || [ -d "${TMP_DATASET_DIR}" ]; then

		echo_step "Clean up"

		if [ -d "${TMP_SERVER_DIR}" ]; then
			rm --recursive --force ${TMP_SERVER_DIR} && echo_date "Deleted temporary server dir @ '${TMP_SERVER_DIR}'"
		fi

		if [ -d "${TMP_DATASET_DIR}" ]; then
			rm --recursive --force ${TMP_DATASET_DIR} && echo_date "Deleted temporary dataset dir @ '${TMP_DATASET_DIR}'"
		fi

	fi
}

main() {

	echo_date "################################"
	echo_date "Snow Owl install script STARTED."

	check_variables

	scan_archives

	find_running_snowowl_servers

	shutdown_server

	if [ ! -z "$SERVER_ARCHIVE_PATH" ]; then
		check_server_sha
	fi

	if [ ! -z "$DATASET_ARCHIVE_PATH" ]; then
		check_dataset_sha
	fi

	if [ ! -z "$SNOWOWL_CONFIG_PATH" ]; then
		setup_configuration
	fi

	start_server

	echo_date
	echo_date "Snow Owl install script FINISHED."

	exit 0
}

trap cleanup EXIT

while getopts ":hf:s:d:r:c:u:p:l:" opt; do
	case "$opt" in
	h)
		usage
		exit 0
		;;
	f)
		DEPLOYMENT_FOLDER=$OPTARG
		;;
	s)
		SERVER_ARCHIVE_PATH=$OPTARG
		;;
	d)
		DATASET_ARCHIVE_PATH=$OPTARG
		;;
	r)
		FORCE_RELOAD=$OPTARG
		;;
	c)
		SNOWOWL_CONFIG_PATH=$OPTARG
		;;
	u)
		MYSQL_USERNAME=$OPTARG
		;;
	p)
		MYSQL_PASSWORD=$OPTARG
		;;
	l)
		LDAP_HOST=$OPTARG
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
