#!/bin/bash

log_blank_line() {
  echo
}

log() {
  printf "%s\n" "$@"
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

declare -a _INPUT_ARR

# Parse input to args that looks like:
# name='string   value'
# --name value
# --flag
# -flag
function cache_args {
  local param=''
  local word
  local param

  for word in "$@"; do
    if [[ "$word" =~ ^(-|--).*$ ]]; then
      # is flag (-f || --flag)
      if [[ -n $param ]]; then
        _INPUT_ARR+=("$param")
        param=''
      fi
      param=$word
      continue
    fi

    if [[ "$word" =~ ^[a-zA-Z0-9_]+=.*$ ]]; then
      # is named param head (ARG=head_of_val)
      if [[ -n $param ]]; then
        _INPUT_ARR+=("$param")
      fi
      param=$word
      continue
    fi

    if [[ -n $param ]]; then
      if [[ "$param" =~ ^(-|--)[a-zA-Z0-9_]+$ ]]; then
        # opt flag (-a || --argument)
        param+="=$word"
      else
        param+=" $word"
      fi
    else
      _INPUT_ARR+=("$word")
    fi
  done

  if [[ -n $param ]]; then
    _INPUT_ARR+=("$param")
  fi
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
        IFS='=' read -r -a array <<<"$argument"
        eval "${array[0]}=\"${array[1]}\""
        continue 2 # name loop
      fi
    done
  done
}

# Read getopts-like formated args: -<flag> <value> | --<name> <value>
#
# $1 – flag name, formart -f | --flag
# $2 – var name
function read_opt {
  local opt_name="$1"
  local var_name="$2"
  local argument

  for argument in "${_INPUT_ARR[@]}"; do
    if [[ $argument == "$opt_name="* ]]; then
      IFS='=' read -r -a array <<<"$argument"
      eval "${var_name}=\"${array[1]}\""
      return 0
    fi
  done
}

# Parse bash array form space-separated string arg: (-|--)<flag> "<element0> <element1>"
#
# $1 – flag name, formart -f | --flag
# $2 – var name
function read_arr {
  local opt_name="$1"
  local var_name="$2"
  local argument

  for argument in "${_INPUT_ARR[@]}"; do
    if [[ $argument == "$opt_name="* ]]; then
      IFS='=' read -r -a array <<<"$argument"
      eval "${var_name}=( ${array[1]} )"
      return 0
    fi
  done
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

  for argument in "${_INPUT_ARR[@]}"; do
    for name in "$@"; do
      if [[ $argument == "$name" ]]; then
        echo "true"
        return 0
      fi
    done
  done

  echo "false"
}

# Is var with provided name defined in scrip scoupe?
# Вool as stdout
#
# – Usage:
# if [[ $(is_defined "LOGIN") = true ]]; then
#   log "DEFINED!"
# fi
function is_defined {
  local var_name="$1"
  if [[ -z "${!var_name}" ]]; then
    echo "false"
  else
    echo "true"
  fi
}

function assert_defined {
  declare -a missing
  local var_name

  for var_name in "$@"; do
    if [[ -z "${!var_name}" ]]; then
      missing+=("$var_name")
    fi
  done

  for var_name in "${missing[@]}"; do
    log_error "Missing required param: $var_name"
  done

  if [[ ! "${#missing[@]}" -eq 0 ]]; then
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
  if [ "${!name}" = true ] || [ "${!name}" == 1 ]; then
    echo true
    return 0
  fi
  echo false
}

cache_args "$@"
