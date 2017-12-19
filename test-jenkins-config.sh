#!/usr/bin/env bash

DEPLOYMENT_FOLDER=""

SERVER_ARCHIVE_PATH=""

DATASET_ARCHIVE_PATH=""

SNOWOWL_CONFIG_PATH=""

MYSQL_USERNAME=""

MYSQL_PASSWORD=""

usage() {

cat << EOF
usage goes here
EOF

}

echo_date() {
	echo -e "[`date +\"%Y-%m-%d %H:%M:%S\"`] $@"
}

echo_error() {
	echo_date "ERROR: $@" >&2
}

echo_step() {
	echo_date
	echo_date "#### $@ ####"
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

check_if_folder_exists() {

	if [ ! -d "$1" ]; then
		echo_exit "$2"
	fi

}

check_variables() {

	check_not_empty "$MYSQL_USERNAME" "MySQL username must be specified"
	check_not_empty "$MYSQL_PASSWORD" "MySQL password must be specified"
	check_not_empty "$DEPLOYMENT_FOLDER" "Deployment folder must be specified"
	check_not_empty "$SERVER_ARCHIVE_PATH" "Server archive must be specified"
	check_not_empty "$DATASET_ARCHIVE_PATH" "Dataset archive must be specified"
	check_not_empty "$SNOWOWL_CONFIG_PATH" "Snow Owl config file path must be specified"
	
	check_if_folder_exists "$DEPLOYMENT_FOLDER" "Deployment folder does not exist"
	check_if_file_exists "$SERVER_ARCHIVE_PATH" "Server archive does not exist at the specified path: '$SERVER_ARCHIVE_PATH'"
	check_if_file_exists "$DATASET_ARCHIVE_PATH" "Dataset archive does not exist at the specified path: '$DATASET_ARCHIVE_PATH'"
	check_if_file_exists "$SNOWOWL_CONFIG_PATH" "Snow Owl config file does not exist at the specified path: '$SNOWOWL_CONFIG_PATH'"

}

print_variables() {

	echo_date "Deployment folder: $DEPLOYMENT_FOLDER"
	echo_date "Server archive: $SERVER_ARCHIVE_PATH"
	echo_date "Dataset archive: $DATASET_ARCHIVE_PATH"
	echo_date "Snow Owl config file: $SNOWOWL_CONFIG_PATH"
	
	echo_date "MySQL user: $MYSQL_USERNAME"
	echo_date "MySQL pass: $MYSQL_PASSWORD"
	 
}

main() {

	echo_step "Snow Owl install script test started"
	echo_date
	
    check_variables
    
    print_variables

    echo_step "Snow Owl install script test finished"
    
    exit 0
}

while getopts ":hf:s:d:c:u:p:" opt; do
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
        c)
            SNOWOWL_CONFIG_PATH=$OPTARG
            ;;
        u)
            MYSQL_USERNAME=$OPTARG
            ;;
        p)
            MYSQL_PASSWORD=$OPTARG
            ;;
        \?)
            echo_error "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo_error "Option: -$OPTARG requires an argument" >&2
            usage
            exit 1
            ;;
    esac
done

main