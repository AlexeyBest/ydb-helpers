#!/bin/bash

red="\033[0;31m"
green="\033[0;32m"
no_color='\033[0m'

error_exit() {
    echo -e "${red}Error: $1 ${no_color}"
    exit 1
}

config() {
    val=$(grep -E "^$1=" configuration.conf 2>/dev/null | head -n 1 | cut -d '=' -f 2)

    if [[ $val == "" ]]
    then
        # Default values
        case $1 in
            backup_directory)
                echo -n "."
                ;;
            backup_parallelism)
                echo -n "1"
                ;;
            restore_parallelism)
                echo -n "1"
                ;;
            ydb_bin_path)
                echo -n "ydb"
                ;;
            backup_view)
                echo -n "true"
                ;;
        esac
    else
        echo -n $val
    fi
}

get_path() {
    str=$1
    last_index=0
    for (( i=0; i<${#str}; i++ )); do
        if [ ${str:$i:1} == "/" ]; then
            last_index=$i
        fi
    done

    echo "${str:0:$last_index}"
}

delete_system_objects() {
    arr=("$@")
    filtered_array=()

    for element in ${arr[@]}; do
        if [[ $element != .* ]] && [[ $element != backup* ]]
        then
            filtered_array+=($element)
        fi
    done

    echo ${filtered_array[@]}
}