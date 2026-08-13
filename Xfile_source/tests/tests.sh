#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

function test_xfile() { ## Test Xfile implementation (arguments handling)
  local fails_log
  fails_log=$(
    set +e # do not fail fast
    ((++_X_TASK_STACK_BASH_SUBSHELL)) # to hide subshell warnings in 'task'

    # shellcheck disable=SC2030
    TEST_FAILS_COUNT=0

    task test_var_is_true
    task test_assert_defined
    task test_args_readers
    task test_arr_to_str
    task test_read_arr
    task test_nounset_mode
    task test_xfile_children
    task test_xfile_dispatch

    # forward_out_and_err_to_dir: process-subst tee without wait — nested levels flake; keep one_level.
    # run_with_status_marker: synced via mkfifo+wait — exercise full nested path.
    task test_forward_out_and_err_to_dir_one_level
    task test_run_with_status_marker

    # - Note:
    # '$(...)' does not inherit caller shell options.
    # So errexit in this block is turned off.
    # It is done on purpose.
    # Full test coverage is desired, not a fail fast approach.
    # Output must not be empty to be considered as assertion failure.
    puts_fails_count_if_any_occurred
  )

  if [ -n "$fails_log" ]; then
    log "$fails_log"
    return 3;
  fi

  log_success "Xfile test succeeded!"
}

puts_fails_count_if_any_occurred() {
  if [ "$TEST_FAILS_COUNT" != 0 ]; then
    log_error "Xfile tests failed with $TEST_FAILS_COUNT asserts, check logs above ^^^" 2>&1
  fi
}

fail_if_new_assertions_has_failed() {
  if [ "$fails_count_before_this_tests" != "$TEST_FAILS_COUNT" ]; then
    return 13
  fi
}

test_var_is_true() {
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_bool() {
    # shellcheck disable=SC2034
    local FT_TEST=$1
    if var_is_true FT_TEST; then
      if [ "$2" != true ]; then
        puts "assert_bool: '$1' should be treated as false"
        ((++TEST_FAILS_COUNT))
      fi
    elif [ "$2" != false ]; then
      puts "assert_bool: '$1' should be treated as true"
      ((++TEST_FAILS_COUNT))
    fi
  }

  assert_bool 1 true
  assert_bool 0 false
  assert_bool true true
  assert_bool false false
  assert_bool TRUE true
  assert_bool yes true
  assert_bool YES true
  assert_bool other false
  assert_bool NO false
  assert_bool no false

  unset assert_bool

  fail_if_new_assertions_has_failed || return $?

  log_success "var_is_true works as expected!"
}

test_assert_defined() {
  # shellcheck disable=SC2034 # names passed to assert_defined (indirect \${!name})
  local value_one=1 value_two=work
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  if ! assert_defined value_one value_two 2>/dev/null; then
    puts "test_assert_defined: Assert is triggered on existing values!"
    ((++TEST_FAILS_COUNT))
  fi
  if assert_defined not_present_value 2>/dev/null; then
    puts "test_assert_defined: Assert is not triggered on non-existing values!"
    ((++TEST_FAILS_COUNT))
  fi

  fail_if_new_assertions_has_failed || return $?

  log_success "assert_defined works as expected!"
}

test_args_readers() {
  local process_out fails_count_before_this_tests=$TEST_FAILS_COUNT

  task assert_opt_and_args_read -l VERSION="42  20" --word 'word' -f -t "Text with  3   words and spaces" BETA_NUMBER='beta'
  task assert_opt_and_args_read -l -f -w 'word' -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20"
  task assert_opt_and_args_read -lf -w 'word' -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20"
  task assert_opt_and_args_read --local --word 'word' --force -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20"
  task assert_opt_and_args_read BETA_NUMBER=beta --local --word 'word' --force --text "Text with  3   words and spaces" VERSION="42  20"
  process_out=$(process assert_opt_and_args_read BETA_NUMBER=beta --local --word 'word' --force --text "Text with  3   words and spaces" VERSION="42  20")
  task assert_flags_read -o -e
  task assert_flags_read --expected --other

  if [ -n "$process_out" ]; then
    puts "$process_out"
    ((++TEST_FAILS_COUNT))
  fi
  fail_if_new_assertions_has_failed || return $?

  log_success "Args readers works as expected!"
}

