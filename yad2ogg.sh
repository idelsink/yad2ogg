#!/bin/bash
#########################################################################
# Script Name: yad2ogg
# Script Version: 1.0.0
# Script Date: 12 Juli 2016
#########################################################################
#
# Based on the idea of dir2ogg
#
#########################################################################
# MIT License
#
# Copyright (c) 2016 Ingmar Delsink
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#########################################################################
# Explanation
# yad2ogg -i input_folder -o destination --copyfile "cover.jpg"
#########################################################################
# --- global parameters ---------------------------------------------
set -e          # kill script if a command fails
set -o nounset  # unset values give error
set -o pipefail # prevents errors in a pipeline from being masked
# --- include files -------------------------------------------------
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_PATH_LOCAL="${SCRIPT_PATH}"
LIBS_PATH="${SCRIPT_PATH}/libs"
LIBS_PATH_LOCAL="${SCRIPT_PATH}"
source "${LIBS_PATH}/b-log/b-log.sh"    # logging
source "${LIBS_PATH}/queue.sh"          # simple queue interface
source "${LIBS_PATH}/mutex.sh"          # simple mutex interface
source "${LIBS_PATH}/processes.sh"      # simple concurrent process management
source "${LIBS_PATH}/value-storage.sh"  # global value storage interface
source "${LIBS_PATH}/find-files.sh"     # find files

# --- global variables ----------------------------------------------
VERSION=1.0.0
APPNAME="yad2ogg"

function usage() {
    # @description prints the short usage of the script
    echo "Usage: ${APPNAME}.sh [options]"
    echo ""
    echo "    -a --ALL              Convert all supported file types"
    echo "    -c --copyfile file    Copy files over from original directory to "
    echo "                          destination directory eg. '*.cue or *.jpg'."
    echo "    -C --command          The default convert command. (default: ffmpeg)"
    echo "                          When ffmpeg is not available, this can be set to avconv"
    echo "    -f --filetypes type   File types to convert eg. 'wav flac ...'"
    echo "    -f 'alac' --ALAC      convert files of type alac"
    echo "    -f 'flac' --FLAC      convert files of type flac"
    echo "    -f 'mp3'  --MP3       convert files of type mp3"
    echo "    -f 'm4a'  --M4A       convert files of type m4a"
    echo "    -f 'ogg'  --OGG       convert files of type ogg"
    echo "    -f 'wav'  --WAV       convert files of type wav"
    echo "    -g --gui              Use a simple UI instead of logging output to stdout. (dialog)"
    echo "    -h --help             Show usage"
    echo "    -i --input dir        Input/source directory (defaults to current directory)"
    echo "    -j --jobs n           Number of concurrent convert jobs (default is 1)"
    echo "    -l --logfile file     Log to a file"
    echo "    -m --metadata         Don't keep metadata(tags) from the original files"
    echo "    -o --output dir       Destination/output directory (defaults to input directory)"
    echo "    -p --parameters param Extra conversion parameters"
    echo "    -q --quality n        Quality switch where n is a number (default 5.0)"
    echo "    -s --syslog param     Log to syslog \"logger 'param' log-message\""
    echo "                          For example: \"-s '-t my-awsome-tag'\" will result in:"
    echo "                          \"logger -t my-awsome-tag log-message\""
    echo "    -v --verbose          Add more verbosity"
    echo "    -V --version          Displays the script version"
    echo "    -w --overwrite        Overwrite existing files"
    echo "    -z --sync             Synchronize the output folder to the input folder."
    echo "                          If a file exists in the output folder but not in the "
    echo "                          input folder, it will be removed."
    echo "                          Extensions will be ignored so that a converted file"
    echo "                          will 'match' the original file"
    echo "    -Z --sync-hidden      Same as --sync but includes hidden files/folders"
    echo ""
}

