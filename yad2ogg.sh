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
set -o nounset # unset values give error

VERSION=0.0.1
APPNAME="yad2ogg"
USAGE="
Usage: command -hVio
-h --help help
-V --version version
-i --input input directory
-o --output destination/output directory
-q quality switch
-j number of concurrent jobs
-c --copyfile 'xx' copy files over from original directory to destination where tracks were converted eg. '*.cue or *.jpg'.
-m --metadata keep the metadata(tags) from the original files
-w --overwrite over write existing files
=FILE TYPES=
types of input files to process
-f file type eg. 'flac or ogg'
Or use these parameters(recommended):
--WAV
--FLAC
--ALAC
--MP3
--OGG
--M4A
--ALL
-a all supported file types
"

PRINT_USAGE(){
	echo "$USAGE"
}

# --- global variables ----------------------------------------------
INPUT_DIR='./'  # input directory
OUTPUT_DIR='./' # output directory
JOBS=1          # number of concurrent jobs
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

# queues
readonly FILES_TO_PROCESS_QUEUE="files_to_process"
readonly FILES_TO_COPY_OVER="files_to_copy_over"

FILETYPES=() # file types wanted

# process queue
CONVERTER_PROCESSES=() # running converter processes (PIDs)
KEEP_METADATA=true # keep metadata(tags)

# directories
readonly TMP_DIR="/tmp"
readonly APP_DIR="${TMP_DIR}/${APPNAME}"
readonly LOCKFILE_DIR="${APP_DIR}/lock"
readonly QUEUE_STORAGE="${APP_DIR}/queue"
readonly GLOBAL_STORE_DIR="${APP_DIR}/global_store"

# some error codes to use in the file
readonly ERR_NO_MORE_FILES="no more files"
readonly ERR_MISSING_PARAMETER="missing parameter"
readonly ERR_MUTEX_TIMEOUT="mutex timeout"
readonly ERR_TYPE_NOT_SUPORTED="type not suported"

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
        "--copyfile") set -- "$@" "-c" ;;
        "--metadata") set -- "$@" "-m" ;;
        # filetypes
        "--WAV") set -- "$@" "-f${SUPORTED_FILETYPES[$WAV_LIST]}" ;;
        "--FLAC") set -- "$@" "-f${SUPORTED_FILETYPES[$FLAC_LIST]}" ;;
        "--ALAC") set -- "$@" "-f${SUPORTED_FILETYPES[$ALAC_LIST]}" ;;
        "--MP3") set -- "$@" "-f${SUPORTED_FILETYPES[$MP3_LIST]}" ;;
        "--OGG") set -- "$@" "-f${SUPORTED_FILETYPES[$OGG_LIST]}" ;;
        "--M4A") set -- "$@" "-f${SUPORTED_FILETYPES[$M4A_LIST]}" ;;
        "--ALL") set -- "$@" "-a" ;;
        *) set -- "$@" "$arg"
  esac
done
# get options
while getopts "hVi:o:q:f:j:ac:m" optname
do
    case "$optname" in
        "h")
            PRINT_USAGE
            exit 0;
            ;;
        "V")
            echo "Version $VERSION"
            exit 0;
            ;;
        "i")
            #echo "Option: $OPTARG"
            INPUT_DIR=$OPTARG
            ;;
        "o")
            #echo "option output: $OPTARG"
            OUTPUT_DIR=$OPTARG
            ;;
        "q")
            echo "option quality: $OPTARG"
            ;;
        "f")
            echo "option filetype: '$OPTARG'"
            FILETYPES[${#FILETYPES[@]}]=$OPTARG
            echo ${FILETYPES[*]}
            ;;
        "a")
            echo "option filetype: (all)"
            FILETYPES=${SUPORTED_FILETYPES[*]}
            echo ${FILETYPES[*]}
            ;;
        "c")
            echo "option copyfile: $OPTARG"
            ;;
        "m")
            echo "keep metadata"
            ;;
        "j")
            JOBS=$OPTARG
            echo "option jobs: $JOBS"
            ;;
        *)
            echo "Unknown error while processing options"
            exit 0;
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
    local readonly queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
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
    local readonly queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    queue_init $queue_name # make sure that the queue exists
    queue_data=$(head -n 1 "$queue_file") # get first line of file
    sed -i 1d $queue_file # remove first line of file
    echo $queue_data
}