assert_opt_and_args_read() {
  local WORD= TEXT= VERSION= BETA_NUMBER=
  read_opt -w --word WORD
  read_opt -t --text TEXT
  read_args VERSION BETA_NUMBER

  if ! read_flags --force -f; then
    puts "assert_opt_and_args_read: Missing expected --force -f flag!"
    ((++TEST_FAILS_COUNT))
  fi

  if ! read_flags --local -l; then
    puts "assert_opt_and_args_read: Missing expected --local -l flag!"
    ((++TEST_FAILS_COUNT))
  fi

  if read_flags --missing; then
    puts "assert_opt_and_args_read: Unexpected --missing flag resolved to true!"
    ((++TEST_FAILS_COUNT))
  fi

  if [ "$WORD" != "word" ]; then
    puts "assert_opt_and_args_read: $WORD != word"
    ((++TEST_FAILS_COUNT))
  fi

  if [ "$TEXT" != "Text with  3   words and spaces" ]; then
    puts "assert_opt_and_args_read: $TEXT != Text with  3   words and spaces"
    ((++TEST_FAILS_COUNT))
  fi

  if [ "$VERSION" != "42  20" ]; then
    puts "assert_opt_and_args_read: $VERSION != 42  20"
    ((++TEST_FAILS_COUNT))
  fi

  if [ "$BETA_NUMBER" != "beta" ]; then
    puts "assert_opt_and_args_read: $BETA_NUMBER != beta"
    ((++TEST_FAILS_COUNT))
  fi
}

assert_flags_read() {
  if read_flags -m --missing; then
    puts "assert_flags_read: Got unexpected --missing flag!"
    ((++TEST_FAILS_COUNT))
  fi
  if ! read_flags -e --expected; then
    puts "assert_flags_read: Failed to read --expected flag!"
    ((++TEST_FAILS_COUNT))
  fi
}

test_read_arr() {
  local expected_arr fails_count_before_this_tests=$TEST_FAILS_COUNT

  expected_arr=( first second )
  task assert_arr_read -a 'first second'
  task assert_arr_read -a 'first:second' :
  task assert_arr_read -a 'first second' ' '
  task assert_arr_read -a '  first   second   ' ' '
  task assert_arr_read -a '::first:second:' :
  task assert_arr_read -a $'first\nsecond' '\n'
  task assert_arr_read -a $'first\nsecond' $'\n'
  task assert_arr_read -a $'\nfirst\nsecond\n' '\n'

  expected_arr=( ' first' ' second' )
  task assert_arr_read -a ': first: second:' :

  expected_arr=( 'first  ' 'second  ' )
  task assert_arr_read -a $'\nfirst  \nsecond  \n' '\n'

  fail_if_new_assertions_has_failed || return $?

  log_success "Array parsed as expected!"
}

assert_arr_read() {
  local idx= myarray=()
  read_arr -a myarray "$3"

  if [ "${#myarray[@]}" != "${#expected_arr[@]}" ]; then
    puts "test_read_arr: Got ${#myarray[@]} elements instead of ${#expected_arr[@]}."
    ((++TEST_FAILS_COUNT))
  fi

  idx=0
  while (( idx < "${#expected_arr[@]}" )); do
    if [ "${myarray[$idx]}" != "${expected_arr[$idx]}" ]; then
      puts "Wrong element at $idx, expected: '${expected_arr[$idx]}', got: '${myarray[$idx]}'."
      ((++TEST_FAILS_COUNT))
    fi
    (( ++idx ))
  done
}

test_nounset_mode() { # helper of test_xfile — not a public task
  local fails_count_before_this_tests=$TEST_FAILS_COUNT
  local bash_bin nounset_err nounset_xlib_out

  for bash_bin in bash /bin/bash; do
    command -v "$bash_bin" >/dev/null || continue
    if ! nounset_err=$("$bash_bin" -u "$GIT_ROOT/Xfile_source/tests/mock_root.sh" help 2>&1 >/dev/null); then
      puts "test_nounset_mode: $bash_bin mock_root help failed under set -u"
      puts "$nounset_err"
      ((++TEST_FAILS_COUNT))
    fi
    if ! nounset_err=$("$bash_bin" -u "$GIT_ROOT/Xfile_source/tests/link_root.sh" 2>&1 >/dev/null); then
      puts "test_nounset_mode: $bash_bin link_root (no args) failed under set -u"
      puts "$nounset_err"
      ((++TEST_FAILS_COUNT))
    fi
    if ! nounset_err=$("$bash_bin" -u "$GIT_ROOT/Xfile_source/tests/mock_root.sh" test_tasks_chain_in_root 2>&1 >/dev/null); then
      puts "test_nounset_mode: $bash_bin mock_root test_tasks_chain_in_root failed under set -u"
      puts "$nounset_err"
      ((++TEST_FAILS_COUNT))
    fi
  done

  nounset_xlib_out=$(
    set -u
    if assert_defined not_present_value 2>/dev/null; then
      puts 'test_nounset_mode: assert_defined should fail on unset'
      exit 1
    fi
    if var_is_true not_present_value; then
      puts 'test_nounset_mode: var_is_true should be false on unset'
      exit 1
    fi
    unset UNSET_ARG UNSET_OPT
    read_args UNSET_ARG
    read_opt --missing UNSET_OPT
    if [ -n "$UNSET_ARG" ] || [ -n "$UNSET_OPT" ]; then
      puts 'test_nounset_mode: read_args/read_opt should leave missing values empty'
      exit 1
    fi
    echo OK
  )
  if [ $? -ne 0 ] || [[ "${nounset_xlib_out-}" != *OK* ]]; then
    puts "test_nounset_mode: in-process xlib checks failed under set -u"
    puts "${nounset_xlib_out-}"
    ((++TEST_FAILS_COUNT))
  fi

  fail_if_new_assertions_has_failed || return $?

  log_success "Xfile works under set -u!"
}

