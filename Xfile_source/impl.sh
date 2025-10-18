#!/usr/bin/env bash

source "$GIT_ROOT/Xfile_source/xlib.sh"

# ---------- Manual ----------

function task_args { ## list $1 task args from $2 file (default: $0 – this Xfile)
  impl:task_args "$@" || impl:task_args_in_linked_children "$@"
}

impl:task_args() { ## list $1 task args from $2 file (default: $0 – this Xfile)
  local file=${2:-$0}
  local funcDefStr=()
  if [ ! -f "$file" ]; then return 4; fi

  while IFS= read -r line; do
    funcDefStr+=("$line")
  done < <(grep -B 1 -E "^function $1(\(\))? {.*" "$file")

  if [[ "${#funcDefStr[@]}" -eq 2 ]]; then
    if [[ "${funcDefStr[0]}" =~ ^\#\#\ .* ]]; then
      echo "${funcDefStr[0]//## /}"
    else
      echo
    fi
  else
    return 3
  fi
}

function task_names { ## list available tasks in this Xfile
  show_task_names_from "$0"
  show_task_names_from_linked_children
}

show_task_names_from() { ## print task names list from $1 file, $2 – optional prefix
  if [ ! -f "$1" ]; then
    return
  fi

  local func_lines
  func_lines=$(grep -E '^function [a-zA-Z0-9_:]+(\(\))? {.*' "$1" || true)
  if [ -z "$func_lines" ]; then
    return
  fi

  echo "$func_lines" |
    sed -e "s/function /$2/" |
    awk 'BEGIN {FS = " {"}; {
      gsub(/\(\)/, "", $1);
      gsub(/##/, "", $2);
      printf "%s\n", $1
    }
    '
}

show_tasks() { ## $1 – header override (may be empty), $2 – tasks prefix
  show_tasks_from "$0" "$1" "$2"
  show_tasks_from_linked_children "$2"
}

show_tasks_from() { ## print task descriptions list from $1 file, $2 – header override (may be empty), $3 – tasks prefix
  if [ ! -f "$1" ]; then
    log_warn "Found missing file while reading tasks: $1"
    return
  fi

  if [ -n "$2" ]; then
    echo "$(tput setaf 4)# $2$(tput sgr0)"
  else
    echo "$(tput setaf 4)# ${1##"$GIT_ROOT/"} tasks:$(tput sgr0)"
  fi
  local picked_lines
  picked_lines=$(grep -E '(^function [a-zA-Z0-9_:]+(\(\))? {.*)|(^# ----------).*' "$1" || true)
  if [ -z "$picked_lines" ]; then
    log_warn "No any visible tasks! You shall define some like 'function my_task() {' in your Xfile"
    return
  fi

  echo "$picked_lines" |
    sed -e "s/function /$3/" |
    awk 'BEGIN {FS = " {"}; {
      if ($1 ~ /^# ----------/) {
        gsub(/# ---------- /, "", $1);
        gsub(/ ----------/, "", $1);
        printf "\n"
        printf "\033[92m## %s\033[0m\n", $1
      } else {
        gsub(/\(\)/, "", $1);
        gsub(/##/, "", $2);
        printf "  \033[93m%-46s\033[92m %s\033[0m\n", $1, $2
      }
    }
    '
  echo
}

function help { ## print full "How to use?" info for this Xfile
  show_tasks
  usage
}

function usage { ## print common usage instructions for Xfile
  log_note 'To run task call:' \
    "$0 <task> <args>" \
    "x <task> <args>" \
    ''
  log_note "To setup alias 'x' and enable autocompletion call:" \
    "./Xfile install_xfile"
}

# ---------- Dispatch ----------

function begin_xfile_task { ## execute task $1 as shell command passing following call args
  local task_name="${_SCRIPT_ARGS_ARR[0]}" child_idx

  if value_in_list "$task_name" "" help --help; then
    help
    return
  fi

  if task_declared "$task_name"; then
    push_task_stack "$task_name"
    "${_SCRIPT_ARGS_ARR[@]}"
  elif child_idx=$(try_find_child_with_task "$task_name"); then
    try_run_task_in_child "$child_idx" "$task_name"
  else
    log_error "🤔 No task named: '$task_name' in this Xfile or linked children!" \
      'Maybe misspelled?' \
      'Try: x help' \
      'Call args:' "${_SCRIPT_ARGS_ARR[@]}"
    return 8
  fi
}

function task { ## run task (as new bash process) passing call args
  log_move_to_task "$1"
  local error_code=0
  $0 "$@" || { error_code=$?; }
  log_move_from_task "$1" "$error_code"
  return "$error_code"
}

function task_declared { ## returns error code if $1 is not a defined func in this Xfile or sourced files
  declare -F "$1" >/dev/null
}

log_move_to_task() {
  printf "🏃‍♀️‍➡️ $(tput setaf 6)in: %s > %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$1" 1>&2
}

log_move_from_task() {
  if [ -n "$2" ] && [ "$2" != 0 ]; then
    printf "💥 $(tput setaf 1)at: %s > %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$1" 1>&2
  else
    printf "🏃🏻‍♀️ $(tput setaf 4)out: %s < %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$1" 1>&2
  fi
}

push_task_stack() {
  if [ -z "$_X_TASK_STACK_STR" ]; then
    _X_TASK_STACK_STR=$1
  else
    _X_TASK_STACK_STR="$_X_TASK_STACK_STR > $1"
  fi

  export _X_TASK_STACK_STR
}

# ---------- Children ----------

_LINKED_XFILE_CHILDREN=()

function link_child_xfile { ## make child Xfile tasks executable from this Xfile. $1 - path to child, $2 - optional tasks prefix
  _LINKED_XFILE_CHILDREN+=("$1;$2")
}

function child_task { ## run task in $1 "child" Xfile forwarding script args, $2 – optional task name (may be in script args)
  if [ -n "$2" ]; then
    "$1" "$2" "${_SCRIPT_ARGS_ARR[@]:1}"
  else
    "$1" "${_SCRIPT_ARGS_ARR[@]:1}"
  fi
}

try_find_child_with_task() {
  local idx=-1 child child_info child_path child_prefix child_task_name

  for child in "${_LINKED_XFILE_CHILDREN[@]}"; do
    (( ++idx ))
    IFS=';' read -r -a child_info <<<"$child"

    child_path="${child_info[0]}"
    child_prefix="${child_info[1]}"

    if [ -n "$child_prefix" ]; then
      if [[ "$task_name" == "$child_prefix"* ]]; then
        child_task_name="${task_name##"$child_prefix"}"
      else
        continue
      fi
    else
      child_task_name=$task_name
    fi

    if "$child_path" task_declared "$child_task_name"; then
      echo -n "$idx"
      return
    fi
  done

  return 9
}

try_run_task_in_child() {
  local child_info child_path child_prefix child_task_name

  IFS=';' read -r -a child_info <<<"${_LINKED_XFILE_CHILDREN["$1"]}"

  child_path="${child_info[0]}"
  child_prefix="${child_info[1]}"

  "$child_path" "${2##"$child_prefix"}" "${_SCRIPT_ARGS_ARR[@]:1}"
}

impl:task_args_in_linked_children() { ## list $1 task args from first match in children files
  local child child_info child_path child_prefix task_name

  if [ "${#_LINKED_XFILE_CHILDREN[@]}" -eq 0 ]; then return 7; fi

  for child in "${_LINKED_XFILE_CHILDREN[@]}"; do
    IFS=';' read -r -a child_info <<<"$child"

    child_path="${child_info[0]}"
    child_prefix="${child_info[1]}"

    if [ -n "$child_prefix" ]; then
      if [[ "$1" == "$child_prefix"* ]]; then
        task_name="${1##"$child_prefix"}"
      else
        continue
      fi
    else
      task_name=$1
    fi

    "$child_path" task_args "$task_name" && return || true
  done

  return 9
}

show_task_names_from_linked_children() {
  local child child_info child_path child_prefix

  for child in "${_LINKED_XFILE_CHILDREN[@]}"; do
    IFS=';' read -r -a child_info <<<"$child"

    child_path="${child_info[0]}"
    child_prefix="${child_info[1]}"

    "$child_path" task_names | sed "s/^/$child_prefix/"
  done
}

show_tasks_from_linked_children() { ## $1 – this Xfile prefix in parent Xfile
  local child child_info child_path child_prefix

  for child in "${_LINKED_XFILE_CHILDREN[@]}"; do
    IFS=';' read -r -a child_info <<<"$child"

    child_path="${child_info[0]}"
    child_prefix="${child_info[1]}"

    "$child_path" show_tasks '' "$1$child_prefix"
  done
}

# ---------- Xfile setup ----------

function install_xfile { ## install autocompletion to zsh/omz/bash
  impl:install_xfile "$@"
}

impl:install_xfile() {
  cp -f Xfile_source/completion.sh "$HOME/.xfile_completion"

  log_success "Xfile autocompletion script has been copied to your home at:" \
    "$HOME/.xfile_completion" \
    ''
  log_warn "To activate autocompletion, you must source this script on Terminal session launch, like:" \
    '```sh' \
    "source \"\$HOME/.xfile_completion\"" \
    '```' \
    ''
  log_note "Put source command to appropriate start-up shell script:" \
    "- If using bash, put activation command to end of ~/.bash_profile file." \
    "- If using zsh or Oh-My-Zsh, put activation command to end of ~/.zshrc file." \
    ''
  log_warn "Restart Terminal session to take effect!"
}

function xfile_init_load() { ## load sources and Xfile sample to $1 dir from $2 git ref
  if [ -z "$1" ]; then return 3; fi

  cd "$1"
  export XFILE_REF=${2:-main}

  curl -fsS "https://raw.githubusercontent.com/amidaleet/Xfile/$XFILE_REF/Xfile_source/setup.sh" -o setup.sh

  log_info "Will execute next script:" '```sh'
  cat setup.sh
  log '```'
  chmod +x setup.sh
  ./setup.sh
  rm -f setup.sh
}

function xfile_init_copy() { ## copy sources and Xfile sample to $1 dir
  if [ -z "$1" ]; then return 3; fi

  cd "$1"
  rm -rf Xfile_source
  mkdir -p Xfile_source
  cd "$GIT_ROOT"

  cp -rf "$GIT_ROOT/Xfile_source" "$1"
  if [ ! -f "$1/Xfile" ]; then
    cp "$GIT_ROOT/Xfile_source/template.sh" "$1/Xfile"
  fi
}
