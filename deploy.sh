#!/usr/bin/env bash
#
# Copyright 2017 B2i Healthcare Pte Ltd, http://b2i.sg
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
# See usage or execute the script with the -h flag to get further information about it.
#
# Version: 1.0
#


# Determines where the server needs to be deployed default is /opt folder
DEPLOYMENT_FOLDER="/opt/snowowl"

# The following variables must be filled in before executing the script at the first time:
# Server specifier for installing and starting locally
SERVER_ARCHIVE_PATH=""

# Dataset specifier for installing and configuring locally
DATASET_ARCHIVE_PATH=""

# Server configuration file to override default configuration
CONFIGURATION_ARCHIVE_FILEPATH=""

# User for MySQL
MYSQL_USERNAME=""

# Password for MySQL
MYSQL_PASSWORD=""

# Variable to determine the local MySQL instance.
MYSQL=$(which mysql)

# Changing the following variables is NOT advised.

# The number of retries to wait for e.g. server shutdown or log file creation.
RETRIES=15

# The number of seconds to wait between retries.
RETRY_WAIT_SECONDS=1

# The MySQL username for Snow Owl server to use
SNOWOWL_MYSQL_USER="snowowl"

# The password for Snow Owl's MySQL user
SNOWOWL_MYSQL_PASSWORD="snowowl"

# A valid Snow Owl user to be able to create backups
SNOWOWL_USERNAME="user@localhost.localdomain"

# The password for the Snow Owl user given above
SNOWOWL_PASSWORD="password123"

# Variable to store the path of the newly installed server.
SERVER_PATH=""

# Variable used for storing the currently running Snow Owl server's path.
RUNNING_SERVER_PATH=""

# Variable to store the path of the newly added dataset.
DATASET_PATH=""

# Global path to the server deployments
GENERIC_SERVER_PATH="$DEPLOYMENT_FOLDER/server"

# Path to the latest folder
LATEST_SERVER_SYMLINK_PATH="$GENERIC_SERVER_PATH/latest"

# Global path to the resources deployments: indexes, defaults snomedicons, indexes
GENERIC_RESOURCES_PATH="$DEPLOYMENT_FOLDER/resources"

# Global path to the logs deployments: logs
GENERIC_LOG_PATH="$DEPLOYMENT_FOLDER/logs"

# Sha 1 value of the existing server
EXISTING_SERVER_SHA1=""

# Sha 1 value of the incoming server
INCOMING_SERVER_SHA1=""

# Sha 1 value of the existing dataset
EXISTING_DATASET_SHA1=""

# Sha 1 value of the incoming dataset
INCOMING_DATASET_SHA1=""

# List of known database names used by the Snow Owl terminology server.
DATABASES=( atcStore icd10Store icd10amStore icd10cmStore localterminologyStore \
 loincStore mappingsetStore sddStore snomedStore umlsStore valuesetStore )

# Path to the sha1 value of the current server on the server
EXISTING_SERVER_SHA1_PATH="$DEPLOYMENT_FOLDER/currentServer"

# Path to the sha1 value of the current dataset on the server
EXISTING_DATASET_SHA1_PATH="$DEPLOYMENT_FOLDER/currentDataset"

# The working folder of the script. It could change to the containing folder of the
# currently running Snow Owl server.
WORKING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