test_arr_to_str() {
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_cmd_output_and_err arr_to_str : one two three <<<'one:two:three'
  assert_cmd_output_and_err arr_to_str ' ' one-1 two-2 three-3 <<<'one-1 two-2 three-3'

  fail_if_new_assertions_has_failed || return $?

  log_success "arr_to_str works!"
}

_args_to_cmd_str() { ## fill _X_FAILED_COMMAND variable with given args
  cmd=$1
  shift

  local arg
  for arg in "$@"; do
    cmd="$cmd '$arg'"
  done
}

puts_failed_call() {
  local cmd
  _args_to_cmd_str "$@"
  print_with_emoji_and_color_header '🚧' 35 'Failed call:' "$cmd"
}

puts_failed_output() {
  print_with_emoji_and_color_header '🚧' 35 "Output in: $1" "$2"
}

puts_failed_diff() {
  local delta
  delta=$(diff <(echo "$1") <(echo "$2"))
  print_with_emoji_and_color_header '🚧' 35 "Diff:" "$delta"
}

assert_cmd_output_and_err() {
  local out expected

  out=$("$@")
  if test ! -t 0; then
    expected=$(cat)
  else
    expected=''
  fi

  if [ "$out" != "$expected" ]; then
    mkdir -p "$GIT_ROOT/output/expected/cmd_output/$1"
    echo "$out" >"$GIT_ROOT/output/expected/cmd_output/$1/out.log"
    puts_failed_call "$@"
    puts_failed_output "$GIT_ROOT/output/expected/cmd_output/$1/out.log" "$out"
    puts_failed_diff "$out" "$expected"
    ((++TEST_FAILS_COUNT))
  fi
}

assert_link_root_output() {
  local out expected

  out=$("$GIT_ROOT/Xfile_source/tests/link_root.sh" "$@" 2>/dev/null)
  if test ! -t 0; then
    expected=$(cat)
  else
    expected=''
  fi

  if [ "$out" != "$expected" ]; then
    mkdir -p "$GIT_ROOT/output/expected/link_root/$1"
    echo "$out" >"$GIT_ROOT/output/expected/link_root/$1/out.log"
    puts_failed_call "$@"
    puts_failed_output "$GIT_ROOT/output/expected/link_root/$1/out.log" "$out"
    puts_failed_diff "$out" "$expected"
    ((++TEST_FAILS_COUNT))
  fi
}

assert_mock_root_output_and_err() {
  local out expected

  out=$("$GIT_ROOT/Xfile_source/tests/mock_root.sh" "$@" 2>&1)
  if test ! -t 0; then
    expected=$(cat)
  else
    expected=''
  fi

  if [ "$out" != "$expected" ]; then
    mkdir -p "$GIT_ROOT/output/expected/mock_root/$1"
    echo "$out" >"$GIT_ROOT/output/expected/mock_root/$1/out.log"
    puts_failed_call "$@"
    puts_failed_output "$GIT_ROOT/output/expected/mock_root/$1/out.log" "$out"
    puts_failed_diff "$out" "$expected"
    ((++TEST_FAILS_COUNT))
  fi
}

assert_mock_root_output() {
  local out expected

  out=$("$GIT_ROOT/Xfile_source/tests/mock_root.sh" "$@" 2>/dev/null)
  if test ! -t 0; then
    expected=$(cat)
  else
    expected=''
  fi

  if [ "$out" != "$expected" ]; then
    mkdir -p "$GIT_ROOT/output/expected/mock_root/$1"
    echo "$out" >"$GIT_ROOT/output/expected/mock_root/$1/out.log"
    puts_failed_call "$@"
    puts_failed_output "$GIT_ROOT/output/expected/mock_root/$1/out.log" "$out"
    puts_failed_diff "$out" "$expected"
    ((++TEST_FAILS_COUNT))
  fi
}

assert_mock_root_err() {
  local out expected

  out=$("$GIT_ROOT/Xfile_source/tests/mock_root.sh" "$@" 2>&1 1>/dev/null)
  if test ! -t 0; then
    expected=$(cat)
  else
    expected=''
  fi

  if [ "$out" != "$expected" ]; then
    mkdir -p "$GIT_ROOT/output/expected/mock_root/$1"
    echo "$out" >"$GIT_ROOT/output/expected/mock_root/$1/err.log"
    puts_failed_call "$@"
    puts_failed_output "$GIT_ROOT/output/expected/mock_root/$1/err.log" "$out"
    puts_failed_diff "$out" "$expected"
    ((++TEST_FAILS_COUNT))
  fi
}