INPUT_DIR="./"                  # input directory
OUTPUT_DIR="${INPUT_DIR:-"./"}" # output directory
QUALITY="5"                     # the quality for the converter switch
# "Most users agree -q 5 achieves transparency, if the source is the original or lossless."
# taken from: http://wiki.hydrogenaud.io/index.php?title=Recommended_Ogg_Vorbis
PARAMETERS=""               # optional parameters for the converter
JOBS=1                      # number of concurrent jobs (default 1)
VERBOSITY=$LOG_LEVEL_NOTICE # set starting log level
LOG_FILE=""                 # file to log to (default empty, so disabled)
SYSLOG_PARAM=""             # syslog parameters (default empty, so disabled)
COPY_FILES=()               # files to copy over from the source directory
USE_GUI=false               # use the GUI?
KEEP_METADATA=true          # keep metadata(tags)
OVERWRITE_EXISTING=false    # overwrite existing files
COUNTERPART_SYNC=false      # synchronize
COUNTERPART_HIDDEN=false    # include hidden files from counterpart check
DEFAULT_CONV_COMM="ffmpeg"  # default convert command
FILETYPES=()                # file types to convert
# file types supported
readonly SUPORTED_FILETYPES=(
    # lossless
    wav
    flac
    alac
    # lossy
    mp3
    ogg
    m4a
)
# location in supported list
readonly WAV_LIST=0
readonly FLAC_LIST=1
readonly ALAC_LIST=2
readonly MP3_LIST=3
readonly OGG_LIST=4
readonly M4A_LIST=5

# directories
readonly ROOT_DIR="/tmp"
readonly APP_DIR="${ROOT_DIR}/${APPNAME}"
readonly LOCKFILE_DIR="${APP_DIR}/lock"
readonly QUEUE_STORAGE="${APP_DIR}/queue"
readonly VARIABLE_STORAGE="${APP_DIR}/variable_storage"

# queues
readonly FILES_TO_PROCESS_QUEUE="files_to_process"          # holds files to process
readonly FILES_TO_COPY_OVER_QUEUE="files_to_copy_over"      # holds files to copy over
readonly CONVERTER_PROCESSES_QUEUE="converter_processes"    # holds PID's of processes
readonly GUI_PROCESSES_QUEUE="converter_status_processes"   # holds PID of the converter status
readonly GUI_NOTIFICATIONS_QUEUE="gui_notifications"        # all notifications that need to be displayed in the UI

# mutex names
readonly MUTEX_READ_FILES_TO_PROCESS="get_convert_file"

# some error codes to use in the file
readonly ERR_NO_MORE_FILES="no more files"
readonly ERR_MISSING_PARAMETER="missing parameter"
readonly ERR_MUTEX_TIMEOUT="mutex timeout"
readonly ERR_TYPE_NOT_SUPORTED="type not supported"

# variable access names
readonly GUI_TITLE="gui_title"
readonly GUI_TOTAL_COUNT="gui_total_count"
readonly GUI_PART_COUNT="gui_part_count"

# set aliases
shopt -s expand_aliases
alias GUI_TITLE="value_set ${GUI_TITLE}"
alias GUI_NOTIFY="queue_add ${GUI_NOTIFICATIONS_QUEUE}"
alias GUI_NOTIFY_CLEAR="\
queue_add ${GUI_NOTIFICATIONS_QUEUE} ' '; \
queue_add ${GUI_NOTIFICATIONS_QUEUE} ' '; \
queue_add ${GUI_NOTIFICATIONS_QUEUE} ' '; \
queue_add ${GUI_NOTIFICATIONS_QUEUE} ' '; "
alias GUI_TOTAL_COUNT="value_set ${GUI_TOTAL_COUNT}"
alias GUI_PART_COUNT="value_set ${GUI_PART_COUNT}"

