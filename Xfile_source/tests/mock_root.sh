#!/usr/bin/env bash

set -eo pipefail

export ROOT_XFILE_PATH="$GIT_ROOT/Xfile_source/tests/mock_root.sh"

source "$GIT_ROOT/Xfile_source/impl.sh"

load_source "$GIT_ROOT/Xfile_source/tests/mock_loaded_source.sh"

link_child_xfile "$GIT_ROOT/Xfile_source/tests/mock_child.sh"
link_child_xfile "$GIT_ROOT/Xfile_source/tests/mock_child_two.sh"

function test_forward_out_and_err_to_dir {
  forward_out_and_err_to_dir "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/main"

  # shellcheck disable=SC2329
  function bar {
    log 'in bar'
    task foo
    puts 'out in bar'
    log 'in bar after foo'
  }

  # shellcheck disable=SC2329
  function foo {
    forward_out_and_err_to_dir "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/foo"

    log 'in foo'
    puts 'out in foo'
  }

  log 'started test_forward_out_and_err_to_dir'

  log 'in test_forward_out_and_err_to_dir'

  puts 'out 1 in test_forward_out_and_err_to_dir'
  task bar
  puts 'out 2 in test_forward_out_and_err_to_dir'

  log 'in test_forward_out_and_err_to_dir after bar'

  unset bar foo
  log 'ended test_forward_out_and_err_to_dir'
}

function test_run_with_status_marker {
  # shellcheck disable=SC2329
  function bar {
    log 'in bar'
    run_with_status_marker "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/foo" \
      task foo
    puts 'out in bar'
    log 'in bar after foo'
  }

  # shellcheck disable=SC2329
  function foo {
    log 'in foo'
    puts 'out in foo'
  }

  log 'started test_forward_out_and_err_to_dir'

  log 'in test_forward_out_and_err_to_dir'

  puts 'out 1 in test_forward_out_and_err_to_dir'
  run_with_status_marker "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/bar" \
    task bar
  puts 'out 2 in test_forward_out_and_err_to_dir'

  log 'in test_forward_out_and_err_to_dir after bar'

  unset bar foo
  log 'ended test_forward_out_and_err_to_dir'
}

function test_tasks_chain_from_root_to_child {
  task child_stack_1 'from test_tasks_chain_from_root_to_child'
}

function test_tasks_chain_from_root_to_child_fails_in_child {
  MOCKED_END_CODE=7 task child_stack_1 'from test_tasks_chain_from_root_to_child_fails_in_child'
}

function test_process_in_logic_expression {
  log "started test_process_in_logic_expression"

  if MOCKED_END_CODE=77 task root_stack_2; then
    log "task root_stack_2 succeeded as expected. Because errexit is implicitly disabled (sadly)"
  else
    log_error "task root_stack_2 has finished without error, which is strange..."
  fi

  if MOCKED_END_CODE=89 process root_stack_2; then
    log_error "process root_stack_2 finished without error, which is not expected!"
  else
    log "process root_stack_2 failed as expected, new process does not inherit disabled errexit"
  fi

  log "ended test_process_in_logic_expression without err"
}

function test_tasks_chain_in_root {
  task root_stack_1 'from test_tasks_chain_in_root'
}

function test_tasks_chain_in_root_fails {
  MOCKED_END_CODE=7 task root_stack_1 'from test_tasks_chain_in_root_fails'
}

root_stack_1() {
  log "root_stack_1 start" "$@"

  task root_stack_2 'from root_stack_1'

  log "root_stack_1 end without err"
}

root_stack_2() {
  log "root_stack_2 start" "$@"

  if [ -n "$MOCKED_END_CODE" ]; then
    return_code "$MOCKED_END_CODE"
  fi

  log "root_stack_2 end without err"
}

return_code() {
  return "$1"
}

function test_failure_after_ignored_process_failure_logging() {
  # shellcheck disable=SC2310
  process return_code 88 || true

  log 'la la la'

  false
}

begin_xfile_task
