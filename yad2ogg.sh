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
#########################################################################
# Explanation
# yad2ogg -i input_folder -o destination --copyfile "cover.jpg"
#########################################################################
# global parameters
set -e          # kill script if a command fails
set -o nounset  # unset values give error
set -o pipefail # prevents errors in a pipeline from being masked

VERSION=0.0.1
APPNAME="yad2ogg"
USAGE="
Usage: command -hVio
-h --help help
-V --version version
-i --input input directory
-o --output destination/output directory
-q --quality quality switch
-p --parameters extra conversion parameters
-j --jobs number of concurrent jobs
-c --copyfile 'xx' copy files over from original directory to destination where tracks were converted eg. '*.cue or *.jpg'.
-m --metadata keep the metadata(tags) from the original files
-w --overwrite overwrite existing files

=FILE TYPES=
types of input files to process
-f --filetypes file type eg. 'flac or ogg'
-a all supported file types
Or use these parameters(recommended):
--WAV
--FLAC
--ALAC
--MP3
--OGG
--M4A
--ALL
"

function PRINT_USAGE() {
    # @description prints the short usage of the script
	echo "$USAGE"
}

# --- global variables ----------------------------------------------
INPUT_DIR='./'      # input directory
OUTPUT_DIR='./'     # output directory
QUALITY="5"         # the quality for the converter switch
# "Most users agree -q 5 achieves transparency, if the source is the original or lossless."
# taken from: http://wiki.hydrogenaud.io/index.php?title=Recommended_Ogg_Vorbis
PARAMETERS=""       # optional parameters for the converter
JOBS=1              # number of concurrent jobs (default 1)
COPY_FILES=()       # files to copy over from the source directory
KEEP_METADATA=false # keep metadata(tags)
OVERWRITE_EXISTING=false # overwrite existing files
FILETYPES=()        # file types to convert
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
while getopts "hVi:o:q:j:c:mwf:a" optname
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
        "i")
            INPUT_DIR=$OPTARG
            ;;
        "o")
            OUTPUT_DIR=$OPTARG
            ;;
        "q")
            QUALITY=${OPTARG}
            ;;
        "p")
            echo "option extra parameters: $OPTARG"
            ;;
        "j")
            JOBS=$OPTARG
            echo "option jobs: $JOBS"
            ;;
        "c")
            echo "option copyfile: $OPTARG"
            ;;
        "m")
            echo "option keep metadata"
            ;;
        "w")
            echo "option overwrite existing files"
            ;;
        "f")
            echo "option filetype: '$OPTARG'"
            FILETYPES[${#FILETYPES[@]}]=$OPTARG
            ;;
        "a")
            echo "option filetype: (all)"
            FILETYPES=${SUPORTED_FILETYPES[*]}
            echo ${FILETYPES[*]}
            ;;
        *)
            echo "unknown error while processing options"
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
        echo "missing queue name"
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
            echo "could not make the queue file"
            exit 1
        fi
    fi
    # check file, if not exist make one
    if [ ! -e "$queue_file" ] ; then
        touch "$queue_file"
    fi
    if [ ! -w "$queue_file" ] ; then
        echo "cannot write to $queue_file"
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
    local queue_data=${2:-}
    if [ -z "$queue_name" ]; then
        echo "missing queue name"
        exit 1
    fi
    local queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    queue_init $queue_name # make sure that the queue exists
    #echo "queue data: '$queue_data'"
    #echo "queue name: $queue_file"
    echo $queue_data >> $queue_file # append data to file
}
function queue_read() {
    # @description read value from the queue on a fifo basis
    # @param $1 the queue name
    # @return returns the 'queue_data'
    local readonly queue_name_prefix="queue_"
    local queue_name=${1:-}
    local queue_data=""
    if [ -z "$queue_name" ]; then
        echo "missing queue name"
        exit 1
    fi
    local queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    queue_init "${queue_name}" # make sure that the queue exists
    queue_data=$(head -n 1 "${queue_file}") || true # get first line of file
    sed -i 1d $queue_file || true # remove first line of file
    echo $queue_data
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
    #echo "function: ${function}"
    #echo "jobs: ${jobs}"
    #echo "id: ${identifier}"
    #echo "queue name: ${queue_name}"
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
    #echo "pid: ${pid}"
    while [ ! -z "${pid}" ]; do
        # check if pid exists
        if [ -n "$(ps -p $pid -o pid=)" ]; then
           kill -${signal} $pid
           echo "signaled process with PID: ${pid}"
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
        echo "missing variable name"
        return 1
    fi
    if [ -z "${var_value}" ]; then
        echo "missing variable value"
        return 1
    fi
    local var_file="${VARIABLE_STORAGE}/${var_name_prefix}${var_name}"
    # make directory
    if [ ! -d "${VARIABLE_STORAGE}" ]; then
        mkdir -p "${VARIABLE_STORAGE}"
        if [ $? -ne 0 ] ; then
            echo "could not make the variable value file"
            exit 1
        fi
    fi
    # make file
    if [ ! -e "$var_file" ] ; then
        touch "$var_file"
    fi
    if [ ! -w "$var_file" ] ; then
        echo "cannot write to $var_file"
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
        echo "missing variable name"
        return 1
    fi
    local var_file="${VARIABLE_STORAGE}/${var_name_prefix}${var_name}"
    if [ -e "${var_file}" ]; then
        var_value=$(<${var_file})
    fi
    echo ${var_value}
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
    # @param $2 filetypes(extensions)
    # @param $3 queue name
    local path=${1:-"./"}
    local filename=${2:-}
    local filetypes=${3:-}
    local queue_name=${4:-}
    #echo "path: $path"
    #echo "filename: $filename"
    #echo "filetypes: $filetypes"
    #echo "queue name: $queue_name"
    queue_init ${queue_name} true
    for filetype in ${filetypes}; do
        find "${path}" -name "${filename}.${filetype}" -print0 | while IFS= read -r -d '' file; do
             queue_add "${queue_name}" "$file"
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
        echo "$(tput setaf 1)Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}$(tput setaf 9)"
    else
        echo "$(tput setaf 1)Error on or near line ${parent_lineno}; exiting with status ${code}$(tput setaf 9)"
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
    # @param $2 extra parameters for the conversion
    local file=${1:-}
    local quality=${2:-"5"}
    local parameters=${3:-}
    local file_type=""
    local output_file=""
    local conversion_command=""       # external accessible after call
    conversion_output_dir=""    # external accessible after call
    if [ -z "${file}" ]; then
        echo "${ERR_MISSING_PARAMETER}"
        return 1 # empty file!
    else
        file_type=${file##*.} # set file type
    fi
    output_file=${file/$INPUT_DIR/$OUTPUT_DIR}  # change input for output dir
    case $file_type in
        ${SUPORTED_FILETYPES[$WAV_LIST]} )
            conversion_command="ffmpeg -i \"${file}\" -acodec libvorbis -aq ${quality} \"${output_file%.*}.ogg\""
            ;;
        ${SUPORTED_FILETYPES[$FLAC_LIST]} )
            conversion_command="ffmpeg -i \"${file}\" -acodec libvorbis -aq ${quality} \"${output_file%.*}.ogg\""
            ;;
        ${SUPORTED_FILETYPES[$ALAC_LIST]} )
            conversion_command="ffmpeg -i \"${file}\" -acodec libvorbis -aq ${quality} \"${output_file%.*}.ogg\""
            ;;
        ${SUPORTED_FILETYPES[$MP3_LIST]} )
            conversion_command="ffmpeg -i \"${file}\" -acodec libvorbis -aq ${quality} \"${output_file%.*}.ogg\""
            ;;
        ${SUPORTED_FILETYPES[$OGG_LIST]} )
            conversion_command="ffmpeg -i \"${file}\" -acodec libvorbis -aq ${quality} \"${output_file%.*}.ogg\""
            ;;
        ${SUPORTED_FILETYPES[$M4A_LIST]} )
            conversion_command="ffmpeg -i \"${file}\" -acodec libvorbis -aq ${quality} \"${output_file%.*}.ogg\""
            ;;
        *)
            conversion_command=$ERR_TYPE_NOT_SUPORTED
            ;;
    esac
    echo ${conversion_command}
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
    value_set "${PROCESS_PID}_TERMINATE" "false" # set default value
    function terminate_process() {
        local PROCESS_PID=${1:-}
        value_set "${PROCESS_PID}_TERMINATE" "true" # set terminate variable
    }
    trap "terminate_process ${PROCESS_PID}" INT # on INT, let the task finish and then exit
    trap 'error ${LINENO}' ERR # on error, print error
    echo "conversion process with PID: $PROCESS_PID started"
    while true; do
        # get file to convert
        file=$(get_file_to_convert) || true # this can fail, just accept it
        if [ -z "${file}" ]; then
            file=${ERR_NO_MORE_FILES}
        fi
        if [ "$file" == "$ERR_NO_MORE_FILES" ]; then
            echo "$PROCESS_PID: no more files left for me"
            break # stop process
        elif [ "$file" == "$ERR_MUTEX_TIMEOUT" ]; then
            echo "$PROCESS_PID: mutex timeout" # retry
        else
            # get convert command
            convert_command=$(get_conversion_command "${file}" "${QUALITY}") || true
            if [ -z "${convert_command}" ]; then
                echo "Got no command to run"
            elif [ "${convert_command}" == "${ERR_MISSING_PARAMETER}" ]; then
                echo "Missing parameters"
            else
                file_output_directory=${file/$INPUT_DIR/$OUTPUT_DIR} # change input for output dir
                file_output_directory="${file_output_directory%/*}"  # directory part of file
                #echo "$PROCESS_PID: ${convert_command}"
                #echo "$PROCESS_PID: ${file_output_directory}"
                echo "$PROCESS_PID| converting: $(basename "$file")"
                # make directory
                if [ ! -d "${file_output_directory}" ]; then
                    mkdir -p "${file_output_directory}" || true
                fi
                # run command
                eval "${convert_command}" "-nostats" "-loglevel 0" "-y" || true
            fi
        fi
        #sleep 2 || true # for debug is this delay handy
        TERMINATE=$(value_get ${PROCESS_PID}_TERMINATE) || true
        if [ "${TERMINATE}" = true ]; then
            break
        fi
    done
    echo "$(tput setaf 2)process $PROCESS_PID stops now$(tput setaf 9)"
    return 0
}

function ctrl_c() {
    # @description do things when the SIGINT is trapped
    echo "** Trapped CTRL-C"
    echo "$(tput setaf 3)requested termination, sending signal now$(tput setaf 9)"

    processes_signal ${CONVERTER_PROCESSES_QUEUE} 'SIGINT'
}
trap 'ctrl_c' INT

# --- main ----------------------------------------------------------

# check no filetypes given
# check input dir exist
#   and has write access
# check ouput dir exist
#   and has write access
#
find_files "${INPUT_DIR}" "*" "${FILETYPES[*]:-}" "${FILES_TO_PROCESS_QUEUE}"   # find the files needed for processing
processes_start 'process_convert' "${JOBS}" "${CONVERTER_PROCESSES_QUEUE}"      # start the conversion processes
# find files for copyfile command or wait for convert tasks?
# copy over files from queue (queue, output path)

trap 'error ${LINENO}' ERR  # on error, print error
trap finish EXIT            # on exit, clean up resources
wait || true                # wait for all child processes to finish
# when this finishes, it returns 1 so catch that please
echo "$(tput setaf 5)${APPNAME} is now done$(tput setaf 9)"

# --- done ----------------------------------------------------------
