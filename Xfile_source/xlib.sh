#!/usr/bin/env bash

log_blank_line() {
  echo
}

log() {
  printf "%s\n" "$@"
}

log_next() {
  printf "⏳ $(tput setaf 13)%s$(tput sgr0)\n" "$@"
}

log_info() {
  printf "👀 $(tput setaf 6)%s$(tput sgr0)\n" "$@"
}

log_warn() {
  printf "❗️ $(tput setaf 3)%s$(tput sgr0)\n" "$@"
}

log_error() {
  printf "❌ $(tput setaf 1)%s$(tput sgr0)\n" "$@"
}

log_success() {
  printf "✅ $(tput setaf 2)%s$(tput sgr0)\n" "$@"
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

  save_previous_arg() {
    if [ -n "$param" ]; then
      _INPUT_ARR+=("$param")
    fi
  }

  for word in "$@"; do
    if [[ "$word" =~ ^(-|--).*$ ]]; then # flag or opt name (-a || --arg)
      save_previous_arg
      param=$word
      continue
    fi

    if [[ "$word" =~ ^[a-zA-Z0-9_]+=.*$ ]]; then # named arg (ARG=value)
      save_previous_arg
      param=$word
      continue
    fi

    if [[ "$param" =~ ^(-|--).*$ ]]; then # opt value
        _INPUT_ARR+=("$param=$word")
        param=''
        continue
    fi

    _INPUT_ARR+=("$word") # simple/positional/pre-processed value
  done

  save_previous_arg
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

# Read getopts-like formated args: -<flag> <value> | --<name> <value>
#
# $1 – flag name, format -f | --flag
# $2 – var name
function read_opt {
  local opt_name=$1
  local var_name=$2
  local argument

  for argument in "${_INPUT_ARR[@]}"; do
    if [[ $argument == "$opt_name="* ]]; then
      argument="${argument/"$opt_name="/}"
      eval "$var_name='$argument'"
      return
    fi
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
# Вool as stdout
#
# – Usage:
# if [[ $(read_flags "-a" "--all") = true ]]; then
#   log "FLAGGED!"
# fi
function read_flags {
  local argument
  local name

  for name in "$@"; do
    for argument in "${_INPUT_ARR[@]}"; do
      if [ "$argument" = "$name" ]; then
        echo true
        return
      fi
    done
  done

  for name in "$@"; do
    if [[ "$name" =~ ^-[a-zA-Z] ]]; then
      for argument in "${_INPUT_ARR[@]}"; do
        if [[ $argument =~ ^-[a-zA-Z]*"${name/-/}"[a-zA-Z]* ]]; then
          echo true
          return
        fi
      done
    fi
  done

  echo false
}

# Is var with provided name defined in scrip scope?
# Вool as stdout
#
# – Usage:
# if [[ $(is_defined "LOGIN") = true ]]; then
#   log "DEFINED!"
# fi
function is_defined {
  local var_name="$1"
  if [[ -z "${!var_name}" ]]; then
    echo false
  else
    echo true
  fi
}

function assert_defined {
  local has_missing=false
  local var_name

  for var_name in "$@"; do
    if [[ -z "${!var_name}" ]]; then
      log_error "Missing required param: $var_name"
      has_missing=true
    fi
  done

  if [ "$has_missing" = true ]; then
    exit 1
  fi
}

# Trusify check. (is value == 1 | true)?
# Вool as stdout
#
# – Usage:
# if [ $(dxToBool "DX_IS_CLOUD_INFRA") = true ]; then
#   log "TRUE"
# fi
function dxToBool {
  local name="$1"
  if [ "${!name}" = true ] || [ "${!name}" = 1 ]; then
    echo true
    return
  fi
  echo false
}

cache_args "$@"
