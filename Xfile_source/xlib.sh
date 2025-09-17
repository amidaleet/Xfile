#!/usr/bin/env bash

_SCRIPT_ARGS_ARR=("$@")

puts() {
  printf "%s\n" "$@"
}

log() {
  printf "%s\n" "$@" 1>&2
}

log_next() {
  printf "⏳ $(tput setaf 13)%s$(tput sgr0)\n" "$@" 1>&2
}

log_info() {
  printf "👀 $(tput setaf 6)%s$(tput sgr0)\n" "$@" 1>&2
}

log_warn() {
  printf "❗️ $(tput setaf 3)%s$(tput sgr0)\n" "$@" 1>&2
}

log_error() {
  printf "❌ $(tput setaf 1)%s$(tput sgr0)\n" "$@" 1>&2
}

log_success() {
  printf "✅ $(tput setaf 2)%s$(tput sgr0)\n" "$@" 1>&2
}

# Makefile style 'ARG=VALUE' arguments parser
#
# - Usage:
# read_args "LOGIN" "PASS"
# echo "login = $LOGIN"
function read_args {
  local argument
  local name

  for name in "$@"; do
    for argument in "${_SCRIPT_ARGS_ARR[@]}"; do
      if [[ $argument == "$name="* ]]; then
        argument="${argument/"$name="/}"
        eval "$name='$argument'"
        continue 2 # name loop
      fi
    done
  done
}

# Read getopts-like formatted args: -<name> <value> | --<name> <value>
#
# $1 – value name, format -n | --name
# $2 – var name
function read_opt {
  local var_name=${*: -1}
  local opt_name
  local argument
  local has_match=false

  for opt_name in "${@:1:$#-1}"; do
    for argument in "${_SCRIPT_ARGS_ARR[@]}"; do
      if [ "$has_match" = true ]; then
        eval "$var_name='$argument'"
        return
      elif [ "$argument" = "$opt_name" ]; then
        has_match=true
      fi
    done
    has_match=false
  done
}

# Parse bash array form string arg: (-|--)<array_name> "<element 0><separator><element 1>"
#
# $1 – arg name, format -a | --array
# $2 – var name
# $3 – separator symbol (to use as IFS)
function read_arr {
  local opt_name=$1
  local arr_name=$2
  local separator=$3
  local argument
  local has_match=false

  for argument in "${_SCRIPT_ARGS_ARR[@]}"; do
    if [ "$has_match" = true ]; then
      str_to_arr "$argument" "$arr_name" "$separator"
      return
    elif [ "$argument" = "$opt_name" ]; then
      has_match=true
    fi
  done
}

function str_to_arr {
  local _ifs="${3:-' '}"

  if [ "$_ifs" = '\n' ]; then
    local line
    eval "$2=()"
    while IFS=$'\n' read -r line; do
      if [ -z "$line" ]; then continue; fi
      eval "$2+=( \"\$line\" )"
    done <<< "$1"
  else
    local tmp
    local el
    IFS="$_ifs" read -r -a tmp <<<"$1"
    eval "$2=()"
    for el in "${tmp[@]}"; do
      if [ -z "$el" ]; then continue; fi
      eval "$2+=( \"\$el\" )"
    done
  fi
}

# Is -f | --flag has been passed in script call?
#
# Status code, no output.
#
# – Usage:
# if read_flags -a --all; then
#   log "FLAGGED!"
# fi
function read_flags {
  local argument
  local name
  local short_flag

  for name in "$@"; do
    short_flag="${name/-/}"
    if [ "${#short_flag}" = 1 ]; then # one letter flag can be mixed with others: "-b" is in "-abc"
      for argument in "${_SCRIPT_ARGS_ARR[@]}"; do
        if [[ $argument =~ ^-[a-zA-Z]*"${short_flag}"[a-zA-Z]* ]]; then
          return
        fi
      done
    else
      for argument in "${_SCRIPT_ARGS_ARR[@]}"; do
        if [ "$argument" = "$name" ]; then
          return
        fi
      done
    fi
  done

  return 3
}

# Fail if any of the given args names is not defined as variable in script scope.
#
# Status code, no output.
#
# – Usage:
# assert_defined LOGIN PASS
function assert_defined {
  local has_missing=false
  local var_name

  for var_name in "$@"; do
    if [ -z "${!var_name}" ]; then
      log_error "Missing required param: $var_name"
      has_missing=true
    fi
  done

  if var_is_true has_missing; then
    return 3
  fi
}

# Trusify check given variable value. (is value in [true, 1, YES, yes])?
#
# Status code, no output.
#
# – Usage:
# if var_is_true DX_IS_CLOUD_INFRA; then
#   log TRUE
# fi
function var_is_true {
  local name=$1

  if value_in_list "${!name}" "" false; then
    return 3
  fi

  if value_in_list "${!name}" true 1 yes YES TRUE; then
    return
  fi

  return 3
}

# Trusify check given variable value. (is value in [true, 1, YES, yes])?
#
# Status code, no output.
#
# – Usage:
# if value_in_list element el1 el2 el3; then
#   log "element is in list!"
# fi
#
# if value_in_list element "${arr[@]}"; then
#   log "element is in array!"
# fi
function value_in_list {
  local match=$1
  shift
  local e
  for e in "$@"; do [ "$match" = "$e" ] && return; done
  return 3
}

function func_defined {
  declare -F "$1" > /dev/null
}
