#!/usr/bin/env bash

source "$GIT_ROOT/Xfile_source/xlib.sh"

# ---------- Xfile core ----------

function task_args { ## list $1 task args from $2 file (default: $0 – this Xfile)
  impl:task_args "$@" || true
}

function impl:task_args() { ## list $1 task args from $2 file (default: $0 – this Xfile)
  local file=${2:-$0}
  local funcDefStr=()
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
}

function show_task_names_from { ## print task names list from $1 file
  if [ ! -f "$1" ]; then
    return
  fi

  local func_lines
  func_lines=$(grep -E '^function [a-zA-Z0-9_:]+(\(\))? {.*' "$1" || true)
  if [ -z "$func_lines" ]; then
    return
  fi

  echo "$func_lines" |
    sed -e 's/function //' | # drop prefix
    awk 'BEGIN {FS = " {"}; {
      gsub(/\(\)/, "", $1);
      gsub(/##/, "", $2);
      printf "%s\n", $1
    }
    '
}

function show_tasks_from { ## print task descriptions list from $1 file, $2 – optional output header
  if [ ! -f "$1" ]; then
    log_warn "Found missing file while reading tasks: $1"
    return
  fi

  if [ -n "$2" ]; then
    echo "$(tput setaf 4)# $2$(tput sgr0)"
  else
    echo "$(tput setaf 4)# Tasks in $1:$(tput sgr0)"
  fi
  local picked_lines
  picked_lines=$(grep -E '(^function [a-zA-Z0-9_:]+(\(\))? {.*)|(^# ----------).*' "$1" || true)
  if [ -z "$picked_lines" ]; then
    log_warn "No any visible tasks! You shall define some like 'function my_task() {' in your Xfile"
    return
  fi

  echo "$picked_lines" |
    sed -e 's/function //' | # drop prefix
    awk 'BEGIN {FS = " {"}; {
      if ($1 ~ /^# ----------/) {
        gsub(/# ---------- /, "", $1);
        gsub(/ ----------/, "", $1);
        printf "\n"
        printf "\033[92m- %s\033[0m\n", $1
      } else {
        gsub(/\(\)/, "", $1);
        gsub(/##/, "", $2);
        printf "  \033[93m%-46s\033[92m %s\033[0m\n", $1, $2
      }
    }
    '
}

function help { ## print full "How to use?" info for this Xfile
  show_tasks_from "$0" "Xfile tasks:"
  log
  usage
}

function usage { ## print common usage instructions for Xfile
  echo "$(tput setaf 4)# To run task:$(tput sgr0)"
  echo "$0 <task> <args>"
  echo "x <task> <args>"
  echo
  echo "$(tput setaf 4)# Note:$(tput sgr0)"
  echo "👉 To setup alias 'x' and enable auto-completion in zsh call:"
  echo "./Xfile install_xfile"
}

function begin_xfile_task { ## execute task $1 as shell command passing following call args
  local task_name="${_SCRIPT_ARGS_ARR[0]}"

  if value_in_list "$task_name" "" help --help; then
    help
    return
  fi

  if ! declare -F "$task_name" >/dev/null; then
    log_warn "🤔 No task named: '$task_name'!"
    log 'Maybe misspelled?'
    log 'Try: x help'
    log 'Call args:' "${_SCRIPT_ARGS_ARR[@]}"
    return 4
  fi

  "${_SCRIPT_ARGS_ARR[@]}"
}

function task { ## run task (as bash process) passing call args
  log_move_to_task "$1"
  $0 "$@"
  log_move_from_task "$1"
}

function task_in_context { ## run task (as bash process) passing script args after call args
  task "$@" "${_SCRIPT_ARGS_ARR[@]:1}"
}

function child_task { ## run task in $1 "child" Xfile forwarding script args, $2 – optional task name (may be in script args)
  if [ -n "$2" ]; then
    "$1" "$2" "${_SCRIPT_ARGS_ARR[@]:1}"
  else
    "$1" "${_SCRIPT_ARGS_ARR[@]:1}"
  fi
}

log_move_to_task() {
  printf "🏃‍♀️‍➡️ $(tput setaf 6) in: %s > %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$1" 1>&2
}

log_move_from_task() {
  printf "🏃‍♂️ $(tput setaf 6) out: %s $(tput sgr0)< %s\n" "$_X_TASK_STACK_STR" "$1" 1>&2
}

push_task_stack() {
  if [ -z "$_X_TASK_STACK_STR" ]; then
    _X_TASK_STACK_STR=$1
  else
    _X_TASK_STACK_STR="$_X_TASK_STACK_STR > $1"
  fi

  export _X_TASK_STACK_STR
}

# ---------- Xfile setup ----------

function install_xfile { ## install autocompletion to zsh
  impl:install_xfile "$@"
}

impl:install_xfile() {
  cp -f Xfile_source/completion.sh "$HOME/.xfile_completion"

  if grep "source \"\$HOME/.xfile_completion\"" "$HOME/.zshrc" || grep "source \"\$HOME/.xfile_completion\"" "$HOME/.zprofile"; then
    log_success "Source for xfile_completion is already set in ~/.zshrc"
  else
    log "Adding completion script as source..."

    echo >>"$HOME/.zshrc"
    echo "source \"\$HOME/.xfile_completion\"" >>"$HOME/.zshrc"

    log_info "Xfile auto-completion has been added to your ~/.zshrc file"
    log_warn "Restart Terminal session to take effect"
    log "Than you'll be able to auto-complete Xfile args with tab button'"
  fi
}

function xfile_init_load() { ## load sources and Xfile sample to $1 dir from $2 git ref
  if [ -z "$1" ]; then return 3; fi

  cd "$1"
  export XFILE_REF=${2:-main}
  bash <<<"$(curl -fsS https://raw.githubusercontent.com/amidaleet/Xfile/$XFILE_REF/Xfile_source/setup.sh)"
}

function xfile_init_copy() { ## copy sources and Xfile sample to $1 dir
  if [ -z "$1" ]; then return 3; fi

  cd "$1"
  rm -rf Xfile_source
  mkdir -p Xfile_source
  cd "$GIT_ROOT"

  cp "$GIT_ROOT/Xfile_source"/* "$1/Xfile_source"
  if [ ! -f "$1/Xfile" ]; then
    cat <<'HEREDOC' >"$1/Xfile"
#!/usr/bin/env bash

set -eo pipefail

export GIT_ROOT="${GIT_ROOT:-"$(realpath .)"}"

source "$GIT_ROOT/Xfile_source/impl.sh"

begin_xfile_task
HEREDOC
    chmod +x "$1/Xfile"
  fi
}

push_task_stack "$1"