# --- options processing --------------------------------------------
if [ $# -eq 0 ] ; then  # nothing past to the script
    usage
    exit 1;
fi
for arg in "$@"; do     # transform long options to short ones
    shift
    case "$arg" in
        "--help") set -- "$@" "-h" ;;
        "--version") set -- "$@" "-V" ;;
        "--verbose") set -- "$@" "-v" ;;
        "--gui") set -- "$@" "-g" ;;
        "--logfile") set -- "$@" "-l" ;;
        "--syslog") set -- "$@" "-s" ;;
        "--input") set -- "$@" "-i" ;;
        "--output") set -- "$@" "-o" ;;
        "--quality") set -- "$@" "-q" ;;
        "--jobs") set -- "$@" "-j" ;;
        "--copyfile") set -- "$@" "-c" ;;
        "--sync") set -- "$@" "-z" ;;
        "--sync-hidden") set -- "$@" "-Z" ;;
        "--metadata") set -- "$@" "-m" ;;
        "--overwrite") set -- "$@" "-w" ;;
        "--command") set -- "$@" "-C" ;;
        # filetypes
        "--filetypes") set -- "$@" "-f" ;;
        "--ALL") set -- "$@" "-a" ;;
        # lossless
        "--WAV") set -- "$@" "-f${SUPORTED_FILETYPES[$WAV_LIST]}" ;;
        "--FLAC") set -- "$@" "-f${SUPORTED_FILETYPES[$FLAC_LIST]}" ;;
        "--ALAC") set -- "$@" "-f${SUPORTED_FILETYPES[$ALAC_LIST]}" ;;
        # lossy
        "--MP3") set -- "$@" "-f${SUPORTED_FILETYPES[$MP3_LIST]}" ;;
        "--OGG") set -- "$@" "-f${SUPORTED_FILETYPES[$OGG_LIST]}" ;;
        "--M4A") set -- "$@" "-f${SUPORTED_FILETYPES[$M4A_LIST]}" ;;
        *) set -- "$@" "$arg"
  esac
done
# get options
while getopts "hVvgl:s:i:o:q:p:j:c:C:zZmwf:a" optname
do
    case "$optname" in
        "h")
            usage
            exit 0;
            ;;
        "V")
            echo "${APPNAME} v${VERSION}"
            exit 0;
            ;;
        "v")
            VERBOSITY=$(($VERBOSITY+100)) # increment log level
            ;;
        "g")
            USE_GUI=true
            ;;
        "l")
            LOG_FILE="${OPTARG}"
            ;;
        "s")
            SYSLOG_PARAM="${OPTARG}"
            ;;
        "i")
            INPUT_DIR="${OPTARG}"
            ;;
        "o")
            OUTPUT_DIR="${OPTARG}"
            ;;
        "q")
            QUALITY="${OPTARG}"
            ;;
        "p")
            PARAMETERS="${OPTARG}"
            ;;
        "j")
            JOBS="${OPTARG}"
            ;;
        "c")
            COPY_FILES[${#COPY_FILES[@]}]="${OPTARG}"
            ;;
        "C")
            DEFAULT_CONV_COMM="${OPTARG}"
            ;;
        "z")
            COUNTERPART_SYNC=true
            ;;
        "Z")
            COUNTERPART_SYNC=true
            COUNTERPART_HIDDEN=true
            ;;
        "m")
            KEEP_METADATA=true
            ;;
        "w")
            OVERWRITE_EXISTING=true
            ;;
        "f")
            FILETYPES[${#FILETYPES[@]}]="${OPTARG}"
            ;;
        "a")
            FILETYPES=${SUPORTED_FILETYPES[*]}
            ;;
        *)
            FATAL "unknown error while processing options"
            exit 1;
        ;;
    esac
done
shift "$((OPTIND-1))" # shift out all the already processed options

# --- start body ----------------------------------------------------
#############################
# error printing
#############################
function error() {
    local parent_lineno="${1:-}"
    local message="${2:-}"
    local code="${3:-1}"
    if [[ -n "$message" ]] ; then
        ERROR "Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
    else
        ERROR "Error on or near line ${parent_lineno}; exiting with status ${code}"
    fi
    exit "${code}"
}

#############################
# program finished
#############################
function finish {
    # @description finish the program by cleaning up it's resources
    # clean app directory, if fail don't care
    rm -r "${APP_DIR}" || true
}

