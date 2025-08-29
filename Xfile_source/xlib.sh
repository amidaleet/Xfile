#!/usr/bin/env bash

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

_INPUT_ARR=()

# Parse input to args that looks like:
#
# name='Large string argument'
# --name value
# -name value
# --flag
# -f
# positional value
function cache_args {
  local param=''
  local word

  for word in "$@"; do
    if [[ "$word" =~ ^(-|--).*$ ]]; then # flag or opt name (-a || --arg)
      if [ -n "$param" ]; then _INPUT_ARR+=("$param"); fi
      param=$word
      continue
    fi

    if [[ "$word" =~ ^[a-zA-Z0-9_]+=.*$ ]]; then # named arg (ARG=value)
      if [ -n "$param" ]; then _INPUT_ARR+=("$param"); fi
      _INPUT_ARR+=("$word")
      param=''
      continue
    fi

    if [ -n "$param" ]; then # opt value
        _INPUT_ARR+=("$param=$word")
        param=''
        continue
    fi

    _INPUT_ARR+=("$word") # simple positional value
  done

  if [ -n "$param" ]; then _INPUT_ARR+=("$param"); fi
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
    for argument in "${_INPUT_ARR[@]}"; do
      if [[ $argument == "$name="* ]]; then
        argument="${argument/"$name="/}"
        eval "$name='$argument'"
        continue 2 # name loop
      fi
    done
  done
}

# Read getopts-like formatted args: -<flag> <value> | --<name> <value>
#
# $1 – flag name, format -f | --flag
# $2 – var name
function read_opt {
  local var_name=${*: -1}
  local opt_name
  local argument

  for opt_name in "${@:1:$#-1}"; do
    for argument in "${_INPUT_ARR[@]}"; do
      if [[ $argument == "$opt_name="* ]]; then
        argument="${argument/"$opt_name="/}"
        eval "$var_name='$argument'"
        return
      fi
    done
  done
}

# Parse bash array form string arg: (-|--)<flag> "<element0> <element1>"
#
# $1 – flag name, format -f | --flag
# $2 – var name
# $3 – separator symbol (to use as IFS)
function read_arr {
  local opt_name=$1
  local arr_name=$2
  local separator=$3
  local argument

  for argument in "${_INPUT_ARR[@]}"; do
    if [[ $argument == "$opt_name="* ]]; then
      argument="${argument/"$opt_name="/}"
      str_to_arr "$argument" "$arr_name" "$separator"
      return
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
      for argument in "${_INPUT_ARR[@]}"; do
        if [[ $argument =~ ^-[a-zA-Z]*"${short_flag}"[a-zA-Z]* ]]; then
          return
        fi
      done
    else
      for argument in "${_INPUT_ARR[@]}"; do
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

cache_args "$@"
