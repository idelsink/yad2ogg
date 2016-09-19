#!/usr/bin/env bash
##########################################################################
# script name: processes
# script date: 28 Juli 2016
##########################################################################
# start and manage concurrent processes
##########################################################################
# --- include guard -------------------------------------------------
[ -n "${PROCESSES_SH+x}" ] && return || readonly PROCESSES_SH=1
# --- global parameters ---------------------------------------------
#set -e          # kill script if a command fails
#set -o nounset  # unset values give error
#set -o pipefail # prevents errors in a pipeline from being masked
# --- include files -------------------------------------------------
SCRIPT_PATH="$(dirname $( realpath ${BASH_SOURCE[0]} ) )"
LIBS_PATH="${SCRIPT_PATH}"
source "${LIBS_PATH}/b-log/b-log.sh"    # logging
source "${LIBS_PATH}/queue.sh"          # queue via file system
# -------------------------------------------------------------------

function processes_start() {
    # @description start a multiple of concurrent processes and store their PIDs
    # @param $1 function to start
    # @param $2 number of times to start this process
    # @param $3 identifier of these processes (used to make a queue for the PIDs)
    local function="${1:-}"
    local jobs=${2:-"1"}
    local identifier=${3:-"${function}"}
    local queue_name="${identifier:-"default"}"
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
    local queue_name="${identifier:-"default"}"
    #pid=""
    pid=$(queue_read ${queue_name})
    while [ ! -z "${pid}" ]; do
        # check if pid exists
        if [ -n "$(ps -p $pid -o pid=)" ]; then
           kill -${signal} $pid || true
           DEBUG "signaled process with PID: ${pid}"
        fi
        pid=$(queue_read ${queue_name})
    done
}
