#!/bin/bash
#########################################################################
# Script Name: yad2ogg
# Script Version: 0.0.1
# Script Date: 23 June 2016
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
# global parameters
set -e          # kill script if a command fails
set -o nounset  # unset values give error
set -o pipefail # prevents errors in a pipeline from being masked

SCRIPT_PATH=${0%/*}
source ${SCRIPT_PATH}/b-log/b-log.sh # include the log script

VERSION=0.0.1
APPNAME="yad2ogg"

function PRINT_USAGE() {
    # @description prints the short usage of the script
    echo "Usage: yad2ogg.sh [options]"
    echo "    -h --help             Show usage"
    echo "    -V --version          Version"
    echo "    -v --verbose          Add more verbosity"
    echo "    -l --logfile 'file'   Log to a file"
    echo "    -s --syslog 'param'   Log to syslog \"logger 'param' log-message\""
    echo "    -i --input 'dir'      Input/source directory"
    echo "    -o --output 'dir'     Destination/output directory"
    echo "    -q --quality 5.0      Quality switch where N is a number"
    echo "    -p --parameters ''    Extra conversion parameters"
    echo "    -j --jobs 1           Number of concurrent jobs"
    echo "    -c --copyfile '*.jpg' Copy files over from original directory to "
    echo "                          destination directory eg. '*.cue or *.jpg'."
    echo "    -m --metadata         Don't keep metadata(tags) from the original files"
    echo "    -w --overwrite        Overwrite existing files"
    echo ""
    echo "                          =FILE TYPES="
    echo "                          types of input files to process"
    echo "    -f --filetypes        File type eg. 'wav flac ...'"
    echo "    -f 'wav'  --WAV"
    echo "    -f 'flac' --FLAC"
    echo "    -f 'alac' --ALAC"
    echo "    -f 'mp3'  --MP3"
    echo "    -f 'ogg'  --OGG"
    echo "    -f 'm4a'  --M4A"
    echo "    -a --ALL              All supported file types"
    echo ""
}

# --- global variables ----------------------------------------------
INPUT_DIR='./'              # input directory
OUTPUT_DIR='./'             # output directory
QUALITY="5"                 # the quality for the converter switch
# "Most users agree -q 5 achieves transparency, if the source is the original or lossless."
# taken from: http://wiki.hydrogenaud.io/index.php?title=Recommended_Ogg_Vorbis
PARAMETERS=""               # optional parameters for the converter
JOBS=1                      # number of concurrent jobs (default 1)
VERBOSITY=$LOG_LEVEL_NOTICE # set starting log level
LOG_FILE=""                 # file to log to (default empty, so disabled)
SYSLOG_PARAM=""             # syslog parameters (default empty, so disabled)
COPY_FILES=()               # files to copy over from the source directory
KEEP_METADATA=true          # keep metadata(tags)
OVERWRITE_EXISTING=false    # overwrite existing files
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
readonly FILES_TO_PROCESS_QUEUE="files_to_process"
readonly FILES_TO_COPY_OVER_QUEUE="files_to_copy_over"
readonly CONVERTER_PROCESSES_QUEUE="converter_processes"
# mutex names
readonly MUTEX_READ_FILES_TO_PROCESS="get_convert_file"

# some error codes to use in the file
readonly ERR_NO_MORE_FILES="no more files"
readonly ERR_MISSING_PARAMETER="missing parameter"
readonly ERR_MUTEX_TIMEOUT="mutex timeout"
readonly ERR_TYPE_NOT_SUPORTED="type not supported"

# --- options processing --------------------------------------------
if [ $# -eq 0 ] ; then  # nothing past to the script
    PRINT_USAGE
    exit 1;
fi
for arg in "$@"; do     # transform long options to short ones
    shift
    case "$arg" in
        "--help") set -- "$@" "-h" ;;
        "--version") set -- "$@" "-V" ;;
        "--verbose") set -- "$@" "-v" ;;
        "--logfile") set -- "$@" "-l" ;;
        "--syslog") set -- "$@" "-s" ;;
        "--input") set -- "$@" "-i" ;;
        "--output") set -- "$@" "-o" ;;
        "--quality") set -- "$@" "-q" ;;
        "--jobs") set -- "$@" "-j" ;;
        "--copyfile") set -- "$@" "-c" ;;
        "--metadata") set -- "$@" "-m" ;;
        "--overwrite") set -- "$@" "-w" ;;
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
while getopts "hVvl:s:i:o:q:p:j:c:mwf:a" optname
do
    case "$optname" in
        "h")
            PRINT_USAGE
            exit 0;
            ;;
        "V")
            echo "${APPNAME} v${VERSION}"
            exit 0;
            ;;
        "v")
            VERBOSITY=$(($VERBOSITY+100)) # increment log level
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
# queue interface
#############################
# use and manage a simple fifo queue
# in a local file system
# - init 'queue name' 'clear existing'
# - add 'queue name' 'data'
# - read 'queue name' [returns via echo]
function queue_init() {
    # @description init the fifo queue, can be called throughout the script
    # @param $1 the queue name
    # @param $2 clear the queue [default false]
    # make file in QUEUE_STORAGE with name of 'queue_name'
    local readonly queue_name_prefix="queue_"
    local queue_name=${1:-}
    local clear_queue=false
    if [ -z "$queue_name" ]; then
        FATAL "missing queue name"
        exit 1
    fi
    if [ -z "${2:-}" ]; then
        clear_queue=false
    elif [ "$2" == "true" ]; then
        clear_queue=true
    fi
    local readonly queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    # check folder location
    if [ ! -d "$QUEUE_STORAGE" ]; then
        mkdir -p "$QUEUE_STORAGE"
        if [ $? -ne 0 ] ; then
            FATAL "could not make the queue file"
            exit 1
        fi
    fi
    # check file, if not exist make one
    if [ ! -e "$queue_file" ] ; then
        touch "$queue_file"
    fi
    if [ ! -w "$queue_file" ] ; then
        FATAL "cannot write to $queue_file"
        exit 1
    fi
    if $clear_queue; then # clearing the queue file
        echo -n "" > $queue_file
    fi
}
function queue_add() {
    # @description add values to the queue
    # @param $1 the queue name
    # @param $2 the queue data
    local readonly queue_name_prefix="queue_"
    local queue_name=${1:-}
    shift
    local queue_data=${@:-}
    if [ -z "$queue_name" ]; then
        FATAL "missing queue name"
        exit 1
    fi
    local queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    queue_init $queue_name # make sure that the queue exists
    DEBUG "queue data: '${queue_data}'"
    DEBUG "queue name: $queue_file"
    echo "${queue_data}" >> $queue_file # append data to file
}
function queue_read() {
    # @description read value from the queue on a fifo basis
    # @param $1 the queue name
    # @return returns the 'queue_data'
    local readonly queue_name_prefix="queue_"
    local queue_name=${1:-}
    local queue_data=""
    if [ -z "$queue_name" ]; then
        FATAL "missing queue name"
        exit 1
    fi
    local queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    queue_init "${queue_name}" # make sure that the queue exists
    queue_data=$(head -n 1 "${queue_file}") || true # get first line of file
    sed -i 1d $queue_file || true # remove first line of file
    echo "${queue_data}"
}

#############################
# mutex interface
#############################
# use and manage a simple mutex implementation
# via a local file system
# - lock 'mutex name' [returns 1(succeeded) or 0(failed)]
# - free 'mutex name'
function mutex_lock() {
    # @description locks a mutex
    # if no mutex exists, one will be made
    # @param $1 the mutex name
    # @return returns status: true/1(succeeded) or false/0(failed)
    local mutex_name=${1:-}
    local readonly mutex_name_prefix="mutex_"
    local readonly LOCK_FD=200
    if [ -z "$mutex_name" ]; then
        return 0 # missing mutex name
    fi
    #local prefix=`basename $0`
    #prefix+="_$mutex_name"
    local fd=${2:-$LOCK_FD}
    local mutex_file="${LOCKFILE_DIR}/${mutex_name_prefix}${mutex_name}"
    # create lock file
    mkdir -p "$(dirname "${mutex_file}")" || return 0
    touch "${mutex_file}"
    eval "exec $fd>$mutex_file"

    # acquier the lock
    flock -n $fd \
        && return 0 \
        || return 1
}
function mutex_free() {
    # @description frees a mutex
    # use this when you have the mutex
    # of the to be freed mutex
    # @param $1 the mutex name
    local mutex_name=${1:-}
    local readonly mutex_name_prefix="mutex_"
    if [ -z "$mutex_name" ]; then
        return 0 # missing mutex name
    fi
    local mutex_file="${LOCKFILE_DIR}/${mutex_name_prefix}${mutex_name}"
    if [ -e "$mutex_file" ]; then
        rm $mutex_file
    fi
}

#############################
# start concurrent processes
#############################
function processes_start() {
    # @description start a multiple of concurrent processes and store their PIDs
    # @param $1 function to start
    # @param $2 number of times to start this process
    # @param $3 identifier of these processes (used to make a queue for the PIDs)
    local function="${1:-}"
    local jobs=${2:-"1"}
    local identifier=${3:-"${function}"}
    local queue_name="processes_pid_${identifier:-"default"}"
    local pid=""
    DEBUG "function: ${function}"
    DEBUG "jobs: ${jobs}"
    DEBUG "id: ${identifier}"
    DEBUG "queue name: ${queue_name}"
    queue_init "${queue_name}" true
    if [ ! -z "${function}" ]; then
        for (( i = 0; i < ${jobs}; i++ )); do
            $function& # start new process
            pid=$!
            queue_add ${queue_name} ${pid} # add pid to queue
        done
    fi
}
function processes_signal() {
    # @description send a kill signal to a multiple of concurrent processes
    # uses a queue file with all the PIDs in a queue
    # @param $1 identifier of these processes (used to make a queue for the PIDs)
    # @param $2 signal (a signal used by the `kill` command) eg. SIGKILL, SIGTERM
    local identifier=${1:-}
    local signal=${2:-"SIGINT"}
    local queue_name="processes_pid_${identifier:-"default"}"
    #pid=""
    pid=$(queue_read ${queue_name})
    while [ ! -z "${pid}" ]; do
        # check if pid exists
        if [ -n "$(ps -p $pid -o pid=)" ]; then
           kill -${signal} $pid
           DEBUG "signaled process with PID: ${pid}"
        fi
        pid=$(queue_read ${queue_name})
    done
}

#############################
# global value storage
#############################
function value_set() {
    # @description store the value of a variable on the local file system
    # @param $1 variable name
    # @param $2 variable value
    local var_name=${1:-}
    local var_value=${2:-}
    local readonly var_name_prefix="variable_"
    if [ -z "${var_name}" ]; then
        ERROR "missing variable name"
        return 1
    fi
    if [ -z "${var_value}" ]; then
        ERROR "missing variable value"
        return 1
    fi
    local var_file="${VARIABLE_STORAGE}/${var_name_prefix}${var_name}"
    # make directory
    if [ ! -d "${VARIABLE_STORAGE}" ]; then
        mkdir -p "${VARIABLE_STORAGE}"
        if [ $? -ne 0 ] ; then
            FATAL "could not make the variable value file"
            exit 1
        fi
    fi
    # make file
    if [ ! -e "$var_file" ] ; then
        touch "$var_file"
    fi
    if [ ! -w "$var_file" ] ; then
        FATAL "cannot write to $var_file"
        exit 1
    fi
    echo "${var_value}" > "${var_file}" # write value in file
}
function value_get() {
    # @description get the value of a variable on the local file system
    # @param $1 variable name
    # @return returns the requested variable value via a echo
    local var_name=${1:-}
    local var_value=""
    local readonly var_name_prefix="variable_"
    if [ -z "${var_name}" ]; then
        ERROR "missing variable name"
        return 1
    fi
    local var_file="${VARIABLE_STORAGE}/${var_name_prefix}${var_name}"
    if [ -e "${var_file}" ]; then
        var_value=$(<${var_file})
    fi
    echo "${var_value}"
}

#############################
# Find files
#############################
function find_files() {
    # @description find all files and add them to a queue
    # - find all the files matching the parameters
    # - add them to a queue that will be cleared first
    # @param $1 path to directory
    # @param $2 filename(wildcards accepted)
    # @param $3 filetypes(extensions)
    # @param $4 queue name
    local path=${1:-"./"}
    local filename=${2:-}
    local filetypes=${3:-}
    local queue_name=${4:-}
    DEBUG "path: $path"
    DEBUG "filename: $filename"
    DEBUG "filetypes: $filetypes"
    DEBUG "queue name: $queue_name"
    queue_init ${queue_name} true
    for filetype in ${filetypes}; do
        find "${path}" -type f -name "${filename}.${filetype}" -print0 | while IFS= read -r -d '' file; do
             queue_add "${queue_name}" "$file"
             DEBUG "file $file"
        done
    done
}

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
    # ^-- not needed, because using the /tmp directory
    :
}

#############################
# conversion command
#############################
get_conversion_command() {
    # @description returns a conversion command
    # based on the file type.
    # the reason for this setup is so that the optimal command(s)
    # per file type can be selected
    # @param $1 filename of the to converted file
    # @param $2 quality switch (integer)
    # @param $3 extra parameters for the conversion
    local file=${1:-}
    local quality=${2:-5}
    local parameters=${3:-}
    local file_type=""
    local output_file=""
    local conversion_command=()       # external accessible after call
    conversion_output_dir=""    # external accessible after call
    if [ -z "${file}" ]; then
        ERROR "${ERR_MISSING_PARAMETER}"
        return 1 # empty file!
    else
        file_type=${file##*.} # set file type
    fi
    output_file=${file/$INPUT_DIR/$OUTPUT_DIR}  # change input for output dir
    printf -v file "%q" "$file" # filter out special characters
    printf -v output_file "%q" "$output_file" # filter out special characters
    case $file_type in
        ${SUPORTED_FILETYPES[$WAV_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=(ffmpeg -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file%.*}.ogg")
            ;;
        ${SUPORTED_FILETYPES[$FLAC_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=(ffmpeg -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file%.*}.ogg")
            ;;
        ${SUPORTED_FILETYPES[$ALAC_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=(ffmpeg -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file%.*}.ogg")
            ;;
        ${SUPORTED_FILETYPES[$MP3_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=(ffmpeg -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file%.*}.ogg")

            ;;
        ${SUPORTED_FILETYPES[$OGG_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=(ffmpeg -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file%.*}.ogg")
            ;;
        ${SUPORTED_FILETYPES[$M4A_LIST]} )
            if [ "${KEEP_METADATA}" = true ] ; then
                parameters+=' -map_metadata 0'
            else
                parameters+=' -map_metadata -1'
            fi
            conversion_command=(ffmpeg -i "${file}" -acodec libvorbis -aq "${quality}" "${parameters}" "${output_file%.*}.ogg")
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
    local file_directory=""
    local file_output_directory=""
    local err_ret_code=0
    local err_ret_message=""
    value_set "${PROCESS_PID}_TERMINATE" "false" # set default value
    function terminate_process() {
        local PROCESS_PID=${1:-}
        value_set "${PROCESS_PID}_TERMINATE" "true" # set terminate variable
    }
    trap "terminate_process ${PROCESS_PID}" INT # on INT, let the task finish and then exit
    trap 'error ${LINENO}' ERR # on error, print error
    DEBUG "conversion process with PID: $PROCESS_PID started"
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
            # get convert command
            convert_command=$(get_conversion_command "${file}" "${QUALITY}" "${PARAMETERS}") || true
            if [ -z "${convert_command}" ]; then
                WARN "got no command to run"
            elif [ "${convert_command}" == "${ERR_MISSING_PARAMETER}" ]; then
                WARN "missing parameters"
            else
                file_output_directory=${file/$INPUT_DIR/$OUTPUT_DIR} # change input for output dir
                file_output_directory="${file_output_directory%/*}"  # directory part of file
                INFO "processing: $(basename "$file")"

                # make directory
                if [ ! -d "${file_output_directory}" ]; then
                    mkdir -p "${file_output_directory}" || true
                fi
                # check overwrite
                if [ "${OVERWRITE_EXISTING}" = true ] ; then
                    convert_command+=" -y"
                else
                    convert_command+=" -n"
                fi
                DEBUG "$PROCESS_PID| command: ${convert_command}"
                convert_command+=" -loglevel error" # add log flag to command
                # run command and catch error message
                err_ret_message=$(eval "${convert_command}" 2>&1 ) || err_ret_code=$?

                # check return code of process
                if [ ! "${err_ret_code}" = 0 ] ; then
                    if [[ "${err_ret_message}" =~ (^File .* already exists. Exiting.$) ]]; then
                        #ERROR "MATCH"
                        DEBUG "${err_ret_message}"
                        err_ret_message=""
                    fi
                    if [ ! -z "${err_ret_message}" ]; then
                        # check return message type
                        # already exists, ignore
                        #if [[ "${err_ret_message}" =~ ^File .* already exists. Exiting.$ ]]; then
                        regex="^File .* already exists. Exiting.$"
                        #if [[ "${err_ret_message}" =~ $regex ]]; then
                        #    ERROR "MATCH"
                        #fi
                        NOTICE "$PROCESS_PID| convert command returned message: ${err_ret_message}"
                    fi
                    if [ "${OVERWRITE_EXISTING}" = true ] ; then
                        # error from command, even if overwrite is enabled
                        ERROR "$PROCESS_PID| error while processing: $file"
                        DEBUG "$PROCESS_PID| return code of process command is: $err_ret_code"
                    fi
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
    DEBUG "source: $source"
    DEBUG "dest: $dest"
    DEBUG "files: ${files[@]}"
    for file in ${files[@]}; do
        filename=$(basename "$file")
        extension="${filename##*.}"
        filename="${filename%.*}"
        INFO "searching for the files to copy over"
        find_files "${source}" "${filename}" "${extension}" "${copy_queue}"
        INFO "copying over files"
        # process queue
        file_to_process=$(queue_read ${copy_queue})
        while [ ! -z "${file_to_process}" ]; do
            DEBUG "copy file: ${file_to_process}"
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

function ctrl_c() {
    # @description do things when the SIGINT is trapped
    DEBUG "** Trapped CTRL-C"
    INFO "requested termination"
    processes_signal ${CONVERTER_PROCESSES_QUEUE} 'SIGINT'
    wait || true                # wait for all child processes to finish
    exit 1
}
trap 'ctrl_c' INT

# --- main ----------------------------------------------------------

#############################
# logger setup
#############################
B_LOG --stdout true   # log over STDIO
B_LOG --file "${LOG_FILE}" --file-prefix-enable --file-suffix-enable # log in a file
B_LOG --syslog "${SYSLOG_PARAM}" # log to syslog
B_LOG --log-level ${VERBOSITY} # set log level

if [ ! -r "${INPUT_DIR}" ]; then    # check input directory for read access
    FATAL "the input directory cannot be read"
    exit 1
fi
if [ ! -w "${OUTPUT_DIR}" ]; then   # check output directory for write access
    FATAL "the output directory is not writable"
    exit 1
fi

trap 'error ${LINENO}' ERR  # on error, print error
trap finish EXIT            # on exit, clean up resources

NOTICE "${APPNAME} v${VERSION}"
NOTICE "finding files and start conversion"
INFO "looking for files with the filetypes: ${FILETYPES[*]-""}"
find_files "${INPUT_DIR}" "*" "${FILETYPES[*]:-}" "${FILES_TO_PROCESS_QUEUE}"   # find the files needed for processing

INFO "starting the conversion process(es)"
processes_start 'process_convert' "${JOBS}" "${CONVERTER_PROCESSES_QUEUE}"      # start the conversion processes

wait || true                # wait for all child processes to finish
NOTICE "done converting, copying over files"
INFO "copying over the following files: ${COPY_FILES[@]:-}"
copy_files_over "${INPUT_DIR}" "${OUTPUT_DIR}" "${COPY_FILES[@]:-}"

NOTICE "${APPNAME} is now done"

# --- done ----------------------------------------------------------
