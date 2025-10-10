#!/usr/bin/env bash

_SCRIPT_ARGS_ARR=("$@")

function puts() { ## print call args to stdout
  printf "%s\n" "$@"
}

function log() { ## print call args to stderr
  printf "%s\n" "$@" 1>&2
}

function log_next() { ## print call args to stderr, with color and ⏳ emoji
  printf "⏳ $(tput setaf 13)%s$(tput sgr0)\n" "$@" 1>&2
}

function log_info() { ## print call args to stderr, with color and 👀 emoji
  printf "👀 $(tput setaf 6)%s$(tput sgr0)\n" "$@" 1>&2
}

function log_warn() { ## print call args to stderr, with color and ❗️ emoji
  printf "❗️ $(tput setaf 3)%s$(tput sgr0)\n" "$@" 1>&2
}

function log_error() { ## print call args to stderr, with color and ❌ emoji
  printf "❌ $(tput setaf 1)%s$(tput sgr0)\n" "$@" 1>&2
}

function log_success() { ## print call args to stderr, with color and ✅ emoji
  printf "✅ $(tput setaf 2)%s$(tput sgr0)\n" "$@" 1>&2
}

function set_errexit_when_command_fails() { ## turn on/off errexit script option. $1 - true/false (default: true)
  if [ "$1" = false ]; then set +o errexit; else set -o errexit; fi
}

function set_pipefail_with_rightmost_non_zero_status() { ## turn on/off pipefail script option. $1 - true/false (default: true)
  if [ "$1" = false ]; then set +o pipefail; else set -o pipefail; fi
}

function read_args() { ## read Makefile styled script args (like: ARG=VALUE) named as call args
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

function read_opt() { ## read script arg following opt_name arg. last call arg – var_name to declare, previous – opt_name
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

function read_arr() { ## read script arg (the one following $1) as array named $2, using $3 as elements separator (default: ' ')
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

function str_to_arr() { ## split string $1 to array named $2, using $3 as elements as separator (default: ' ')
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

function read_flags() { ## returns error code if none of the given script args present
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

function assert_defined() { ## returns error code if any variable named as on of the call args is empty/undefined
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

function var_is_true() { ## returns error code if the value of variable named $1 is not represent true ( true, 1, YES, yes, TRUE )
  local name=$1

  if value_in_list "${!name}" "" false; then
    return 3
  fi

  if value_in_list "${!name}" true 1 yes YES TRUE; then
    return
  fi

  return 3
}

function value_in_list() { ## returns error code if $1 is not found in next call args
  local match=$1
  shift
  local e
  for e in "$@"; do [ "$match" = "$e" ] && return; done
  return 3
}