# FIX-----------------------------------------------------------------------------------------
# replace this in the code and remove this
# make file and dir if not exist
mkfilep() { mkdir -p "$(dirname "$1")" || return; touch "$1"; }

#############################
# mutex interface
#############################
# use and manage a simple mutex implementation
# via a local file system
# - lock 'mutex name' [returns 1(succeeded) or 0(failed)]
# - free 'mutex name'
mutex_lock(){
    # @description locks a mutex
    # if no mutex exists, one will be made
    # @param $1 the mutex name
    # @return returns status: true/1(succeeded) or false/0(failed)
    local mutex_name=${1:-}
    local readonly LOCK_FD=200
    if [ -z "$mutex_name" ]; then
        return false # missing mutex name
    fi
    local prefix=`basename $0`
    prefix+="_$mutex_name"
    local fd=${2:-$LOCK_FD}
    local lock_file="${LOCKFILE_DIR}/${prefix}.lock"

    # create lock file
    mkfilep "$lock_file"
    eval "exec $fd>$lock_file"

    # acquier the lock
    flock -n $fd \
        && return 0 \
        || return 1
}
mutex_free(){
    # @description frees a mutex
    # use this when you have the mutex
    # of the to be freed mutex
    # @param $1 the mutex name
    local mutex_name=${1:-}
    if [ -z "$mutex_name" ]; then
        return false # missing mutex name
    fi
    local prefix=`basename $0`
    prefix+="_$mutex_name"
    local lock_file=$LOCKFILE_DIR/$prefix.lock
    if [ -e "$lock_file" ]; then
        rm $lock_file
    fi
}


########################################## PARAMETER STORAGE HERE

#############################
# conversion command
#############################
# file, other parameters for specific type
# get te conversion command based on filetype
# command can be found in the 'conversion_command' variable
get_conversion_command() {
    # @description returns a conversion command
    # based on the file type
    # @param $1 filename of the to converted file
    # @param $2 extra parameters ......... @todo add more
    if [ -z "$1" ]; then
        echo "missing file"
        exit 1
    else
        file=$1
        type=${file##*.}
    fi
    if [ -z "$2" ]; then
        # nothing
        params=""
    else
        params=$2
    fi
    local output_file=${file/$INPUT_DIR/$OUTPUT_DIR}
    conversion_output_dir="${output_file%/*}" # directory part of file
    conversion_command=""
    #echo "input dir: $INPUT_DIR"
    #echo "output dir: $OUTPUT_DIR"
    #echo "Type: $type"
    #echo "File: $file"
    #echo "Ouput file: $output_file"
    #echo "Parameters: $params"
    case $type in
        ${SUPORTED_FILETYPES[$WAV_LIST]} )
            #echo "conversion of 'wav'"
            conversion_command="WAV"
            ;;
        ${SUPORTED_FILETYPES[$FLAC_LIST]} )
            #echo "conversion of 'flac'"
            conversion_command="FLAC"
            ;;
        ${SUPORTED_FILETYPES[$MP3_LIST]} )
            #echo "conversion of 'mp3'"
            conversion_command="ffmpeg -i '$file' -acodec libvorbis -aq 3 '${output_file%.*}.ogg'"
            ;;
        ${SUPORTED_FILETYPES[$OGG_LIST]} )
            #echo "conversion of 'ogg'"
            conversion_command="OGG"
            ;;
        *)
            #echo "filetype not supported"
            conversion_command=$ERR_TYPE_NOT_SUPORTED
            ;;
    esac
    return 0
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

    echo "path: $path"
    echo "filename: $filename"
    echo "filetypes: $filetypes"
    echo "queue name: $queue_name"
    queue_init ${queue_name} true
    for filetype in ${filetypes}; do
        find "${path}" -name "${filename}.${filetype}" -print0 | while IFS= read -r -d '' file; do
             queue_add "${queue_name}" "$file"
        done
    done
}

# hmm this echo is handy for now, but remove it later.. oke?
echo "-----------------------"
#
# 1. read files to convert
# 2. startup conversion
# 2. copy files over

