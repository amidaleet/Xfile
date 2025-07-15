#!/usr/bin/env zsh

alias x=./Xfile

if [[ $(type complete) != "complete not found" ]]; then
  function xfile_completions() {
    if [ ${#COMP_WORDS[@]} -gt 2 ]; then
      COMPREPLY=($(./Xfile task_args ${COMP_WORDS[1]}))
      return
    fi
    local names
    names=$(./Xfile task_names)

    if [ "$?" != 0 ]; then
      local func_lines
      func_lines=$(grep -E '^function [a-zA-Z0-9_:]+(\(\))? {.*' Xfile || true)
      if [ -z "$func_lines" ]; then
        COMPREPLY=''
        return
      fi

      names=$(echo "$func_lines" |
        sed -e 's/function //' | # drop prefix
        awk 'BEGIN {FS = " {"}; {
          gsub(/\(\)/, "", $1);
          gsub(/##/, "", $2);
          printf "%s\n", $1
        }
        ')
    fi

    COMPREPLY="$names"
  }

  complete -F xfile_completions Xfile
else
  echo "❗️ $(tput setaf 3)[WARNING] Cannot activate Xfile auto-completion $(tput sgr0)"
  echo "Missing complete 'command' in active shell ($SHELL)"
  echo "Setup omz, to enable it in zsh"
  echo "See: https://ohmyz.sh"
fi
