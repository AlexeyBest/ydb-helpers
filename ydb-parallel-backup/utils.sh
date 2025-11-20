#!/bin/bash

red="\033[0;31m"
green="\033[0;32m"
no_color='\033[0m'

# Logging
log_dir="logs"
mkdir -p $log_dir
log_file="$log_dir/log_$(date +'%Y%m%d_%H%M%S').log"
is_backup=true
init_logging() {
    
    # Create path
    # log_files="$(ls $log_dir/log_* | sort -r)"
    if [ $1 = "backup" ]; then
        log_file="$log_dir/backup_$(date +'%Y%m%d_%H%M%S').log"
        log_files="$(ls $log_dir/backup_* | sort -r)"
    else
        log_file="$log_dir/restore_$(date +'%Y%m%d_%H%M%S').log"
        log_files="$(ls $log_dir/restore_* | sort -r)"
    fi
    
    # Delete an old log files
    max_log_files_count=3
    counter=1
    for old_log_file in ${log_files[@]}; do
        if (( $counter > $max_log_files_count )); then
            rm $old_log_file
        fi
        ((counter++))
    done;
}

log_message() {
    echo -e $1
    echo -e "$(date +'%Y-%m%-d %H:%M:%S')\t$1" >> $log_file
}

error_exit() {
    log_message "${red}ERROR: $1 ${no_color}"
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
            use_import_data)
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