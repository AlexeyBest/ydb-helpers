#!/bin/bash
source utils.sh

# Logging
init_logging "backup"

start_datetime=$(date +'%Y-%m-%d %H:%M:%S')
echo -e "${green}Start backup: ${start_datetime}${no_color}\n"

# Load config
log_message "Configuration:"
parallel_count=$(config backup_parallelism)
log_message "\tParallelism is $parallel_count."

ydb_bin_path=$(config ydb_bin_path)
log_message "\tYDB bin path is $ydb_bin_path."

ydb_profile_name=$(config ydb_backup_profile_name)
log_message "\tYDB profile is $ydb_profile_name."

backup_view=$(config backup_view)
log_message "\tBackup view: $backup_view."

echo

# Check ydb and connection
$ydb_bin_path -p $ydb_profile_name discovery whoami || error_exit "Couldn't connect to YDB."

# Backup all metadata
backup_name="backup_$(date +'%Y%m%d_%H%M%S')"
backup_dir="$(config backup_directory)/$backup_name"
log_message "Backup directory: $backup_dir"
mkdir -p $backup_dir

remove_snapshot() {
    $ydb_bin_path -p $ydb_profile_name scheme rmdir -r -f $backup_name
}

# Get full list of databse objects
database_scheme_path=$backup_dir/database_scheme.json
$ydb_bin_path -p $ydb_profile_name scheme ls -R -l --format json > $database_scheme_path || error_exit "Couldn't get scheme."
log_message "Database scheme saved here: $database_scheme_path"

# Read list of table, ordered by size (desc)
all_tables=$(cat $database_scheme_path | jq -r 'sort_by(.size) | reverse | .[] | select(.type == "table") | .path' || error_exit "Couldn't get tables from database scheme JSON.")
# Filter system objects like .sys directories
tables_to_backup=$(delete_system_objects ${all_tables[@]})

# Create dirs for backup
all_dirs=$(cat $database_scheme_path | jq -r '.[] | select(.type == "dir") | .path' || error_exit "Couldn't get dirs from database scheme JSON.")

$ydb_bin_path -p $ydb_profile_name scheme mkdir $backup_name || error_exit "Couldn't create directory $backup_name in YDB."

dir_list_path=$backup_dir/dirs.txt
for dirs in ${all_dirs[@]}; do
    if [[ $dirs != .* ]] && [[ $dirs != backup* ]]
    then
        $ydb_bin_path -p $ydb_profile_name scheme mkdir $backup_name/$dirs || error_exit "Couldn't create directory $backup_name/$dirs in YDB."
        echo $dirs >> $dir_list_path
    fi
done

# Backup tables in YDB
tools_copy_args=""
for table in ${tables_to_backup[@]}; do
    tools_copy_args="$tools_copy_args --item d=$backup_name/$table,s=$table"
done

$ydb_bin_path -p $ydb_profile_name tools copy $tools_copy_args || error_exit "Couldn't make copies of tables in YDB."

# Backup data
data_dir=$backup_dir/data/tables
mkdir -p $data_dir

tables_list_path=$backup_dir/tables.txt

function dump_table {
    counter=1
    for table in ${tables_to_backup[@]}; do
        if (( $(($counter % $parallel_count )) == $1 )); then
            dump_dir=$data_dir/"$(printf "%04d\n" $1)_$(printf "%04d\n" $counter)"
            mkdir -p $dump_dir
            mkdir -p "$log_dir/dumps"
            log_message "\tTable: $table (thread $1, counter $counter, dump table $backup_name/$table to $dump_dir)"
            $ydb_bin_path -p $ydb_profile_name tools dump -p $backup_name/$table -o $dump_dir --avoid-copy > "$log_dir/dumps/$(printf "%04d\n" $1)_$(printf "%04d\n" $counter).log" || error_exit "Couldn't backup table $backup_name/$table."
            echo $table >> $tables_list_path
            if [[ $table == *"/"* ]]; then
                get_path $table >> "$dump_dir/path.txt"
            else
                echo "." > "$dump_dir/path.txt"
            fi
        fi
        ((counter++))
    done
}

PIDS=()
for ((i=0; i<$parallel_count; i++)); do
    dump_table $i &
    PIDS+=($!)
done

# Wait for all threads to finish
for pid in "${PIDS[@]}"; do
    wait $pid
    exit_status=$?
    if (( $exit_status > 0 )); then
        error_exit "Expected exit status 0, but it's $exit_status for 'ydb tools dump'"
    else 
        log_message "Pid $pid, exit status is $exit_status"
    fi
done

view_dir=$backup_dir/data/views
mkdir -p $view_dir

# Dump view
if [ $backup_view = true ]
then
    views_list_path=$backup_dir/views.txt

    all_views=$(cat $database_scheme_path | jq -r '.[] | select(.type == "view") | .path' || error_exit "Couldn't get views from database scheme JSON.")
    # Filter system objects like .sys directories
    views_to_backup=$(delete_system_objects ${all_views[@]})

    counter=1
    for view in ${views_to_backup[@]}; do
        dump_dir=$view_dir/"$(printf "%04d\n" $counter)"
        mkdir -p $dump_dir
        log_message "\tView $view (counter $counter, dump view $view to $dump_dir)"
        $ydb_bin_path -p $ydb_profile_name tools dump -p $view -o $dump_dir --avoid-copy || error_exit "Couldn't backup view $view."
        echo $view >> $views_list_path
        if [[ $view == *"/"* ]]; then
            get_path $view >> "$dump_dir/path.txt"
        else
            echo "." > "$dump_dir/path.txt"
        fi
        ((counter++))
    done
else
    log_message "\nBackup for view is disabled by configuration.conf"
fi

# Clean up
log_message "\nDelete snapshot"
remove_snapshot

log_message "\n${green}Done: $(date +'%Y-%m-%d %H:%M:%S') (started at ${start_datetime})${no_color}"
log_message "\tBackup directory: $backup_dir"
log_message "\tBackup size: $(du -hs ${backup_dir})"
# log_message "\tMetadata: $metadata_dir"
log_message "\tData: $data_dir"
log_message "\tLog file: $log_file"