# @todo better interface and some documentation and better function names?
set_global() {
    local var_name=""
    local var_value=""
    local GLOBAL_LOCATION="${GLOBAL_STORE_DIR}"
    if [ -z "$1" ]; then
        echo "missing variable name"
        return 0
    else
        var_name=$1
    fi
    if [ -z "$2" ]; then
        echo "missing variable value"
        return 0
    else
        var_value=$2
    fi
    #echo "set: '$var_name' with value: '$var_value' in ${GLOBAL_LOCATION}/$var_name"
    mkfilep "${GLOBAL_LOCATION}/$var_name"
    echo "$var_value" > "${GLOBAL_LOCATION}/$var_name"
}
get_global() {
    local var_name=""
    local var_value=0
    local GLOBAL_LOCATION="${GLOBAL_STORE_DIR}"
    if [ -z "$1" ]; then
        echo "missing variable name"
        return 0
    else
        var_name=$1
    fi
    #echo "get: '$var_name' in ${GLOBAL_LOCATION}/$var_name"
    #read var name from file in tmp
    if [ -e "${GLOBAL_LOCATION}/$var_name" ]; then
        var_value=$(<${GLOBAL_LOCATION}/$var_name)
    fi
    #echo "var value: $var_value"
    return ${var_value}
}

# the index from where one file can be claimed
#set_global "FILES_INDEX" 0

get_file_to_convert() {
    local filename=""
    local timeout=5 #seconds
    local retry_timeout=$(bc -l <<< "scale = 2; $timeout/10.0")
    local retry_count=0
    local current_timeout=0

    # wait to get mutex, with timeout
    while true; do
        if mutex_lock "get_convert_file" ; then
            filename=$(queue_read "${FILES_TO_PROCESS_QUEUE}")
            if [ -z "$filename" ]; then
                filename=$ERR_NO_MORE_FILES
            fi     # $String is null.
            # free the mutex
            sleep 5;
            mutex_free "get_convert_file"
            break
        else
            current_timeout=$(bc -l <<< "scale = 2; $retry_timeout*$retry_count")
            if [[ ${current_timeout%%.*} -gt $timeout ]]; then
                echo $ERR_MUTEX_TIMEOUT
                return 0
            fi
            ((retry_count++))
            sleep $retry_timeout
        fi
    done
    echo $filename # return the filename
}

convert_process() {
    local PROCESS_PID=$BASHPID
    local PROCESS_PPID=$PPID
    local TERMINATE=false
    local filename
    kill_process() {
        echo "set terminate signal"
        TERMINATE=true
    }
    trap kill_process INT
    echo "process with PID: $PROCESS_PID is now running"


    # get file from queue
    # convert
    local count=0
    while true; do
        ((count++))
        #echo $PROCESS_PID: $count
        # get file to convert
        filename=$(get_file_to_convert)
        if [ "$filename" == "$ERR_NO_MORE_FILES" ]; then
            echo "$PROCESS_PID: no more files left for me"
            return 0 # stop process
        elif [ "$filename" == "$ERR_MUTEX_TIMEOUT" ]; then
            echo "$PROCESS_PID: mutex timeout"
        else
            #echo "$PROCESS_PID: filename: ${filename}"
            # get convert command
            get_conversion_command "$filename" "-q1"
            # make conversion dir
            #echo "$conversion_output_dir"
            if [ ! -d "$conversion_output_dir" ]; then
                # directory for output does not exist
                mkdir -p "$conversion_output_dir"
                if [ $? -ne 0 ] ; then
                    echo "mkdir failed"
                else
                    echo "success"
                    # run conversion command
                fi
            fi
            # run convert command
            echo "$conversion_command"
            #echo "$conversion_output_dir"
        fi
        #sleep 0.5;
        if $TERMINATE ; then
            echo "stopping process"
            return 0;
        fi
    done
    return 0
}

# start processes and add them to the array
start_converter_processes() {
    echo "starting convert process(es)"
    for (( i = 0; i < $JOBS; i++ )); do
        convert_process& # start new process
        CONVERTER_PROCESSES[${#CONVERTER_PROCESSES[@]}]=$! # add to array
    done
}

# kill all converter processes
kill_converter_processes() {
    for pid in ${CONVERTER_PROCESSES[*]}; do
        echo "killing process: '$pid'"
        pkill $pid
    done
    unset CONVERTER_PROCESSES # clear processes
}

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
function ctrl_c() {
        echo "** Trapped CTRL-C"
        kill_converter_processes
}

# --- main ----------------------------------------------------------

find_files "${INPUT_DIR}" "*" "${FILETYPES[*]}" "${FILES_TO_PROCESS_QUEUE}" # find the files needed for processing
start_converter_processes   # start the conversion of the found files
# find files for copyfile command
# copy over files from queue (queue, output path)
wait                        # wait for all child processes to finish
kill_converter_processes    # redundant killing, if something was missed
