#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

function test_tasks_chain_in_child {
  task child_stack_1 'from test_tasks_chain_in_child'
}

function test_tasks_chain_in_child_fails {
  MOCKED_END_CODE=7 task child_stack_1 'from test_tasks_chain_in_child_fails'
}

function test_root_task_from_child_without_link_fails {
  task root_stack_2 'from test_root_task_from_child_without_link_fails'
}

function child_stack_1 {
  log "child_stack_1 start" "$@"

  task child_stack_2 'from child_stack_1'

  log "child_stack_1 end without err"
}

child_stack_2() {
  log "child_stack_2 start" "$@"

  if [ -n "$MOCKED_END_CODE" ]; then
    return_code "$MOCKED_END_CODE"
  fi

  log "child_stack_2 end without err"
}

return_code() {
  return "$1"
}

begin_xfile_task