usage() {
cat << EOF
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

execute_mysql_statement() {
	${MYSQL} --user=${MYSQL_USERNAME} --password=${MYSQL_PASSWORD} --execute="$1" > /dev/null 2>&1 && echo_date "$2"
}

verify_server_startup() {

	SERVER_IS_UP=false

	for i in $(seq 1 "$RETRIES"); do

		SERVER_TO_START=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

		if [ -z "$SERVER_TO_START" ]; then
			sleep "$RETRY_WAIT_SECONDS"s
		else
			echo_date "Server started @ '$SERVER_TO_START'"
			SERVER_IS_UP=true
			break
		fi

	done

	if [ "$SERVER_IS_UP" = false ]; then
		echo_exit "Unable to start server @ '$1' after $(( $RETRIES * $RETRY_WAIT_SECONDS )) seconds"
	fi

}

start_server() {

	if [ ! -z "$SERVER_PATH" ] || [ ! -z "$RUNNING_SERVER_PATH" ]; then

			echo_step "Starting server"

			if [ ! -z "$DATASET_PATH" ]; then

				if [ ! -z "$SERVER_PATH" ]; then

					nohup "$LATEST_SERVER_SYMLINK_PATH/bin/startup.sh" > /dev/null &

					verify_server_startup ${SERVER_PATH}

				elif [ ! -z "$RUNNING_SERVER_PATH" ]; then

					verify_server_startup ${RUNNING_SERVER_PATH}

				fi

			elif [ ! -z "$SERVER_PATH" ]; then

				verify_server_startup ${SERVER_PATH}

			fi

	fi

}

check_server_sha() {
    echo_step "Unzipping server"

    # Cuts the filename from the sha1
    INCOMING_SERVER_SHA1=`sha1sum "${SERVER_ARCHIVE_PATH}" | awk '{ print $1 }'`
    if [ -e "${EXISTING_SERVER_SHA1_PATH}" ]; then

        # Reads the sha1 value from the file
        EXISTING_SERVER_SHA1=$(<${EXISTING_SERVER_SHA1_PATH})

        if [ ! "${INCOMING_SERVER_SHA1}" = "${EXISTING_SERVER_SHA1}" ]; then
            unzip_server
        fi
    else
        unzip_server
    fi
}

unzip_server() {

    echo_step "Unzipping server"

    touch ${EXISTING_SERVER_SHA1_PATH}

    echo "$INCOMING_SERVER_SHA1" > "$EXISTING_SERVER_SHA1_PATH"

    if [ ! -d "$GENERIC_SERVER_PATH" ]; then
        mkdir "$GENERIC_SERVER_PATH"
    fi

    TMP_SERVER_DIR=$(mktemp -d --tmpdir=${WORKING_DIR})

    unzip -q ${SERVER_ARCHIVE_PATH} -d ${TMP_SERVER_DIR}


    CURRENT_DATE=$(date +%Y%m%d_%H%M%S)
    FOLDER_NAME=$(basename ${SERVER_ARCHIVE_PATH})"_$CURRENT_DATE"

    if [ ! -d "$GENERIC_SERVER_PATH/"${FOLDER_NAME} ]; then
        mkdir "$GENERIC_SERVER_PATH/"${FOLDER_NAME}
    fi

    SERVER_PATH="$GENERIC_SERVER_PATH/"${FOLDER_NAME}

    mv -t ${SERVER_PATH} "$TMP_SERVER_DIR/"*
    rm -rf "$TMP_SERVER_DIR/$SERVER_ARCHIVE_PATH/"

    echo_date "Extracted server files to: '"${SERVER_PATH}"'"

    ln -sf ${SERVER_PATH} ${LATEST_SERVER_SYMLINK_PATH}

    if [ ! -d "$SERVER_PATH/serviceability/" ]; then
        mkdir "$SERVER_PATH/serviceability"
    fi

    SERVER_LOG_PATH="$SERVER_PATH/serviceability/"
    ln -sf ${GENERIC_LOG_PATH} ${SERVER_LOG_PATH}
    echo_date "created Symlink from the server logs to '"${GENERIC_LOG_PATH}"'"

    if [ -d "$SERVER_PATH/resources" ]; then
        mv -t ${GENERIC_RESOURCES_PATH} "$SERVER_PATH/resources/"*
        rm -rf "$SERVER_PATH/resources"
    fi

    echo_date "created Symlink from the server resources to '"${GENERIC_RESOURCES_PATH}"'"

    ln -sf "$GENERIC_RESOURCES_PATH" "$SERVER_PATH/"
    ln -sf "$SERVER_PATH/snowowl_config.yml" "$DEPLOYMENT_FOLDER/config.yml"
    echo_date "created Symlink from the server to '"${LATEST_SERVER_SYMLINK_PATH}"'"

}

check_dataset_sha() {

    echo_step "Unzipping dataset"

    # Cuts the filename from the sha1
    INCOMING_DATASET_SHA1=`sha1sum "${DATASET_ARCHIVE_PATH}" | awk '{ print $1 }'`

    if [ -e "${EXISTING_DATASET_SHA1_PATH}" ]; then


        EXISTING_DATASET_SHA1=$(<${EXISTING_DATASET_SHA1_PATH})

        if [ ! "${INCOMING_DATASET_SHA1}" = "${EXISTING_DATASET_SHA1}" ]; then
            unzip_dataset
        fi
    else
        unzip_dataset
    fi
}

unzip_dataset() {

    # Saving sha1 value of the new dataset
    touch ${EXISTING_DATASET_SHA1_PATH}

    echo "$INCOMING_DATASET_SHA1" > "$EXISTING_DATASET_SHA1_PATH"

    if [ ! -d "$GENERIC_RESOURCES_PATH" ]; then
        mkdir "$GENERIC_RESOURCES_PATH"
    fi

    TMP_DATASET_DIR=$(mktemp -d --tmpdir=${WORKING_DIR})

    unzip -q ${DATASET_ARCHIVE_PATH} -d ${TMP_DATASET_DIR}

    DATASET_PATH="${GENERIC_RESOURCES_PATH}"
    mv -t ${DATASET_PATH} "$TMP_DATASET_DIR/"*
    rm -rf "$TMP_DATASET_DIR/$DATASET_ARCHIVE_PATH/"

    echo_date "Extracted dataset files to: '"${DATASET_PATH}"'"

}

shutdown_server() {

    if [ ! -z "$RUNNING_SERVER_PATH" ]; then

		echo_step "Shutdown"

		"$RUNNING_SERVER_PATH/bin/shutdown.sh" > /dev/null

		SERVER_IS_DOWN=false

		for i in $(seq 1 "$RETRIES"); do

			SERVER_TO_SHUTDOWN=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

			if [ ! -z "$SERVER_TO_SHUTDOWN" ]; then
				sleep "$RETRY_WAIT_SECONDS"s
			else
				echo_date "Shutdown finished."
				SERVER_IS_DOWN=true
				break
			fi

		done

		if [ "$SERVER_IS_DOWN" = false ]; then
			echo_exit "Unable to shutdown server @ '$RUNNING_SERVER_PATH' after $(( $RETRIES * $RETRY_WAIT_SECONDS )) seconds"
		fi

	fi

}

overwrite_configuration() {

    echo_step "Overwriting configuration"
    cp "$CONFIGURATION_ARCHIVE_FILEPATH" "$DEPLOYMENT_FOLDER"

}

cleanup () {

   if [ -d "$TMP_SERVER_DIR" ] || [ -d "$TMP_DATASET_DIR" ]; then

		echo_step "Clean up"

		if [ -d "$TMP_SERVER_DIR" ]; then
			rm -rf ${TMP_SERVER_DIR} && echo_date "Deleted temporary server dir @ '$TMP_SERVER_DIR'"
		fi

		if [ -d "$TMP_DATASET_DIR" ]; then
			rm -rf ${TMP_DATASET_DIR} && echo_date "Deleted temporary dataset dir @ '$TMP_DATASET_DIR'"
		fi

	fi
}

trap cleanup EXIT

check_if_exists() {

	if [ -z "$1" ]; then
		echo_exit "$2"
	fi

}

check_variables() {

	check_if_exists "$MYSQL_USERNAME" "MySQL username must be specified"
	check_if_exists "$MYSQL_PASSWORD" "MySQL password must be specified"
	echo_step "Creating neccesary folders for the script if needed."

	if [ ! -d "$DEPLOYMENT_FOLDER" ]; then
	    mkdir  "$DEPLOYMENT_FOLDER"
	fi

    if [ ! -d "$GENERIC_RESOURCES_PATH" ]; then
        mkdir "$GENERIC_RESOURCES_PATH"
    fi

	if [ ! -d "$GENERIC_LOG_PATH" ]; then
	    mkdir "${GENERIC_LOG_PATH}"
	fi

}

find_running_snowowl_servers() {

	echo_step "Searching for running server instances"

	RUNNING_SERVER_PATH=$(ps aux | grep virgo | sed 's/-D/\n/g' | grep osgi.install.area | sed 's/=/\n/g' | tail -n1 | sed 's/ //g')

	if [ ! -z "$RUNNING_SERVER_PATH" ]; then
		echo_date "Found running Snow Owl server instance @ '"${RUNNING_SERVER_PATH}"'"
		WORKING_DIR=$(dirname "$RUNNING_SERVER_PATH")
	else
		echo_date "No running Snow Owl server found."
	fi

}

setup_mysql_content() {

	echo_date "Setting up MySQL content..."

	SNOWOWL_USER_EXISTS=false

	while read User; do
		if [[ "$SNOWOWL_MYSQL_USER" == "$User" ]]; then
			SNOWOWL_USER_EXISTS=true
			echo "if"
			break
		fi
	done < <(${MYSQL} --user=${MYSQL_USERNAME} --password=${MYSQL_PASSWORD} \
		--batch --skip-column-names --execute='use mysql; SELECT `user` FROM `user`;' > /dev/null 2>&1)

	if [ "$SNOWOWL_USER_EXISTS" = false ]; then
		execute_mysql_statement "CREATE USER '${SNOWOWL_MYSQL_USER}'@'localhost' identified by '${SNOWOWL_MYSQL_PASSWORD}';" \
			"Created '${SNOWOWL_MYSQL_USER}' MySQL user with password '${SNOWOWL_MYSQL_PASSWORD}'."
	fi

	for i in "${DATABASES[@]}";	do
		execute_mysql_statement "DROP DATABASE \`${i}\`;" "Dropped database ${i}."
	done

	if [ -z "$DATASET_PATH" ]; then

		for i in "${DATABASES[@]}"; do

			DATABASE_NAME=${i}

			execute_mysql_statement "CREATE DATABASE \`${DATABASE_NAME}\` DEFAULT CHARSET 'utf8';" "Created database ${DATABASE_NAME}."
			execute_mysql_statement "GRANT ALL PRIVILEGES ON \`${DATABASE_NAME}\`.* to '${SNOWOWL_MYSQL_USER}'@'localhost';" \
				"Granted all privileges on ${DATABASE_NAME} to '${SNOWOWL_MYSQL_USER}@localhost'."

		done

	else

		for i in $(find "$DATASET_PATH" -type f -name '*.sql'); do

			BASENAME=$(basename ${i})
			DATABASE_NAME=${BASENAME%.sql}

			execute_mysql_statement "CREATE DATABASE \`${DATABASE_NAME}\` DEFAULT CHARSET 'utf8';" "Created database ${DATABASE_NAME}."
			execute_mysql_statement "GRANT ALL PRIVILEGES ON \`${DATABASE_NAME}\`.* to '${SNOWOWL_MYSQL_USER}'@'localhost';" \
				"Granted all privileges on ${DATABASE_NAME} to '${SNOWOWL_MYSQL_USER}@localhost'."

			echo_date "Loading ${BASENAME}..."
			${MYSQL} --user=${MYSQL_USERNAME} --password=${MYSQL_PASSWORD} "${DATABASE_NAME}" < "${i}" > /dev/null 2>&1 && \
				echo_date "Loading of ${BASENAME} finished."

		done

	fi

	execute_mysql_statement "FLUSH PRIVILEGES;" "Reloaded grant tables."

}

configure_mysql_user() {

	SNOWOWL_CONFIG_LOCATION=$(find ${DEPLOYMENT_FOLDER} -type f -name '*config.yml')

	# set Snow Owl MySQL user

	if [ "$SNOWOWL_MYSQL_USER" != "snowowl" ]; then

		OLD_VALUE=$(grep -Eo 'username: [^ ]+' ${SNOWOWL_CONFIG_LOCATION})

		NEW_VALUE="username: $SNOWOWL_MYSQL_USER"

		sed -i 's,'"$OLD_VALUE"','"$NEW_VALUE"',' ${SNOWOWL_CONFIG_LOCATION}

		echo_date "Setting Snow Owl's MySQL user to '$SNOWOWL_MYSQL_USER'"

	fi

	# set Snow Owl MySQL password

	if [ "$SNOWOWL_MYSQL_PASSWORD" != "snowowl" ]; then

		OLD_VALUE=$(grep -Eo 'password: [^ ]+' ${SNOWOWL_CONFIG_LOCATION})

		NEW_VALUE="password: $SNOWOWL_MYSQL_PASSWORD"

		sed -i 's,'"$OLD_VALUE"','"$NEW_VALUE"',' ${SNOWOWL_CONFIG_LOCATION}

		echo_date "Setting Snow Owl's MySQL password to '$SNOWOWL_MYSQL_PASSWORD'"

	fi

}

main() {

    echo_date "################################"
	echo_date "Snow Owl install script STARTED."

    check_variables

    find_running_snowowl_servers

    shutdown_server

    if [ ! -z "$SERVER_ARCHIVE_PATH" ]; then
        check_server_sha
    fi

    if [ ! -z "$DATASET_ARCHIVE_PATH" ]; then
        check_dataset_sha
    fi

    if [ ! -z "$CONFIGURATION_ARCHIVE_FILEPATH" ]; then
        overwrite_configuration
    fi

    configure_mysql_user

    setup_mysql_content

    start_server

    echo_date "Snow owl install script FINISHED."
    exit 0
}

#Program entry point
while getopts f:s:d:c:hu::p:: opt; do
    case "$opt" in
        f)
            DEPLOYMENT_FOLDER=$OPTARG
            ;;
        s)
            SERVER_ARCHIVE_PATH=$OPTARG
            ;;
        d)
            DATASET_ARCHIVE_PATH=$OPTARG
            ;;
        c)
            CONFIGURATION_ARCHIVE_FILEPATH=$OPTARG
            ;;
        h)
            usage
            exit 1
            ;;
        u)
            MYSQL_USERNAME=$OPTARG
            ;;
        p)
            MYSQL_PASSWORD=$OPTARG
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



