#!/bin/bash

source utils.sh

echo -e "${green}Start restore: $(date +'%Y-%m-%d %H:%M:%S')${no_color}"

# Load config
echo -e "\nConfiguration:"
parallel_count=$(config restore_parallelism)
echo -e "\tParallelism is $parallel_count."

ydb_bin_path=$(config ydb_bin_path)
echo -e "\tYDB bin path is $ydb_bin_path."

ydb_profile_name=$(config ydb_restore_profile_name)
echo -e "\tYDB profile is $ydb_profile_name."

echo

# Check ydb and connection
$ydb_bin_path -p $ydb_profile_name discovery whoami || error_exit "Couldn't connect to YDB."

# Get restore folder
restore_dir=$1

if [[  -z "$restore_dir" ]]; then
    error_exit "Please provide directory with backup."
fi

# Check that tables don't exist
tables_list_path=$restore_dir/tables.txt

tables_list_to_restore=()
while IFS= read -r line; do
    if [[ $line != .sys* ]] && [[ $line != .metadata* ]] && [[ $line != backup* ]] 
    then
        tables_list_to_restore+=($line)
    fi
done < $tables_list_path

all_tables=$($ydb_bin_path -p $ydb_profile_name scheme ls -R -l --format json | jq -r '.[] | select(.type == "table") | .path')

# Filter system objects like .sys directories
tables_list=$(delete_system_objects ${all_tables[@]})

is_table_exists=false
for table in ${tables_list[@]}; do
    for table_to_restore in ${tables_list_to_restore[@]}; do
        if [ $table == $table_to_restore ]
        then
            echo "Table \"$table\" is already exists"
            is_table_exists=true
        fi
    done
done

if [ "$is_table_exists" = true ]; then
    error_exit "Tables are already exists in destination database."
fi

# Restore tables
path_to_tables="$restore_dir/data/tables/"
data_dirs=$(ls $path_to_tables)

function restore_table {
    counter=1
    for table_dir in ${data_dirs[@]}; do
        if (( $(($counter % $parallel_count )) == $1 )); then
            path=$(cat "$path_to_tables/$table_dir/path.txt")
            echo -e "\tThread $1, counter $counter, restore table $path_to_tables/$table_dir, path: $path"
            $ydb_bin_path -p $ydb_profile_name tools restore --path $path --input "$path_to_tables/$table_dir" || echo -e "\tCouldn't restore for path: $path_to_tables/$table_dir."
        fi
        ((counter++))
    done
}

PIDS=()
for ((i=0; i<$parallel_count; i++)); do
    restore_table $i &
    PIDS+=($!)
done

# Wait for all threads to finish
for pid in "${PIDS[@]}"; do
    wait $pid
done

# Restore views
path_to_views="$restore_dir/data/views/"
view_dirs=$(ls $path_to_views)

counter=1
for view_dir in ${views_dirs[@]}; do
    path=$(cat "$path_to_views/$view_dir/path.txt")
    echo -e "\tCounter $counter, restore view $path_to_views/$view_dir, path: $path"
    $ydb_bin_path -p $ydb_profile_name tools restore --path $path --input "$path_to_views/$view_dir" || echo -e "\tCouldn't restore for path: $path_to_views/$view_dir."
    ((counter++))
done

echo
echo -e "${green}Restore done: $(date +'%Y-%m-%d %H:%M:%S')${no_color}"