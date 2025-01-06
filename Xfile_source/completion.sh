#!/usr/bin/env zsh

alias x=./Xfile

if [[ $(type complete) != "complete not found" ]]; then
  function xfile_completions() {
    if [ ${#COMP_WORDS[@]} -gt 2 ]; then
      COMPREPLY=($(./Xfile task_args ${COMP_WORDS[1]}))
      return
    fi

    local task_names=$(grep -E '^function [a-zA-Z0-9_:]+ {.*' Xfile |
      sed -e 's/function //' | # drop prefix
      awk 'BEGIN {FS = " {"}; {
        gsub(/##/, "", $2);
        printf "%s\n", $1
      }
      ')

    COMPREPLY="$task_names"
  }

  complete -F xfile_completions Xfile
else
  echo "❗️ $(tput setaf 3)[WARNING] Cannot activate Xfile auto-completion $(tput sgr0)"
  echo "Missing complete 'command' in active shell ($SHELL)"
  echo "Setup omz, to enable it in zsh"
  echo "See: https://ohmyz.sh"
fi
