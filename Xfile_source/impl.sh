#!/usr/bin/env bash

source "$GIT_ROOT/Xfile_source/xlib.sh"

# ---------- Xfile core ----------

function install_xfile { ## Install autocompletion
  impl:install_xfile "$@"
}

function impl:install_xfile {
  cp -f Xfile_source/completion.sh "$HOME/.xfile_completion"

  if [[ -n $(grep "source \"\$HOME/.xfile_completion\"" "$HOME/.zshrc" || true) ]]; then
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

function task_args { ## List task args
  impl:task_args "$@" || true
}

function impl:task_args {
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

function task_names { ## List available task names
  show_task_names_from "$0"
}

function show_task_names_from { ## Print task names list from file
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

function show_tasks_from { ## Print task descriptions list from file
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
    log_warn "No any visible tasks! You may add some 'function task_name {' to your file"
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

function help { ## Print "How to use?" info
  show_tasks_from "$0" "Xfile tasks:"
  log_blank_line
  usage
}

function usage { ## Print usage instructions
  echo "$(tput setaf 4)# To run task:$(tput sgr0)"
  echo "$0 <task> <args>"
  echo "x <task> <args>"
  echo
  echo "$(tput setaf 4)# Note:$(tput sgr0)"
  echo "👉 To setup alias 'x' and enable auto-completion in zsh call:"
  echo "./Xfile install_xfile"
}

function run_task { ## Execute task as shell command
  local task_name=$1

  if [ -z "$task_name" ] || [ "$task_name" = "help" ] || [ "$task_name" = "--help" ]; then
    help
    exit 0
  fi

  is_known_task=false
  local task
  for task in $(compgen -A function); do
    if [ "$task_name" = "$task" ]; then
      is_known_task=true
      break
    fi
  done

  if [ "$is_known_task" = false ]; then
    if [ "$IS_CI" = true ]; then
      log_error "🤔 No task named '$task_name'!"
      log 'Call args:' "$@"
      echo
      exit 3
    fi
    log_warn "🤔 No task named: $task_name"
    log 'Maybe misspelled?'
    log 'Try: x help'
    log 'Call args:' "$@"
    exit 4
  fi

  "$@"
}

function child_task { ## Execute child Xfile task
  if [ -n "$2" ]; then
    "$1" "$2" "${_INPUT_ARR[@]:1}"
  else
    "$1" "${_INPUT_ARR[@]:1}"
  fi
}

function task {
  log_move_to_task "$1"
  $0 "$@"
  log_move_from_task "$1"
}

function task_in_context { ## Execute task as shell command passing all arguments from parent task
  task "$@" "${_INPUT_ARR[@]:1}"
}

function task_out { ## Clean output, no Xfile logs
  $0 "$@"
}

function log_move_to_task {
  printf "🏃‍♀️‍➡️ $(tput setaf 6) in: %s > %s$(tput sgr0)\n" "$_X_TASK_STACK_STR" "$1"
}

function log_move_from_task {
  printf "🏃‍♂️ $(tput setaf 6) out: %s $(tput sgr0)< %s\n" "$_X_TASK_STACK_STR" "$1"
}

function push_task_stack {
  if [ -z "$_X_TASK_STACK_STR" ]; then
    _X_TASK_STACK_STR=$1
  else
    _X_TASK_STACK_STR="$_X_TASK_STACK_STR > $1"
  fi

  export _X_TASK_STACK_STR
}

# ---------- Xfile setup ----------

## --path
function impl:xfile_init_load { ## Loads sources and Xfile sample to provided path
  read_opt --path target_path
  assert_defined target_path

  cd "$target_path"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/amidaleet/Xfile/HEAD/Xfile_source/setup.sh)"
}

## --path
function impl:xfile_init_copy { ## Copies sources and Xfile sample to provided path
  read_opt --path target_path
  assert_defined target_path

  cd "$target_path"
  rm -rf Xfile_source
  mkdir -p Xfile_source
  cd "$GIT_ROOT"

  cp "$GIT_ROOT/Xfile_source"/* "$target_path/Xfile_source"

  impl:write_xfile_template "$target_path/Xfile"
}

function impl:write_xfile_template {
  cat <<'TEXT' > "$1"
#!/usr/bin/env bash

set -eo pipefail

export GIT_ROOT="$(realpath .)"

source "$GIT_ROOT/Xfile_source/xlib.sh"

run_task "$@"
TEXT
  chmod +x "$1"
}

push_task_stack "$1"
