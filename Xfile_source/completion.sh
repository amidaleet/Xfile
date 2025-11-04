# shellcheck shell=bash
function bind_xfile_completion() {
  if [[ -n "$ZSH_VERSION" ]]; then
    if [[ $(type complete) == "complete not found" ]]; then
      ## using pure zsh built-in
      function _zsh_xfile_completion() {
        if (( ${#words} > 2 )); then
          # 2 or more args: suggest task_args for the given task name
          local task_args
          task_args=$(./Xfile task_args "${words[2]}" 2>/dev/null)
          if [[ $? -eq 0 && -n "$task_args" ]]; then
            # shellcheck disable=SC2086 # zsh: split words intentionally
            compadd -Q -- ${=task_args}
          fi
        else
          # 1 arg: suggest task_names
          local task_names
          task_names=$(./Xfile task_names 2>/dev/null)
          if [[ $? -eq 0 && -n "$task_names" ]]; then
            # shellcheck disable=SC2086 # zsh: split words intentionally
            compadd -Q -- ${=task_names}
          fi
        fi
      }

      autoload -Uz compinit
      compinit

      compdef _zsh_xfile_completion Xfile
    else
      ## using omz complete function
      function _omz_xfile_completion() {
        if [[ ${#COMP_WORDS[@]} -gt 2 ]]; then
          # 2 or more args: suggest task_args for the given task name
          local task_args
          task_args=$(./Xfile task_args "${COMP_WORDS[1]}" 2>/dev/null)
          if [[ $? -eq 0 && -n "$task_args" ]]; then
            # shellcheck disable=SC2206 # bash/zsh completion: split words into array intentionally
            COMPREPLY=( $task_args )
          else
            COMPREPLY=()
          fi
        else
          # 1 arg: suggest task_names
          local task_names
          task_names=$(./Xfile task_names 2>/dev/null)
          if [[ $? -eq 0 && -n "$task_names" ]]; then
            # shellcheck disable=SC2206 # bash/zsh completion: split words into array intentionally
            COMPREPLY=( $task_names )
          else
            COMPREPLY=()
          fi
        fi
      }

      complete -F _omz_xfile_completion Xfile
    fi

  elif [[ -n "$BASH_VERSION" ]]; then
    ## using bash built-in
    function _bash_xfile_completion() {
      if [ ${#COMP_WORDS[@]} -gt 2 ]; then
        # 2 or more args: suggest task_args for the given task name
        local task_args task_name w next

        task_name="${COMP_WORDS[1]}"
        for w in "${COMP_WORDS[@]:2}"; do
          # bash splits task names with ":", so we must rebuild task_name
          if [ "$w" = ":" ]; then
            task_name="$task_name$w"
            next='y'
          elif [ "$next" = "y" ]; then
            task_name="$task_name$w"
            next=''
          else
            break
          fi
        done

        task_args=$(./Xfile task_args "$task_name" 2>/dev/null)
        if [[ $? -eq 0 && -n "$task_args" ]]; then
          # shellcheck disable=SC2207 # bash completion expects array from command substitution
          COMPREPLY=( $(compgen -W "$task_args" -- "${COMP_WORDS[$COMP_CWORD]}") )
        else
          COMPREPLY=()
        fi
      else
        # 1 arg: suggest task_names
        local task_names
        task_names=$(./Xfile task_names 2>/dev/null)
        if [[ $? -eq 0 && -n "$task_names" ]]; then
          # shellcheck disable=SC2207 # bash completion expects array from command substitution
          COMPREPLY=( $(compgen -W "$task_names" -- "${COMP_WORDS[$COMP_CWORD]}") )
        else
          COMPREPLY=()
        fi
      fi
    }

    bind 'set show-all-if-ambiguous on'
    bind 'TAB:menu-complete'
    bind '"\e[Z":menu-complete-backward'

    complete -F _bash_xfile_completion Xfile
    complete -F _bash_xfile_completion x

  else
    ## Unsupported shells
    {
      echo "❗️ [WARNING] Failed to activate Xfile autocompletion!"
      echo "Detected unsupported shell, designed to work with zsh, oh-my-zsh and bash"
    } >&2
  fi
}

alias x=./Xfile
bind_xfile_completion; unset bind_xfile_completion
