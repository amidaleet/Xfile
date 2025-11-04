#!/usr/bin/env bash

source "$GIT_ROOT/Xfile_source/xlib.sh"

# ---------- Manual ----------

function task_args { ## list $1 task args from $THIS_XFILE_PATH, loaded sources and children (if root)
  if impl:task_args "$1"; then
    return
  elif impl:task_args_in_loaded_sources "$1"; then
    return
  elif this_xfile_is_root && impl:task_args_in_linked_children "$1"; then
    return
  else
    return 9
  fi
}

impl:task_args() { ## list $1 task args from $2 file (default: $THIS_XFILE_PATH)
  local file=${2:-$THIS_XFILE_PATH}

  if [ ! -f "$file" ]; then return 4; fi

  local decl_lines
  decl_lines=$(grep -B 1 -m 1 -E "^(function $1(\(\))?|$1\(\)) ({|\().*" "$file")

  if [ -z "$decl_lines" ]; then return 3; fi

  while IFS= read -r line; do
    if [[ "$line" =~ ^\#\#\ .* ]]; then
      echo "${line//## /}"
    else
      return 0
    fi
  done <<<"$decl_lines"
}

function task_names { ## list available tasks in this Xfile and children (if root)
  show_task_names_from "$THIS_XFILE_PATH"
  show_task_names_from_loaded_sources
  if this_xfile_is_root; then
    show_task_names_from_linked_children
  fi
}

show_task_names_from() { ## print task names list from $1 file, $2 – optional prefix
  if [ ! -f "$1" ]; then return 5; fi

  local func_decl_first_lines
  func_decl_first_lines=$(grep -E '^function [a-zA-Z0-9_:]+(\(\))? ({|\().*' "$1" || true)

  if [ -z "$func_decl_first_lines" ]; then return 0; fi

  local line
  while read -r line; do
    line=${line#'function '}
    line=${line%%\{*} # normal body
    line=${line%%\(*} # subshell body
    echo "$line"
  done <<<"$func_decl_first_lines"
}

show_tasks() { ## $1 – header override (may be empty), $2 – tasks prefix
  show_tasks_from "$THIS_XFILE_PATH" "$1" "$2"
  show_tasks_from_loaded_sources "$1" "$2"
  if this_xfile_is_root; then
    show_tasks_from_linked_children "$2"
  fi
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

  local marks_and_func_first_lines
  marks_and_func_first_lines=$(grep -E '(^function [a-zA-Z0-9_:]+(\(\))? ({|\().*)|(^# ----------).*' "$1" || true)

  if [ -z "$marks_and_func_first_lines" ]; then
    log_warn "No any visible tasks! You shall define some like 'function my_task() {' in your Xfile"
    return 0
  fi

  local line func_name func_description
  while IFS= read -r line; do
    if [[ "$line" == '# ----------'* ]]; then
      line="${line#'# ---------- '}"
      line="${line%' ----------'}"
      printf "\033[92m## %s\033[0m\n" "$line"
    else # function name() { ## description
      func_name=${line#*' '}
      func_name=${func_name%% *}
      func_name=${func_name%'()'}
      if [[ "$line" == *\#\#* ]]; then
        func_description=${line#*'##'}
        func_description=${func_description#' '}
      else
        func_description=''
      fi
      printf "  \033[93m%-48s\033[92m %s\033[0m\n" "$3$func_name" "$func_description"
    fi
  done <<<"$marks_and_func_first_lines"
  echo
}

function help { ## print full "How to use?" info for this Xfile
  show_tasks
  usage
}

function usage { ## print common usage instructions for Xfile
  log_note 'To run task call:' \
    "$THIS_XFILE_PATH <task> <args>" \
    "x <task> <args>" \
    '' \
    2>&1
  log_note "To setup alias 'x' and enable autocompletion call:" \
    "./Xfile install_xfile" \
    2>&1
}

# ---------- Dispatch ----------

function begin_xfile_task { ## Xfile task starting point, should be called after function declarations (Xfile last line)
  local task_name="${_SCRIPT_ARGS_ARR[0]}" child_idx

  if value_in_list "$task_name" "" help --help -h; then
    help 2>/dev/null
    return
  fi

  if task_declared "$task_name" 2>/dev/null; then
    if [ -n "$_X_TASK_STACK_STR" ]; then
      # result code logged outside, avoid trap overhead
      "${_SCRIPT_ARGS_ARR[@]}"
      return $?
    fi
    _log_move_to_task "$task_name"
    (( ++_X_TASK_STACK_LENGTH_IN_SUBSHELL ))
    trap '_task_exit_trap $? "$BASH_COMMAND"' EXIT
    "${_SCRIPT_ARGS_ARR[@]}"
    _log_move_from_task $?
  elif child_idx=$(try_find_child_with_task "$task_name"); then
    try_run_task_in_child "$child_idx" "$task_name"
    return $?
  else
    _log_x_task_is_undeclared "${_SCRIPT_ARGS_ARR[@]}"
    return 8
  fi
}

function task { ## Call declared function, use "$@" as _SCRIPT_ARGS_ARR inside
  local _SCRIPT_ARGS_ARR=("$@") task_name=$1 child_idx

  if task_declared "$task_name" 2>/dev/null; then
    if [ "$_X_TASK_STACK_BASH_SUBSHELL" != "$BASH_SUBSHELL" ]; then
      # task call inside new subshell shall log only subshell tasks stack part
      log_warn "Detected task call from subshell – $BASH_SUBSHELL." \
        "'task' called inside of '${FUNCNAME[1]}'"
      _X_TASK_STACK_LENGTH_IN_SUBSHELL=0
      _X_TASK_STACK_BASH_SUBSHELL=$BASH_SUBSHELL
      _log_move_to_task "$task_name" '(subshell)'
    else
      _log_move_to_task "$task_name"
    fi
    (( ++_X_TASK_STACK_LENGTH_IN_SUBSHELL ))
    trap '_task_exit_trap $? "$BASH_COMMAND"' EXIT
    "$@"
    (( _X_TASK_STACK_LENGTH_IN_SUBSHELL-- ))
    _log_move_from_task $?
  elif child_idx=$(try_find_child_with_task "$task_name"); then
    try_run_task_in_child "$child_idx" "$task_name"
    return $?
  else
    _log_x_task_is_undeclared "${_SCRIPT_ARGS_ARR[@]}"
    return 8
  fi
}

_task_exit_trap() {
  if [ "$1" = 0 ]; then
    return 0
  fi

  local count=$_X_TASK_STACK_LENGTH_IN_SUBSHELL
  _log_move_from_task "$1" "$2"
  (( count-- ))

  while (( count > 0 )); do
    _log_move_from_task "$1"
    (( count-- ))
  done

  return 0
}

function process { ## run task (as new bash process) passing call args
  local _SCRIPT_ARGS_ARR=("$@") task_name=$1 child_idx

  if task_declared "$task_name" 2>/dev/null; then
    _log_move_to_task "$task_name" '(process)'
    local _X_FAILED_COMMAND
    _cache_failed_command_for_logging "$@"
    local code=0
    # will call: same Xfile as _new process_ -> begin_xfile_task -> func call -> ...
    _X_CALLED_FROM_XFILE_OR_CHILD=true \
      "$THIS_XFILE_PATH" "$@" || { code=$?; }
    _log_move_from_task "$code" "$_X_FAILED_COMMAND"
    return "$code"
  elif child_idx=$(try_find_child_with_task "$task_name"); then
    try_run_task_in_child "$child_idx" "$task_name"
    return $?
  else
    _log_x_task_is_undeclared "${_SCRIPT_ARGS_ARR[@]}"
    return 8
  fi
}

_task_in_child() { ## ## Private API. Runs task in child, task should checked to be declared beforehand
  local THIS_XFILE_PATH=$1
  _log_move_to_task "$2"
  local _X_FAILED_COMMAND
  _cache_failed_command_for_logging "${@:2}"
  local code=0
  _X_CALLED_FROM_XFILE_OR_CHILD=true \
    "$@" || { code=$?; }
  _log_move_from_task "$code" "$_X_FAILED_COMMAND"
  return "$code"
}

_cache_failed_command_for_logging() { ## fill _X_FAILED_COMMAND variable with given args
  _X_FAILED_COMMAND=$1
  shift

  local arg
  for arg in "$@"; do
    _X_FAILED_COMMAND="$_X_FAILED_COMMAND '$arg'"
  done
}

_call_child_impl_task() { ## Private API, runs child task which expected to be from impl.sh source
  _X_CALLED_FROM_XFILE_OR_CHILD=true THIS_XFILE_PATH="$1" "$@"
}

function task_declared { ## returns error code if $1 is not a declared as function in this Xfile or sourced files
  declare -F "$1" >/dev/null
}

_log_x_task_is_undeclared() {
  log_error "🤔 No task named: '$1' in this Xfile or linked children!" \
    'Maybe misspelled?' \
    'Try: x help' \
    'Call args:' \
    "$@"
}

_log_move_to_task() { ## Private API. Handles CALL STACK
  local new_part=$1

  if [ -n "$2" ]; then
    new_part="$2 $new_part"
  fi
  new_part="[${THIS_XFILE_PATH##*/}] $new_part"

  if [ -z "$_X_TASK_STACK_STR" ]; then
    printf "🚀 $(tput setaf 4)do: %s$(tput sgr0)\n" "$new_part" 1>&2
    _X_TASK_STACK_STR=$new_part
  else
    printf "🌚 $(tput setaf 4)in: %s > %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$new_part" 1>&2
    _X_TASK_STACK_STR="$_X_TASK_STACK_STR > $new_part"
  fi

  export _X_TASK_STACK_STR
}

_log_move_from_task() { ## Private API. Handles CALL STACK
  local code=$1 failed_command=$2

  if [[ $_X_TASK_STACK_STR == *' > '* ]]; then
    local just_finished_task
    just_finished_task=${_X_TASK_STACK_STR##*' > '}
    _X_TASK_STACK_STR=${_X_TASK_STACK_STR%' > '*}
    if [ "$code" != 0 ]; then
      printf "💥 $(tput setaf 1)at: %s < %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$just_finished_task" 1>&2
      if [ -n "$failed_command" ]; then
        log "💥 $code from command:" \
          "💥 $failed_command"
      fi
    else
      printf "🌝 $(tput setaf 6)out: %s < %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$just_finished_task" 1>&2
    fi
  else
    if [ "$code" != 0 ]; then
      printf "💥 $(tput setaf 1)failed: %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" 1>&2
      if [ -n "$failed_command" ]; then
        log "💥 $code from command:" \
          "💥 $failed_command"
      fi
    else
      printf "👍 $(tput setaf 6)done: %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" 1>&2
    fi
    _X_TASK_STACK_STR=''
  fi
}

this_xfile_is_root() { ## returns error code if path test fails
  test "$THIS_XFILE_PATH" = "$ROOT_XFILE_PATH"
}

# ---------- Sources ----------

function load_source { ## source $1, capture path for help
  assert_abs_path "$1"
  if [ ! -f "$1" ]; then
    log_error "Trying to load the source while it is not a file:" "$1"
    return 14
  fi
  _LOADED_SOURCE_FILES+=("$1")
  source "$1"
}

function load_optional_source { ## source $1 if file exist, capture path for help
  assert_abs_path "$1"
  if [ ! -f "$1" ]; then
    return
  fi
  _LOADED_SOURCE_FILES+=("$1")
  source "$1"
}

impl:task_args_in_loaded_sources() { ## list $1 task args from first match in loaded source files
  local source_path

  if [ "${#_LOADED_SOURCE_FILES[@]}" -eq 0 ]; then return 7; fi

  for source_path in "${_LOADED_SOURCE_FILES[@]}"; do
    impl:task_args "$1" "$source_path" && return || true
  done

  return 9
}

show_task_names_from_loaded_sources() {
  local source_path

  for source_path in "${_LOADED_SOURCE_FILES[@]}"; do
    show_task_names_from "$source_path"
  done
}

show_tasks_from_loaded_sources() {
  local source_path

  for source_path in "${_LOADED_SOURCE_FILES[@]}"; do
    show_tasks_from "$source_path" "$1" "$2"
  done
}

# ---------- Children ----------

function link_child_xfile { ## make child Xfile tasks executable from this Xfile. $1 - path to child, $2 - optional tasks prefix
  assert_abs_path "$1"
  if [ ! -x "$1" ]; then
    log_error "Trying to link the child while it is not an executable:" "$1"
    return 17
  fi
  _LINKED_XFILE_CHILDREN+=("$1;$2")
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

    if _call_child_impl_task "$child_path" task_declared "$child_task_name" 2>/dev/null; then
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

  _task_in_child "$child_path" "${2##"$child_prefix"}" "${_SCRIPT_ARGS_ARR[@]:1}"
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

    _call_child_impl_task "$child_path" task_args "$task_name" && return || true
  done

  return 9
}

show_task_names_from_linked_children() {
  local child child_info child_path child_prefix

  for child in "${_LINKED_XFILE_CHILDREN[@]}"; do
    IFS=';' read -r -a child_info <<<"$child"

    child_path="${child_info[0]}"
    child_prefix="${child_info[1]}"

    _call_child_impl_task "$child_path" task_names | sed "s/^/$child_prefix/"
  done
}

show_tasks_from_linked_children() { ## $1 – this Xfile prefix in parent Xfile
  local child child_info child_path child_prefix

  for child in "${_LINKED_XFILE_CHILDREN[@]}"; do
    IFS=';' read -r -a child_info <<<"$child"

    child_path="${child_info[0]}"
    child_prefix="${child_info[1]}"

    _call_child_impl_task "$child_path" show_tasks '' "$1$child_prefix"
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

  local caller_dir=$PWD
  cd "$1"
  export XFILE_REF=${2:-main}

  process try_load_xfile_from_release_archive || process try_load_xfile_from_ref || {
    log_error "Failed to install Xfile $XFILE_REF to:" "$1"
    return 9
  }

  log_success "Installed Xfile $XFILE_REF to:" "$1"
  cd "$caller_dir"
}

try_load_xfile_from_release_archive() {
  log_next "Will try to load and unpack Xfile_source.zip from Release $XFILE_REF"

  curl -fsSL "https://github.com/amidaleet/Xfile/releases/download/$XFILE_REF/Xfile_source.zip" -o Xfile_source.zip
  rm -rf ./Xfile_source
  unzip ./Xfile_source.zip
  if [ ! -x ./Xfile ]; then
    cp -f ./Xfile_source/template.sh ./Xfile
  fi
  rm -f ./Xfile_source.zip
}

try_load_xfile_from_ref() {
  log_next "Will try load and use ./Xfile_source/setup.sh from git ref $XFILE_REF"

  curl -fsSL "https://raw.githubusercontent.com/amidaleet/Xfile/$XFILE_REF/Xfile_source/setup.sh" -o setup.sh
  log_next "Will execute next script:" '```sh'
  cat setup.sh
  log '```'

  chmod +x setup.sh
  ./setup.sh
  rm -f setup.sh
}

function xfile_init_copy() { ## copy sources and Xfile sample to $1 dir
  if [ -z "$1" ]; then return 3; fi

  local caller_dir=$PWD
  cd "$1"
  rm -rf Xfile_source
  mkdir -p Xfile_source

  cp -rf "$GIT_ROOT/Xfile_source" "$1"
  if [ ! -f "$1/Xfile" ]; then
    cp "$GIT_ROOT/Xfile_source/template.sh" "$1/Xfile"
  fi

  cd "$caller_dir"
}

{ ## Set important Xfile implementation ENV. Performed at Xfile start while impl is sourced. Should not be called manually
  _LINKED_XFILE_CHILDREN=()
  _LOADED_SOURCE_FILES=()
  _X_TASK_STACK_BASH_SUBSHELL=$BASH_SUBSHELL
  _X_TASK_STACK_LENGTH_IN_SUBSHELL=0

  export ROOT_XFILE_PATH=${ROOT_XFILE_PATH:-"$GIT_ROOT/Xfile"} # expected absolute path

  if [ -n "$_X_CALLED_FROM_XFILE_OR_CHILD" ]; then
    # Spawned from Xfile or child with 'task' or '_call_child_impl_task', they states this flag
    # Unset to allow task sub processes call root Xfile by $ROOT_XFILE_PATH without this flag
    unset _X_CALLED_FROM_XFILE_OR_CHILD
    if [ -z "$THIS_XFILE_PATH" ]; then
      log_error "THIS_XFILE_PATH found empty, but expected to be filled from parent Xfile side!"
      return 9
    fi
  else
    # Either first launch from ./Xfile or called from transitive sub process
    # restart possibly "dirty" task call stack
    _X_TASK_STACK_STR=''
    export THIS_XFILE_PATH=$ROOT_XFILE_PATH
  fi
}
