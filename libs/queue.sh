#!/bin/bash
##########################################################################
# script name: queue
# script date: 28 Juli 2016
##########################################################################
# a simple queue interface
#
# use and manage a simple fifo queue
# in a local file system
# - init 'queue name' 'clear existing'
# - add 'queue name' 'data'
# - read 'queue name' [returns via echo]
##########################################################################
# --- include guard -------------------------------------------------
[ -n "${QUEUE_SH+x}" ] && return || readonly QUEUE_SH=1
# --- global parameters ---------------------------------------------
#set -e          # kill script if a command fails
#set -o nounset  # unset values give error
#set -o pipefail # prevents errors in a pipeline from being masked
# --- include files -------------------------------------------------
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_PATH_LOCAL="${SCRIPT_PATH}"
LIBS_PATH="${SCRIPT_PATH}"
LIBS_PATH_LOCAL="${SCRIPT_PATH}"
source "${LIBS_PATH}/b-log/b-log.sh"    # logging
# -------------------------------------------------------------------

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
function queue_size() {
    # @description returns the size of a queue
    # @param $1 the queue name
    # @return returns the size of a queue
    local readonly queue_name_prefix="queue_"
    local queue_name=${1:-}
    local queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    local num_of_lines=0
    num_of_lines=$(wc -l < "${queue_file}")
    echo ${num_of_lines}
}
function queue_look_sl() {
    # @description look in queue (single line)
    # @param $1 the queue name
    # @return returns the queue as a string with spaces
    local readonly queue_name_prefix="queue_"
    local queue_name=${1:-}
    local queue_file="${QUEUE_STORAGE}/${queue_name_prefix}${queue_name}"
    local queue=""
    queue=$(tr '\n' ' ' < "${queue_file}")
    echo "${queue}"
}
