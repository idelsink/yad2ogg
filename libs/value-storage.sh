#!/bin/bash
##########################################################################
# script name: value-storage
# script date: 28 Juli 2016
##########################################################################
# file system based global value storage
##########################################################################
# --- include guard -------------------------------------------------
[ -n "${VALUE_STORAGE_SH+x}" ] && return || readonly VALUE_STORAGE_SH=1
# --- global parameters ---------------------------------------------
#set -e          # kill script if a command fails
#set -o nounset  # unset values give error
#set -o pipefail # prevents errors in a pipeline from being masked
# --- include files -------------------------------------------------
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIBS_PATH="${SCRIPT_PATH}"
source "${LIBS_PATH}/b-log/b-log.sh"    # logging
# -------------------------------------------------------------------

function value_set() {
    # @description store the value of a variable on the local file system
    # @param $1 variable name
    # @param $2 variable value
    local var_name=${1:-}
    shift
    local var_value=${@:-}
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