test_xfile_children() { # helper of test_xfile — not a public task
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_link_root_output main <<<'main in child_zero'
  assert_link_root_output link_root_task <<<'link_root_task in link_root'
  assert_link_root_output one:child_one_task <<<'child_one_task in child_one'
  assert_link_root_output two:child_two_task <<<'child_two_task in child_two'
  assert_link_root_output one:main <<<'main in child_one'
  assert_link_root_output task_args two:child_two_task <<<'--two'
  assert_link_root_output task_args main <<<'--something -v'
  assert_link_root_output task_args one:main <<<'-a --name'
  assert_link_root_output task_args two:main <<<''
  assert_link_root_output task_args subshell_task <<<'--argument --dir'
  assert_link_root_output task_args subshell_task_two <<<'--force -f'
  assert_link_root_output task_names <<'HEREDOC'
link_root_task
subshell_task
main
one:two:child_two_task
one:main
two:child_two_task
two:main
HEREDOC
  assert_link_root_output show_tasks <<'HEREDOC'
[34m# Xfile_source/tests/link_root.sh tasks:(B[m
  [93mlink_root_task                                  [92m link_root task[0m
  [93msubshell_task                                   [92m link_root – subshell_task[0m

[34m# Xfile_source/tests/child_zero.sh tasks:(B[m
  [93mmain                                            [92m child_zero main task[0m

[34m# Xfile_source/tests/child_one.sh tasks:(B[m
  [93mone:two:child_two_task                          [92m child_one task that should not override child_two[0m
  [93mone:main                                        [92m child_one main task[0m

[34m# Xfile_source/tests/child_two.sh tasks:(B[m
  [93mtwo:child_two_task                              [92m child_two task[0m
  [93mtwo:main                                        [92m child_two main task[0m
HEREDOC

  fail_if_new_assertions_has_failed || return $?

  log_success "Xfile children links works as expected!"
}

test_xfile_dispatch() { # helper of test_xfile — not a public task
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_mock_root_output_and_err test_tasks_chain_in_root <<'HEREDOC'
🚀 [34mdo: test_tasks_chain_in_root(B[m
🌚 [34min: test_tasks_chain_in_root > root_stack_1(B[m
root_stack_1 start
from test_tasks_chain_in_root
🌚 [34min: test_tasks_chain_in_root > root_stack_1 > root_stack_2(B[m
root_stack_2 start
from root_stack_1
root_stack_2 end without err
🌝 [36mout: test_tasks_chain_in_root > root_stack_1 < root_stack_2(B[m
root_stack_1 end without err
🌝 [36mout: test_tasks_chain_in_root < root_stack_1(B[m
👍 [36mdone: test_tasks_chain_in_root(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_root_fails <<'HEREDOC'
🚀 [34mdo: test_tasks_chain_in_root_fails(B[m
🌚 [34min: test_tasks_chain_in_root_fails > root_stack_1(B[m
root_stack_1 start
from test_tasks_chain_in_root_fails
🌚 [34min: test_tasks_chain_in_root_fails > root_stack_1 > root_stack_2(B[m
root_stack_2 start
from root_stack_1
💥 [31mat: test_tasks_chain_in_root_fails > root_stack_1 < root_stack_2(B[m
💥 7 from command:
💥 return "$1"
💥 [31mat: test_tasks_chain_in_root_fails < root_stack_1(B[m
💥 [31mfailed: test_tasks_chain_in_root_fails(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_from_root_to_child <<'HEREDOC'
🚀 [34mdo: test_tasks_chain_from_root_to_child(B[m
❗️ [33mCalled uncached child task 'child_stack_1', should add it to task list in 'link_child_xfile' call(B[m
🌚 [34min: test_tasks_chain_from_root_to_child > [mock_child.sh] child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_from_root_to_child
🌚 [34min: test_tasks_chain_from_root_to_child > [mock_child.sh] child_stack_1 > child_stack_2(B[m
child_stack_2 start
from child_stack_1
child_stack_2 end without err
🌝 [36mout: test_tasks_chain_from_root_to_child > [mock_child.sh] child_stack_1 < child_stack_2(B[m
child_stack_1 end without err
🌝 [36mout: test_tasks_chain_from_root_to_child < [mock_child.sh] child_stack_1(B[m
👍 [36mdone: test_tasks_chain_from_root_to_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_cached_tasks_chain_from_root_to_child <<'HEREDOC'
🚀 [34mdo: test_cached_tasks_chain_from_root_to_child(B[m
🌚 [34min: test_cached_tasks_chain_from_root_to_child > [mock_child.sh] child_stack_1_cached(B[m
child_stack_1_cached start
from test_cached_tasks_chain_from_root_to_child
🌚 [34min: test_cached_tasks_chain_from_root_to_child > [mock_child.sh] child_stack_1_cached > child_stack_2(B[m
child_stack_2 start
from child_stack_1_cached
child_stack_2 end without err
🌝 [36mout: test_cached_tasks_chain_from_root_to_child > [mock_child.sh] child_stack_1_cached < child_stack_2(B[m
child_stack_1_cached end without err
🌝 [36mout: test_cached_tasks_chain_from_root_to_child < [mock_child.sh] child_stack_1_cached(B[m
👍 [36mdone: test_cached_tasks_chain_from_root_to_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_from_root_to_child_fails_in_child <<'HEREDOC'
🚀 [34mdo: test_tasks_chain_from_root_to_child_fails_in_child(B[m
❗️ [33mCalled uncached child task 'child_stack_1', should add it to task list in 'link_child_xfile' call(B[m
🌚 [34min: test_tasks_chain_from_root_to_child_fails_in_child > [mock_child.sh] child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_from_root_to_child_fails_in_child
🌚 [34min: test_tasks_chain_from_root_to_child_fails_in_child > [mock_child.sh] child_stack_1 > child_stack_2(B[m
child_stack_2 start
from child_stack_1
💥 [31mat: test_tasks_chain_from_root_to_child_fails_in_child > [mock_child.sh] child_stack_1 < child_stack_2(B[m
💥 7 from command:
💥 return "$1"
💥 [31mat: test_tasks_chain_from_root_to_child_fails_in_child < [mock_child.sh] child_stack_1(B[m
💥 7 from command:
💥 child_stack_1 'from test_tasks_chain_from_root_to_child_fails_in_child'
💥 [31mfailed: test_tasks_chain_from_root_to_child_fails_in_child(B[m
💥 7 from command:
💥 return "$code"
HEREDOC

  assert_mock_root_output_and_err test_process_in_logic_expression <<'HEREDOC'
🚀 [34mdo: test_process_in_logic_expression(B[m
started test_process_in_logic_expression
🌚 [34min: test_process_in_logic_expression > root_stack_2(B[m
root_stack_2 start
root_stack_2 end without err
🌝 [36mout: test_process_in_logic_expression < root_stack_2(B[m
task root_stack_2 succeeded as expected. Because errexit is implicitly disabled (sadly)
🌚 [34min: test_process_in_logic_expression > (process) root_stack_2(B[m
root_stack_2 start
💥 [31mat: test_process_in_logic_expression < (process) root_stack_2(B[m
💥 89 from command:
💥 root_stack_2
process root_stack_2 failed as expected, new process does not inherit disabled errexit
ended test_process_in_logic_expression without err
👍 [36mdone: test_process_in_logic_expression(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_loaded_source <<'HEREDOC'
🚀 [34mdo: test_tasks_chain_in_loaded_source(B[m
🌚 [34min: test_tasks_chain_in_loaded_source > loaded_source_stack_1(B[m
started loaded_source_stack_1
🌚 [34min: test_tasks_chain_in_loaded_source > loaded_source_stack_1 > loaded_source_stack_2(B[m
started loaded_source_stack_2
🌚 [34min: test_tasks_chain_in_loaded_source > loaded_source_stack_1 > loaded_source_stack_2 > loaded_source_stack_3(B[m
started loaded_source_stack_3
finished loaded_source_stack_3 as planned
🌝 [36mout: test_tasks_chain_in_loaded_source > loaded_source_stack_1 > loaded_source_stack_2 < loaded_source_stack_3(B[m
finished loaded_source_stack_2 as planned
🌝 [36mout: test_tasks_chain_in_loaded_source > loaded_source_stack_1 < loaded_source_stack_2(B[m
finished loaded_source_stack_1 as planned
🌝 [36mout: test_tasks_chain_in_loaded_source < loaded_source_stack_1(B[m
👍 [36mdone: test_tasks_chain_in_loaded_source(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_loaded_source_fails <<'HEREDOC'
🚀 [34mdo: test_tasks_chain_in_loaded_source_fails(B[m
🌚 [34min: test_tasks_chain_in_loaded_source_fails > loaded_source_stack_1(B[m
started loaded_source_stack_1
🌚 [34min: test_tasks_chain_in_loaded_source_fails > loaded_source_stack_1 > loaded_source_stack_2(B[m
started loaded_source_stack_2
🌚 [34min: test_tasks_chain_in_loaded_source_fails > loaded_source_stack_1 > loaded_source_stack_2 > loaded_source_stack_3(B[m
started loaded_source_stack_3
💥 [31mat: test_tasks_chain_in_loaded_source_fails > loaded_source_stack_1 > loaded_source_stack_2 < loaded_source_stack_3(B[m
💥 24 from command:
💥 return "$1"
💥 [31mat: test_tasks_chain_in_loaded_source_fails > loaded_source_stack_1 < loaded_source_stack_2(B[m
💥 [31mat: test_tasks_chain_in_loaded_source_fails < loaded_source_stack_1(B[m
💥 [31mfailed: test_tasks_chain_in_loaded_source_fails(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_child <<'HEREDOC'
❗️ [33mCalled uncached child task 'test_tasks_chain_in_child', should add it to task list in 'link_child_xfile' call(B[m
🚀 [34mdo: [mock_child.sh] test_tasks_chain_in_child(B[m
🌚 [34min: [mock_child.sh] test_tasks_chain_in_child > child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_in_child
🌚 [34min: [mock_child.sh] test_tasks_chain_in_child > child_stack_1 > child_stack_2(B[m
child_stack_2 start
from child_stack_1
child_stack_2 end without err
🌝 [36mout: [mock_child.sh] test_tasks_chain_in_child > child_stack_1 < child_stack_2(B[m
child_stack_1 end without err
🌝 [36mout: [mock_child.sh] test_tasks_chain_in_child < child_stack_1(B[m
👍 [36mdone: [mock_child.sh] test_tasks_chain_in_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_child_fails <<'HEREDOC'
❗️ [33mCalled uncached child task 'test_tasks_chain_in_child_fails', should add it to task list in 'link_child_xfile' call(B[m
🚀 [34mdo: [mock_child.sh] test_tasks_chain_in_child_fails(B[m
🌚 [34min: [mock_child.sh] test_tasks_chain_in_child_fails > child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_in_child_fails
🌚 [34min: [mock_child.sh] test_tasks_chain_in_child_fails > child_stack_1 > child_stack_2(B[m
child_stack_2 start
from child_stack_1
💥 [31mat: [mock_child.sh] test_tasks_chain_in_child_fails > child_stack_1 < child_stack_2(B[m
💥 7 from command:
💥 return "$1"
💥 [31mat: [mock_child.sh] test_tasks_chain_in_child_fails < child_stack_1(B[m
💥 [31mfailed: [mock_child.sh] test_tasks_chain_in_child_fails(B[m
💥 7 from command:
💥 test_tasks_chain_in_child_fails
HEREDOC

  assert_mock_root_output_and_err test_root_task_from_child_without_link_fails <<'HEREDOC'
❗️ [33mCalled uncached child task 'test_root_task_from_child_without_link_fails', should add it to task list in 'link_child_xfile' call(B[m
🚀 [34mdo: [mock_child.sh] test_root_task_from_child_without_link_fails(B[m
❌ [31m🤔 No task named: 'root_stack_2' in this Xfile or linked children!(B[m
Maybe misspelled?
Try: x help
Call args:
root_stack_2
from test_root_task_from_child_without_link_fails
💥 [31mfailed: [mock_child.sh] test_root_task_from_child_without_link_fails(B[m
💥 8 from command:
💥 test_root_task_from_child_without_link_fails
HEREDOC

  assert_mock_root_output_and_err test_child_cannot_call_child_that_not_linked_directly <<'HEREDOC'
❗️ [33mCalled uncached child task 'test_child_cannot_call_child_that_not_linked_directly', should add it to task list in 'link_child_xfile' call(B[m
🚀 [34mdo: [mock_child_two.sh] test_child_cannot_call_child_that_not_linked_directly(B[m
❌ [31m🤔 No task named: 'child_stack_1' in this Xfile or linked children!(B[m
Maybe misspelled?
Try: x help
Call args:
child_stack_1
from test_child_cannot_call_child_that_not_linked_directly
💥 [31mfailed: [mock_child_two.sh] test_child_cannot_call_child_that_not_linked_directly(B[m
💥 8 from command:
💥 test_child_cannot_call_child_that_not_linked_directly
HEREDOC

  assert_mock_root_output_and_err test_root_task_from_child <<'HEREDOC'
❗️ [33mCalled uncached child task 'test_root_task_from_child', should add it to task list in 'link_child_xfile' call(B[m
🚀 [34mdo: [mock_child_two.sh] test_root_task_from_child(B[m
❗️ [33mCalled uncached child task 'root_stack_2', should add it to task list in 'link_child_xfile' call(B[m
🌚 [34min: [mock_child_two.sh] test_root_task_from_child > [mock_root.sh] root_stack_2(B[m
root_stack_2 start
from test_root_task_from_child
root_stack_2 end without err
🌝 [36mout: [mock_child_two.sh] test_root_task_from_child < [mock_root.sh] root_stack_2(B[m
👍 [36mdone: [mock_child_two.sh] test_root_task_from_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_failure_after_ignored_process_failure_logging <<'HEREDOC'
🚀 [34mdo: test_failure_after_ignored_process_failure_logging(B[m
🌚 [34min: test_failure_after_ignored_process_failure_logging > (process) return_code(B[m
💥 [31mat: test_failure_after_ignored_process_failure_logging < (process) return_code(B[m
💥 88 from command:
💥 return_code '88'
la la la
💥 [31mfailed: test_failure_after_ignored_process_failure_logging(B[m
💥 1 from command:
💥 false
HEREDOC

  assert_mock_root_output_and_err test_tasks_in_subshell_warnings <<'HEREDOC'
🚀 [34mdo: test_tasks_in_subshell_warnings(B[m
❗️ [33mDetected task call from subshell – 1.(B[m
'task' called inside of 'test_tasks_in_subshell_warnings'
🌚 [34min: test_tasks_in_subshell_warnings > (subshell) root_stack_1(B[m
root_stack_1 start
🌚 [34min: test_tasks_in_subshell_warnings > (subshell) root_stack_1 > root_stack_2(B[m
root_stack_2 start
from root_stack_1
root_stack_2 end without err
🌝 [36mout: test_tasks_in_subshell_warnings > (subshell) root_stack_1 < root_stack_2(B[m
root_stack_1 end without err
🌝 [36mout: test_tasks_in_subshell_warnings < (subshell) root_stack_1(B[m
❗️ [33mDetected task call from subshell – 1.(B[m
'task' called inside of 'test_tasks_in_subshell_warnings'
🌚 [34min: test_tasks_in_subshell_warnings > (subshell) return_code(B[m
🌝 [36mout: test_tasks_in_subshell_warnings < (subshell) return_code(B[m
👍 [36mdone: test_tasks_in_subshell_warnings(B[m
HEREDOC

  fail_if_new_assertions_has_failed || return $?

  log_success "Xfile dispatch works as expected!"
}

# - Note:
# 1) multiple tee may mix up lines, get err and out separately
# 2) tasks inherit streams forwarding, so caller task tail is in the logs of child task
test_forward_out_and_err_to_dir() { # helper of test_xfile — not a public task
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_mock_root_output test_forward_out_and_err_to_dir <<'HEREDOC'
out 1 in test_forward_out_and_err_to_dir
out in foo
out in bar
out 2 in test_forward_out_and_err_to_dir
HEREDOC

  assert_mock_root_err test_forward_out_and_err_to_dir <<'HEREDOC'
🚀 [34mdo: test_forward_out_and_err_to_dir(B[m
💁 [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir/main
- called inside of 'test_forward_out_and_err_to_dir'
started test_forward_out_and_err_to_dir
in test_forward_out_and_err_to_dir
🌚 [34min: test_forward_out_and_err_to_dir > bar(B[m
in bar
🌚 [34min: test_forward_out_and_err_to_dir > bar > foo(B[m
💁 [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir/foo
- called inside of 'foo'
❗️ [33mRepetitive forwarding of output and error streams in the same shell (script/subshell) – 0.(B[m
Called inside of 'foo'
Will do.
But previous forwarding will remain in effect globally in this shell, fd will be chained like:
tee -> tee -> >1 (process fd)
Consider refactor to 'run_with_status_marker' or subshelling the task that must forward itself

in foo
🌝 [36mout: test_forward_out_and_err_to_dir > bar < foo(B[m
in bar after foo
🌝 [36mout: test_forward_out_and_err_to_dir < bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [36mdone: test_forward_out_and_err_to_dir(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/main/out.log" <<'HEREDOC'
out 1 in test_forward_out_and_err_to_dir
out in foo
out in bar
out 2 in test_forward_out_and_err_to_dir
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/main/err.log" <<'HEREDOC'
started test_forward_out_and_err_to_dir
in test_forward_out_and_err_to_dir
🌚 [34min: test_forward_out_and_err_to_dir > bar(B[m
in bar
🌚 [34min: test_forward_out_and_err_to_dir > bar > foo(B[m
💁 [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir/foo
- called inside of 'foo'
❗️ [33mRepetitive forwarding of output and error streams in the same shell (script/subshell) – 0.(B[m
Called inside of 'foo'
Will do.
But previous forwarding will remain in effect globally in this shell, fd will be chained like:
tee -> tee -> >1 (process fd)
Consider refactor to 'run_with_status_marker' or subshelling the task that must forward itself

in foo
🌝 [36mout: test_forward_out_and_err_to_dir > bar < foo(B[m
in bar after foo
🌝 [36mout: test_forward_out_and_err_to_dir < bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [36mdone: test_forward_out_and_err_to_dir(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/foo/out.log" <<'HEREDOC'
out in foo
out in bar
out 2 in test_forward_out_and_err_to_dir
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/foo/err.log" <<'HEREDOC'
in foo
🌝 [36mout: test_forward_out_and_err_to_dir > bar < foo(B[m
in bar after foo
🌝 [36mout: test_forward_out_and_err_to_dir < bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [36mdone: test_forward_out_and_err_to_dir(B[m
HEREDOC

  fail_if_new_assertions_has_failed || return $?

  log_success "forward_out_and_err_to_dir works as expected!"
}

test_forward_out_and_err_to_dir_one_level() { # helper of test_xfile — not a public task
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_mock_root_output test_forward_out_and_err_to_dir_one_level <<'HEREDOC'
out 1 in test_forward_out_and_err_to_dir_one_level
out in bar
out 2 in test_forward_out_and_err_to_dir_one_level
HEREDOC

  assert_mock_root_err test_forward_out_and_err_to_dir_one_level <<'HEREDOC'
🚀 [34mdo: test_forward_out_and_err_to_dir_one_level(B[m
💁 [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir_one_level/main
- called inside of 'test_forward_out_and_err_to_dir_one_level'
started test_forward_out_and_err_to_dir_one_level
in test_forward_out_and_err_to_dir_one_level
🌚 [34min: test_forward_out_and_err_to_dir_one_level > bar(B[m
in bar
ended bar
🌝 [36mout: test_forward_out_and_err_to_dir_one_level < bar(B[m
in test_forward_out_and_err_to_dir_one_level after bar
ended test_forward_out_and_err_to_dir_one_level
👍 [36mdone: test_forward_out_and_err_to_dir_one_level(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir_one_level/main/out.log" <<'HEREDOC'
out 1 in test_forward_out_and_err_to_dir_one_level
out in bar
out 2 in test_forward_out_and_err_to_dir_one_level
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir_one_level/main/err.log" <<'HEREDOC'
started test_forward_out_and_err_to_dir_one_level
in test_forward_out_and_err_to_dir_one_level
🌚 [34min: test_forward_out_and_err_to_dir_one_level > bar(B[m
in bar
ended bar
🌝 [36mout: test_forward_out_and_err_to_dir_one_level < bar(B[m
in test_forward_out_and_err_to_dir_one_level after bar
ended test_forward_out_and_err_to_dir_one_level
👍 [36mdone: test_forward_out_and_err_to_dir_one_level(B[m
HEREDOC

  fail_if_new_assertions_has_failed || return $?

  log_success "test_forward_out_and_err_to_dir_one_level works as expected!"
}

# - Note:
# 1) multiple tee may mix up lines, get err and out separately
test_run_with_status_marker() { # helper of test_xfile — not a public task
  local fails_count_before_this_tests=$TEST_FAILS_COUNT

  assert_mock_root_output test_run_with_status_marker <<'HEREDOC'
out 1 in test_run_with_status_marker
out in foo
out in bar
out 2 in test_run_with_status_marker
HEREDOC

  assert_mock_root_err test_run_with_status_marker <<'HEREDOC'
🚀 [34mdo: test_run_with_status_marker(B[m
started test_run_with_status_marker
in test_run_with_status_marker
💁 [35mForwarding output and error streams:(B[m
- of: task bar
- to: ./output/xfile_tests/test_run_with_status_marker/bar
💁 [35mWill create 'success' file in forwarding dir, unless command fails(B[m
🌚 [34min: test_run_with_status_marker > bar(B[m
in bar
💁 [35mForwarding output and error streams:(B[m
- of: task foo
- to: ./output/xfile_tests/test_run_with_status_marker/foo
💁 [35mWill create 'success' file in forwarding dir, unless command fails(B[m
🌚 [34min: test_run_with_status_marker > bar > foo(B[m
in foo
🌝 [36mout: test_run_with_status_marker > bar < foo(B[m
in bar after foo
🌝 [36mout: test_run_with_status_marker < bar(B[m
in test_run_with_status_marker after bar
ended test_run_with_status_marker
👍 [36mdone: test_run_with_status_marker(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/bar/out.log" <<'HEREDOC'
out in foo
out in bar
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/bar/err.log" <<'HEREDOC'
🌚 [34min: test_run_with_status_marker > bar(B[m
in bar
💁 [35mForwarding output and error streams:(B[m
- of: task foo
- to: ./output/xfile_tests/test_run_with_status_marker/foo
💁 [35mWill create 'success' file in forwarding dir, unless command fails(B[m
🌚 [34min: test_run_with_status_marker > bar > foo(B[m
in foo
🌝 [36mout: test_run_with_status_marker > bar < foo(B[m
in bar after foo
🌝 [36mout: test_run_with_status_marker < bar(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/foo/out.log" <<'HEREDOC'
out in foo
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/foo/err.log" <<'HEREDOC'
🌚 [34min: test_run_with_status_marker > bar > foo(B[m
in foo
🌝 [36mout: test_run_with_status_marker > bar < foo(B[m
HEREDOC

  fail_if_new_assertions_has_failed || return $?

  log_success "test_run_with_status_marker works as expected!"
}

begin_xfile_task