#echo "MySql username:"
#read USERNAME
#MYSQL_USERNAME=${USERNAME}
#echo "enter password"
#while IFS= read -r -s -n1 char; do
#  [[ -z ${char} ]] && { printf '\n'; break; } # ENTER pressed; output \n and break.
#  if [[ ${char} == $'\x7f' ]]; then # backspace was pressed
#      # Remove last char from output variable.
#      [[ -n ${MYSQL_PASSWORD} ]] && MYSQL_PASSWORD=${MYSQL_PASSWORD%?}
#      # Erase '*' to the left.
#      printf '\b \b'
#  else
#    # Add typed char to output variable.
#    MYSQL_PASSWORD+=${char}
#    # Print '*' in its stead.
#    printf '*'
#  fi
#done

#shift "$(( OPTIND - 1 ))"
#if [ ! -z "$USERNAME" ] && [ ! -z "$PASSWORD" ]; then
#    MYSQL_USER=${USERNAME}
#    MYSQL_PASSWORD=${PASSWORD}
#fi
#
#if [ ! -z "$s1" ] && [ ! -z "$2" ]; then
#    MYSQL_USER=$1
#    MYSQL_PASSWORD=$2
#elif [ -z "$1" ] || [ -z "$2" ]; then
#    echo_error "You must enter both the mysql username or password"
#    usage
#    exit 1
#fi
#
#if [ ! -z "$3" ]; then
#
#	echo_error "More than two parameters are not allowed."
#	usage
#	exit 1
#
#fi

main