#############################
# conversion command
#############################
get_conversion_command() {
    # @description returns a conversion command
    # based on the file type.
    # the reason for this setup is so that the optimal command(s)
    # per file type can be selected
    # @param $1 input file
    # @param $2 output file
    # @param $2 quality switch (integer)
    # @param $3 extra parameters for the conversion
    local file=${1:-}
    local output_file=${2:-}
    local quality=${3:-5}
    local parameters=${4:-}
    local file_type=""
    local conversion_command=()       # external accessible after call
    conversion_output_dir=""    # external accessible after call
    if [ -z "${file}" ]; then
        echo "${ERR_MISSING_PARAMETER}"
        return 1 # empty file!
    else
        file_type=${file##*.} # set file type
    fi
    #output_file=${file/$INPUT_DIR/$OUTPUT_DIR}  # change input for output dir
    printf -v file "%q" "$file" # filter out special characters
    printf -v output_file "%q" "$output_file" # filter out special characters
    case $file_type in
        ${SUPORTED_FILETYPES[$WAV_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=("${DEFAULT_CONV_COMM}" -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file}")
            ;;
        ${SUPORTED_FILETYPES[$FLAC_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=("${DEFAULT_CONV_COMM}" -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file}")
            ;;
        ${SUPORTED_FILETYPES[$ALAC_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=("${DEFAULT_CONV_COMM}" -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file}")
            ;;
        ${SUPORTED_FILETYPES[$MP3_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=("${DEFAULT_CONV_COMM}" -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file}")
            ;;
        ${SUPORTED_FILETYPES[$OGG_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=("${DEFAULT_CONV_COMM}" -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file}")
            ;;
        ${SUPORTED_FILETYPES[$M4A_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=("${DEFAULT_CONV_COMM}" -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file}")
            ;;
        *)
            conversion_command=$ERR_TYPE_NOT_SUPORTED
            ;;
    esac
    echo "${conversion_command[@]}"
    return 0
}

#############################
# file to convert
#############################
function get_file_to_convert() {
    # @description get a file from the queue
    # This is using a mutex so that the queue is only read by one process
    local filename=""
    local timeout=5 #seconds
    local retry_timeout=$(bc -l <<< "scale = 2; $timeout/10.0") || true
    local retry_count=0
    local current_timeout=0
    while true; do # wait to get mutex, with timeout
        if mutex_lock "${MUTEX_READ_FILES_TO_PROCESS}" ; then
            filename=$(queue_read "${FILES_TO_PROCESS_QUEUE}")
            if [ -z "${filename}" ]; then
                filename=${ERR_NO_MORE_FILES}
            fi
            mutex_free "${MUTEX_READ_FILES_TO_PROCESS}" # free the mutex
            break
        else
            current_timeout=$(bc -l <<< "scale = 2; $retry_timeout*$retry_count") || true
            if [[ ${current_timeout%%.*} -gt $timeout ]]; then
                echo ${ERR_MUTEX_TIMEOUT}
                return 0
            fi
            ((retry_count++)) || true
            sleep $retry_timeout || true
        fi
    done
    echo "${filename}" # return the filename
}

#############################
# converter process
#############################
function process_convert() {
    # @description convert files from the queue
    # - get a file from the queue
    # - get a command based on the file
    # - setup output directory
    # - run command
    # - check file
    # - repeat when queue is empty
    # * some other things to remember *
    # * on INT signal, finish the conversion
    # * check EVERYTHING, this script needs to run for HOURS!
    local PROCESS_PID=$BASHPID
    local PROCESS_PPID=$PPID
    local convert_command=""
    local file=""
    local output_file=""
    local file_directory=""
    local file_output_directory=""
    local err_ret_code=0
    local err_ret_message=""
    value_set "${PROCESS_PID}_TERMINATE" "false" # set default value
    function terminate_process() {
        local PROCESS_PID=${1:-}
        value_set "${PROCESS_PID}_TERMINATE" "true" # set terminate variable
    }
    trap "terminate_process ${PROCESS_PID}" TERM INT # on INT, let the task finish and then exit
    trap 'error ${LINENO}' ERR # on error, print error
    DEBUG "conversion process with PID: $PROCESS_PID started"
    GUI_TITLE "Converting files"
    while true; do
        # get file to convert
        file=$(get_file_to_convert) || true # this can fail, just accept it
        if [ -z "${file}" ]; then
            file=${ERR_NO_MORE_FILES}
        fi
        if [ "$file" == "$ERR_NO_MORE_FILES" ]; then
            INFO "no more files left to process"
            break # stop process
        elif [ "$file" == "$ERR_MUTEX_TIMEOUT" ]; then
            NOTICE "$PROCESS_PID| mutex timeout" # retry
        else
            output_file=${file/$INPUT_DIR/$OUTPUT_DIR}  # change input for output dir
            output_file="${output_file%.*}.ogg" # replace extension
            # get convert command
            convert_command=$(get_conversion_command "${file}" "${output_file}" "${QUALITY}" "${PARAMETERS}") || true
            if [ -z "${convert_command}" ]; then
                WARN "got no command to run"
            elif [ "${convert_command}" == "${ERR_MISSING_PARAMETER}" ]; then
                WARN "missing parameters"
            elif [ "${convert_command}" ==  "${ERR_TYPE_NOT_SUPORTED}" ]; then
                ERROR "type not supported"
            else
                file_output_directory=${file/$INPUT_DIR/$OUTPUT_DIR} # change input for output dir
                file_output_directory="${file_output_directory%/*}"  # directory part of file
                INFO "processing: $(basename "$file")"
                GUI_NOTIFY "${file}"
                GUI_PART_COUNT $(queue_size "${FILES_TO_PROCESS_QUEUE}")
                # make directory
                if [ ! -d "${file_output_directory}" ]; then
                    mkdir -p "${file_output_directory}" || true
                fi
                # check overwrite
                if [ "${OVERWRITE_EXISTING}" = true ] ; then
                    convert_command="echo \"y\" | ${convert_command}"
                else
                    convert_command="echo \"n\" | ${convert_command}"
                fi
                DEBUG "$PROCESS_PID| command: ${convert_command}"
                convert_command+=" -loglevel error" # add log flag to command
                # run command and catch error message
                err_ret_message=$(eval "${convert_command}" 2>&1 ) || err_ret_code=$?

                # check return code of process
                if [ ! "${err_ret_code}" = 0 ] ; then
                    # command returned error
                    if [[ "${err_ret_message}" =~ (^File .* already exists. Exiting.$) ]] || \
                       [[ "${err_ret_message}" =~ (^File .* already exists. Overwrite \? \[y\/N] Not overwriting - exiting$) ]]; then
                        DEBUG "file already exists, skipping ${file}"
                    else
                        ERROR "error while processing: ${file}"
                        INFO "error message: ${err_ret_message}"
                        INFO "return code of command was: $err_ret_code"
                        # remove failed file
                        INFO "removing file because conversion failed: ${output_file}"
                        rm "${output_file}" || true
                    fi
                    err_ret_message=""
                    err_ret_code=0
                fi
            fi
        fi
        TERMINATE=$(value_get ${PROCESS_PID}_TERMINATE) || true
        if [ "${TERMINATE}" = true ]; then
            break
        fi
    done
    DEBUG "process $PROCESS_PID stops now"
    return 0
}

#############################
# Graphical User Interface
#############################
function process_gui() {
    # @description this displays the UI in terminal or via an UI interface called 'dialog'
    local PROCESS_PID=$BASHPID
    local start_time=""
    local end_time=""
    local elapsed_time=""
    local old_elapsed_time=""
    local title=""
    local sub_title=""
    local totalcount=0
    local partcount=0
    local old_title=""
    local old_totalcount=0
    local old_partcount=0
    local notification=""
    local notifications=()
    local message="" # mess to display
    local old_message=""
    local percentage=0
    local gui_update="0.5" #sec
    local term_update="10" #sec
    local terminal_width=$(tput cols) || true
    terminal_width=$(((${terminal_width:-200} / 10)*8)) # about 80%
    export DIALOGRC="${SCRIPT_PATH_LOCAL}/.dialogrc" # export rc file
    start_time=$(date +%s)
    value_set "${PROCESS_PID}_TERMINATE" "false" # set default value
    function terminate_process() {
        DEBUG "set GUI term value"
        local PROCESS_PID=${1:-}
        value_set "${PROCESS_PID}_TERMINATE" "true" # set terminate variable
    }
    trap "terminate_process ${PROCESS_PID}" TERM INT # on TERM or INT, let the task finish and then exit
    trap 'error ${LINENO}' ERR # on error, print error
    DEBUG "start GUI"
    while true; do
        title=$(value_get "${GUI_TITLE}") || true
        totalcount=$(value_get "${GUI_TOTAL_COUNT}") || true
        partcount=$(value_get "${GUI_PART_COUNT}") || true
        notification=$(queue_read "${GUI_NOTIFICATIONS_QUEUE}") || true
        while [ ! -z "${notification}" ]; do
            notifications[0]="${notifications[1]:-}"
            notifications[1]="${notifications[2]:-}"
            notifications[2]="${notifications[3]:-}"
            notifications[3]="${notification}"
            notification=$(queue_read "${GUI_NOTIFICATIONS_QUEUE}")
        done
        printf -v elapsed_time "%02d:%02d:%02d" \
            $(($(( $(date +%s)-$start_time ))/3600)) \
            $(($(( $(date +%s)-$start_time ))%3600/60)) \
            $(($(( $(date +%s)-$start_time ))%60))
        if [ "${totalcount}" == 0 ]; then
            sub_title=""
            percentage=0
        elif [ -z "${partcount}" ] || [ -z "${totalcount}" ]; then
            sub_title=""
            percentage=0
        else
            sub_title="$partcount out of $totalcount left to process."
            percentage=$(((totalcount-partcount)*100/totalcount))
        fi
        if [ ! "${title}" = "${old_title}" ] || \
           [ ! "${message}" = "${old_message}" ] || \
           [ ! "${totalcount}" = "${old_totalcount}" ] || \
           [ ! "${partcount}" = "${old_partcount}" ] || \
           [ ! "${elapsed_time}" = "${old_elapsed_time}" ]; then
            # write to log every term_update sec
            if [ "$((($(date +%s)-$start_time)%$term_update))" = "0" ] || [ "${USE_GUI}" = false ]; then
                NOTICE "Elapsed time: $elapsed_time | ${percentage}% | ${title} | ${sub_title}"
            fi
            if [ "${USE_GUI}" = true ]; then
                message="\Z4${sub_title}\Zn\n"
                message+="\n"
                message+="${notifications[0]:-}\n"
                message+="${notifications[1]:-}\n"
                message+="${notifications[2]:-}\n"
                message+="${notifications[3]:-}\n"
                message+="\n"
                message+="\ZbElapsed time since start: $elapsed_time\Zn"
                echo $percentage  | dialog --colors --title "${title}" --gauge "${message}" 14 ${terminal_width:-100} 0
                sleep $gui_update || true
            else
                sleep $term_update || true
            fi
        fi
        TERMINATE=$(value_get ${PROCESS_PID}_TERMINATE) || true
        if [ "${TERMINATE}" = true ]; then
            end_time=$(date +%s)
            printf -v elapsed_time "%02d:%02d:%02d" \
                $(($(( $end_time-$start_time ))/3600)) \
                $(($(( $end_time-$start_time ))%3600/60)) \
                $(($(( $end_time-$start_time ))%60))
            start_time=$(date -d@$start_time '+%m/%d/%Y %H:%M:%S') || true
            end_time=$(date -d@$end_time '+%m/%d/%Y %H:%M:%S') || true
            message="\nStart time: $start_time\nEnd time:   $end_time\nTime taken: ${elapsed_time}"
            if [ "${USE_GUI}" = true ]; then
                echo 100  | dialog --title "${APPNAME} is now done" --gauge "${message}" 14 ${terminal_width:-100} 0
            fi
            NOTICE "${APPNAME} is now done"
            NOTICE "Start time: $start_time"
            NOTICE "End time:   $end_time"
            NOTICE "Time taken: ${elapsed_time}"
            break
        fi
        old_title="${title}"
        old_message="${message}"
        old_partcount="${partcount}"
        old_totalcount="${totalcount}"
        old_elapsed_time="${elapsed_time}"
    done
    DEBUG "GUI stops now"
    return 0
}

#############################
# copy over files
#############################
function copy_files_over() {
    # @description copy over files
    # @param $1 source
    # @param $2 dest
    # @param rest of the parameters filenames
    local source=${1:-"./"}
    local dest=${2:-"./"}
    shift 2
    local files=${@:-""}
    local filename=""
    local extension=""
    local err_ret_code=0
    local err_ret_message=""
    local readonly copy_queue="files_to_copy_over"
    GUI_TITLE "Copying files over"
    GUI_NOTIFY_CLEAR
    DEBUG "source: $source"
    DEBUG "dest: $dest"
    DEBUG "files: ${files[@]}"
    for file in ${files[@]}; do
        filename=$(basename "$file")
        extension="${filename##*.}"
        filename="${filename%.*}"
        INFO "searching for the files to copy over"
        GUI_NOTIFY "searching for file(s): ${file}"
        find_files "${source}" "${filename}" "${extension}" "${copy_queue}"
        GUI_TOTAL_COUNT $(queue_size ${copy_queue})
        GUI_PART_COUNT 0
        INFO "copying over files"
        # process queue
        file_to_process=$(queue_read ${copy_queue})
        while [ ! -z "${file_to_process}" ]; do
            DEBUG "copy file: ${file_to_process}"
            GUI_NOTIFY "${file_to_process}"
            GUI_PART_COUNT $(queue_size ${copy_queue})
            file_output_directory=${file_to_process/$source/$dest} # change input for output dir
            file_output_directory="${file_output_directory%/*}"  # directory part of file
            # make directory
            if [ ! -d "${file_output_directory}" ]; then
                mkdir -p "${file_output_directory}" || true
            fi
            output_file=${file_to_process/$source/$dest}
            INFO "copying file: '${file_to_process}'"
            DEBUG "to: '${output_file}'"
            err_ret_message=$(cp "${file_to_process}" "${output_file}" 2>&1 ) || err_ret_code=$?
            if [ ! "${err_ret_code}" = 0 ] ; then
                if [ ! -z "${err_ret_message}" ]; then
                    ERROR "copy command returned message: ${err_ret_message}"
                fi
                ERROR "error while processing: ${file_to_process}"
                DEBUG "return code of command is: ${err_ret_code}"
            fi
            file_to_process=$(queue_read ${copy_queue}) # read new file
        done
    done
}

#############################
# synchronize files
#############################
function fuzzy_counterpart_check() {
    # @description check if a 'counterpart' file exists in another directory
    # This will check if a folder has a counterpart file in another directory.
    # The 'counterpart' file is a file which has the same name and path as the file it checks to.
    # The fuzzy part is that the extension will not be checked.
    # @param $1 from; the base folder
    # @param $2 to; the folder to check
    # @param $3 include hidden files/folders [true/false]
    local base_directory=${1:-}
    local check_directory=${2:-}
    local hidden=${3:-}
    local base_file=""
    local check_file=""
    local err_ret_code=0
    local found_files=0
    local find_param=""
    local queue_check_file="fuzzy_counterpart_check"
    # check directories
    if [ -z "${base_directory}" ]; then
        ERROR "the from/base directory parameter for the fuzzy counterpart check was not set"
        return 1
    fi
    if [ -z "${check_directory}" ]; then
        ERROR "the to/check directory parameter for the fuzzy counterpart check was not set"
        return 1
    fi
    if [ ! -r "${base_directory}" ]; then # check base directory for read access
        ERROR "the from/base directory for the fuzzy counterpart check cannot be read"
        return 1
    fi
    if [ ! -w "${check_directory}" ]; then # check check directory for write access
        ERROR "the to/check directory for the fuzzy counterpart check is not writable"
        return 1
    fi
    # set hidden
    if [ ! "${hidden}" = true ] ; then
        find_param="*/\.*" # exclude hidden files/folders
    fi
    GUI_TITLE "Synchronize files"
    GUI_TOTAL_COUNT 0
    GUI_PART_COUNT 0
    GUI_NOTIFY "looking for all the files in the output folder, this may take a while"
    # find files of all types
    find_files "${check_directory}" "*" "*" "${queue_check_file}" "${find_param}"
    GUI_TOTAL_COUNT $(queue_size ${queue_check_file})
    check_file=$(queue_read "${queue_check_file}")
    while [ ! -z "${check_file}" ]; do
        DEBUG "counterpart check: $check_file"
        GUI_NOTIFY "${check_file}"
        GUI_PART_COUNT $(queue_size "${queue_check_file}")
        # - replace check dir with base dir
        base_file="${check_file/$check_directory/$base_directory}"
        base_file="${base_file%.*}" # remove extension
        DEBUG "counterpart check to: ${base_file}"
        # - check if exists based on filename, ignoring all extension (fuzzy part)
        found_files=$(ls "${base_file}".* 2> /dev/null | wc -l) || true
        DEBUG "found counterpart files: ${found_files}"

        if [ "${found_files}" -eq 0 ] ; then
            DEBUG "file ${check_file} has no counterpart"
            INFO "removing ${check_file}"
            rm "${check_file}" || true # remove check file
        else
            DEBUG "file ${check_file} has counterpart"
        fi
        found_files=0
        check_file=$(queue_read "${queue_check_file}")
    done
    # remove empty directories
    DEBUG "removing empty directories"
    GUI_NOTIFY "removing empty directories"
    find "${check_directory}" -type d -empty -delete
}

function ctrl_c() {
    # @description do things when the SIGINT is trapped
    DEBUG "** Trapped CTRL-C"
    INFO "requested termination"
    processes_signal ${CONVERTER_PROCESSES_QUEUE} 'SIGINT'
    kill -SIGTERM "${GUI_PID}"      # stop GUI
    wait || true                # wait for all child processes to finish
    exit 1
}
trap 'ctrl_c' INT

# --- main ----------------------------------------------------------
GUI_PID=0

# logger setup
B_LOG --stdout true
B_LOG --file "${LOG_FILE}" --file-prefix-enable --file-suffix-enable # log in a file
B_LOG --syslog "${SYSLOG_PARAM}" # log to syslog
B_LOG --log-level ${VERBOSITY} # set log level

# check folders
if [ ! -r "${INPUT_DIR}" ]; then    # check input directory for read access
    FATAL "the input directory cannot be read"
    exit 1
fi
if [ ! -w "${OUTPUT_DIR}" ]; then   # check output directory for write access
    FATAL "the output directory is not writable"
    exit 1
fi

# set traps
trap 'error ${LINENO}' ERR  # on error, print error
trap finish EXIT            # on exit, clean up resources

# set stdio output for GUI
if [ "${USE_GUI}" = true ]; then
    B_LOG --stdout false
else
    B_LOG --stdout true
fi

# set default GUI values
GUI_TITLE "${APPNAME} v${VERSION}"
GUI_NOTIFY_CLEAR

process_gui& # start the GUI
GUI_PID=$!

# looking for files
NOTICE "finding files and start conversion"
INFO "looking for files with the filetypes: ${FILETYPES[*]:-}"
GUI_TITLE "looking for files to convert"
GUI_NOTIFY_CLEAR
GUI_NOTIFY "this may take a while"
find_files "${INPUT_DIR}" "*" "${FILETYPES[*]:-}" "${FILES_TO_PROCESS_QUEUE}"   # find the files needed for processing
GUI_TOTAL_COUNT "$(queue_size "${FILES_TO_PROCESS_QUEUE}")"
GUI_PART_COUNT 0
# converting the files
INFO "starting the conversion process(es)"
GUI_TITLE "starting the conversion process(es)"
GUI_NOTIFY_CLEAR
processes_start 'process_convert' "${JOBS}" "${CONVERTER_PROCESSES_QUEUE}"          # start the conversion processes
wait $(queue_look_sl "${CONVERTER_PROCESSES_QUEUE}") || true                # wait for converter processes

# copying over files
NOTICE "copying over files"
INFO "copying over the following files: ${COPY_FILES[@]:-}"
copy_files_over "${INPUT_DIR}" "${OUTPUT_DIR}" "${COPY_FILES[@]:-}"
NOTICE "done copying"

# syncing/counterpart checking files
if [ "${COUNTERPART_SYNC}" = true ] ; then
    NOTICE "checking for counterpart files"
    if [ "${COUNTERPART_HIDDEN}" = true ] ; then
        fuzzy_counterpart_check "${INPUT_DIR}" "${OUTPUT_DIR}" true
    else
        fuzzy_counterpart_check "${INPUT_DIR}" "${OUTPUT_DIR}" false
    fi
fi

# stop the program
NOTICE "${APPNAME} is now done"
kill -SIGTERM "${GUI_PID}"      # stop GUI
wait || true
# --- done ----------------------------------------------------------
