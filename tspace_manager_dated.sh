#!/bin/bash
###############################################################
# Version: v1.1.0 tspace_manager_dated.sh for %Y-%m-%d 0nly!  #
###############################################################
#
# Wat those this script do?
# - First: it checks oldest dated directories.
# - Second: it wipes the first 5 directory`s inside the datad directories.
# - Last: if oldest dated directories are -emty- it will be wiped!
# - Final: Free space is between low and high threshold reached loop stops.
#
# Setup:
# - Modify "Start of Config" to fit your needs by adding or removing paths as necessary.
# - Test "DEBUG" the script on a sample environment to verify that it behaves as expected.
# - You can run the script manually or schedule it with cron to run at a specific time or interval.
#   0/5 * * * /path/to/tspace_manager_dated.sh
#
## Changelog
# 
################### START OF CONFIG ########################
# Configuration
MOUNT_POINT="/dev/sda"  # harddrive setting
THRESHOLD_LOW_GB=300    # 300 GB minimum space threshold
THRESHOLD_HIGH_GB=500   # 500 GB maximum space threshold

# DEBUG
DEBUG_MODE="FALSE"      # Set to TRUE for debug mode, FALSE for actual deletion
DEBUG_MAX_LOOPS=5       # Maximum debug iterations before exiting

LOG_FILE="/glftpd/tmp/delete.log"
MAX_DELETIONS_PER_SUBDIR=5  # Maximum number of content deletions per dated directory per cycle

# Directories to check
SPACE_TO_CHECK=(
    "/glftpd/site/MP3"
    "/glftpd/site/0DAYS"
    "/glftpd/site/FLAC"
)
#################### END OF CONFIG ########################

# Convert GB to bytes (binary system)
THRESHOLD_LOW=$((THRESHOLD_LOW_GB * 1024 * 1024 * 1024))
THRESHOLD_HIGH=$((THRESHOLD_HIGH_GB * 1024 * 1024 * 1024))

# Today's date
TODAY_DATE=$(date '+%Y-%m-%d')

# Function to log actions
log_action() {
    local action="$1"
    local item="$2"
    local message="$3"
    echo "$(date '+%a %b %e %T %Y') - $action $item - $message" >> "$LOG_FILE"
}

# Function to check free disk space
check_free_space() {
    df --output=avail "$MOUNT_POINT" | awk 'NR==2'
}

# Function to delete content inside a dated directory
delete_content_in_directory() {
    local dated_dir="$1"
    local deletions=0

    # Loop through the files or subdirectories inside the dated directory
    for item in "$dated_dir"/*; do
        if [ ! -e "$item" ]; then
            break
        fi

        if [ "$DEBUG_MODE" == "TRUE" ]; then
            log_action "DEBUG" "$item" "Simulating removal of content inside dated directory"
        else
            rm -rf "$item"
            log_action "DELETE" "$item" "Removed content inside dated directory to free up space"
        fi

        deletions=$((deletions + 1))
        if [ "$deletions" -ge "$MAX_DELETIONS_PER_SUBDIR" ]; then
            break
        fi
    done
}

# Function to clean up a dated directory
cleanup_dated_directory() {
    local dated_dir="$1"

    # Skip today's directory
    if [[ "$(basename "$dated_dir")" == "$TODAY_DATE" ]]; then
        log_action "INFO" "$dated_dir" "Skipped: Current dated directory (today)"
        return
    fi

    delete_content_in_directory "$dated_dir"

    # Check if the directory is empty after cleanup, and remove it if so
    if [ -z "$(ls -A "$dated_dir")" ]; then
        if [ "$DEBUG_MODE" == "TRUE" ]; then
            log_action "DEBUG" "$dated_dir" "Simulating removal of empty dated directory"
        else
            rm -rf "$dated_dir"
            log_action "DELETE" "$dated_dir" "Removed empty dated directory"
        fi
    fi
}

# Main script logic
cleanup() {
    local free_space=$(check_free_space)
    local debug_loops=0

    while [ "$free_space" -lt "$THRESHOLD_LOW" ]; do
        log_action "INFO" "Disk space check" "Free space: $((free_space / 1024 / 1024)) GB, initiating cleanup"

        local made_changes=false

        for section in "${SPACE_TO_CHECK[@]}"; do
            local dated_dirs=( $(find "$section" -mindepth 1 -maxdepth 1 -type d | sort) )
            local dated_dirs_count="${#dated_dirs[@]}"

            if [ "$dated_dirs_count" -lt 3 ]; then
                log_action "INFO" "$section" "Skipped: Less than 3 dated directories"
                continue
            fi

            for dated_dir in "${dated_dirs[@]}"; do
                cleanup_dated_directory "$dated_dir"
                made_changes=true

                # Re-check free space after each deletion
                free_space=$(check_free_space)
                if [ "$free_space" -ge "$THRESHOLD_LOW" ]; then
                    log_action "INFO" "Disk space check" "Cleanup complete: Free space is now above threshold"
                    return
                fi
            done
        done

        # If no deletions occurred in this cycle, exit the loop
        if [ "$made_changes" == "false" ]; then
            log_action "INFO" "Disk space check" "No deletions occurred in this run, exiting cleanup loop"
            break
        fi

        if [ "$DEBUG_MODE" == "TRUE" ]; then
            debug_loops=$((debug_loops + 1))
            if [ "$debug_loops" -ge "$DEBUG_MAX_LOOPS" ]; then
                log_action "INFO" "Debug Mode" "Reached maximum debug loops ($DEBUG_MAX_LOOPS), exiting loop"
                break
            fi
        fi
    done

    if [ "$free_space" -ge "$THRESHOLD_LOW" ] && [ "$free_space" -lt "$THRESHOLD_HIGH" ]; then
        log_action "INFO" "Disk space check" "Free space is between low and high threshold, ongoing cleanup is in progress"
    elif [ "$free_space" -ge "$THRESHOLD_HIGH" ]; then
        log_action "INFO" "Disk space check" "Free space is above threshold, no cleanup necessary"
    fi
}

# Run the cleanup function
cleanup
#eof
