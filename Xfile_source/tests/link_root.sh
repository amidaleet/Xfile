#!/usr/bin/env bash

set -eo pipefail

export ROOT_XFILE_PATH="$GIT_ROOT/Xfile_source/tests/link_root.sh"

source "$GIT_ROOT/Xfile_source/impl.sh"

link_child_xfile "$GIT_ROOT/Xfile_source/tests/child_zero.sh"
link_child_xfile "$GIT_ROOT/Xfile_source/tests/child_one.sh" one:
link_child_xfile "$GIT_ROOT/Xfile_source/tests/child_two.sh" two:

function link_root_task() { ## link_root task
  echo 'link_root_task in link_root'
}

## --argument --dir
function subshell_task() ( ## link_root – subshell_task
  :
)

## --force -f
subshell_task_two() ( ## link_root – subshell_task_two
  :
)

begin_xfile_task
