#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

link_child_xfile "$GIT_ROOT/Xfile_source/tests/mock_root.sh"

function test_child_cannot_call_child_that_not_linked_directly {
  task child_stack_1 'from test_child_cannot_call_child_that_not_linked_directly'
}

function test_root_task_from_child {
  task root_stack_2 'from test_root_task_from_child'
}

begin_xfile_task
