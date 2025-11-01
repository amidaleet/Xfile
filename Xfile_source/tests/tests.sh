#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

function test_xfile() { ## Test Xfile implementation (arguments handling)
  local fails_log
  fails_log=$(
    task test_var_is_true
    task test_assert_defined
    task test_args_parsing -l VERSION="42  20" --word 'word' -f -t "Text with  3   words and spaces" BETA_NUMBER='beta'
    task test_args_parsing -l -f -w 'word' -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20"
    task test_args_parsing -lf -w 'word' -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20"
    task test_args_parsing --local --word 'word' --force -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20"
    task test_args_parsing BETA_NUMBER=beta --local --word 'word' --force --text "Text with  3   words and spaces" VERSION="42  20"
    process test_args_parsing BETA_NUMBER=beta --local --word 'word' --force --text "Text with  3   words and spaces" VERSION="42  20"
    task test_read_flags -o -e
    task test_read_flags --expected --other
    task test_arr_to_str
    EXPECTED='first:second' task test_read_arr -a 'first second'
    EXPECTED='first:second' task test_read_arr -a 'first:second' :
    EXPECTED='first:second' task test_read_arr -a 'first second' ' '
    EXPECTED='first:second' task test_read_arr -a '  first   second   ' ' '
    EXPECTED='first:second' task test_read_arr -a '::first:second:' :
    EXPECTED=' first: second' task test_read_arr -a ': first: second:' :
    EXPECTED='first:second' task test_read_arr -a $'first\nsecond' '\n'
    EXPECTED='first:second' task test_read_arr -a $'\nfirst\nsecond\n' '\n'
    EXPECTED='first  :second  ' task test_read_arr -a $'\nfirst  \nsecond  \n' '\n'
    task test_xfile_children
    task test_xfile_dispatch
    task test_forward_out_and_err_to_dir
    task test_run_with_status_marker

    # - Note:
    # '$(...)' does not inherit caller shell options.
    # So errexit in this block is turned off.
    # It is done on purpose.
    # Full test coverage is desired, not a fail fast approach.
    # Output must not be empty to be considered as assertion failure.
    true
  )

  if [ -n "$fails_log" ]; then
    log_error "Xfile test failed with problems:"
    log "$fails_log"
    return 3;
  fi

  log_success "Xfile test succeeded!"
}

test_var_is_true() {
  local has_problems=false

  assert_bool() {
    # shellcheck disable=SC2034
    local FT_TEST=$1
    if var_is_true FT_TEST; then
      if [ "$2" != true ]; then
        puts "assert_bool: '$1' should be treated as false"
        has_problems=true
      fi
    elif [ "$2" != false ]; then
      puts "assert_bool: '$1' should be treated as true"
      has_problems=true
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

  if var_is_true has_problems; then return 3; fi

  log_success "var_is_true works as expected!"
}

test_assert_defined() {
  local value_one=1
  local value_two=work
  local has_problems=false

  if ! assert_defined value_one value_two 2>/dev/null; then
    puts "test_assert_defined: Assert is triggered on existing values!"
    has_problems=true
  fi
  if assert_defined not_present_value 2>/dev/null; then
    puts "test_assert_defined: Assert is not triggered on non-existing values!"
    has_problems=true
  fi

  if var_is_true has_problems; then return 3; fi

  log_success "assert_defined works as expected!"
}

test_args_parsing() {
  read_opt -w --word WORD
  read_opt -t --text TEXT
  read_args VERSION BETA_NUMBER

  local has_problems=false

  if ! read_flags --force -f; then
    puts "test_args_parsing: Missing expected --force -f flag!"
    has_problems=true
  fi

  if ! read_flags --local -l; then
    puts "test_args_parsing: Missing expected --local -l flag!"
    has_problems=true
  fi

  if read_flags --missing; then
    puts "test_args_parsing: Unexpected --missing flag resolved to true!"
    has_problems=true
  fi

  if [ "$WORD" != "word" ]; then
    puts "test_args_parsing: $WORD != word"
    has_problems=true
  fi

  if [ "$TEXT" != "Text with  3   words and spaces" ]; then
    puts "test_args_parsing: $TEXT != Text with  3   words and spaces"
    has_problems=true
  fi

  if [ "$VERSION" != "42  20" ]; then
    puts "test_args_parsing: $VERSION != 42  20"
    has_problems=true
  fi

  if [ "$BETA_NUMBER" != "beta" ]; then
    puts "test_args_parsing: $BETA_NUMBER != beta"
    has_problems=true
  fi

  if var_is_true has_problems; then return 3; fi

  log_success "Args parsed as expected!"
}

test_read_flags() {
  local has_problems=false

  if read_flags -m --missing; then
    puts "test_read_flags: Got unexpected --missing flag!"
    has_problems=true
  fi
  if ! read_flags -e --expected; then
    puts "test_read_flags: Failed to read --expected flag!"
    has_problems=true
  fi

  if var_is_true has_problems; then return 3; fi

  log_success "Flags parsed as expected!"
}

test_read_arr() {
  local expected_arr idx has_problems=false
  IFS=':' read -a expected_arr <<<"$EXPECTED"

  read_arr -a myarray "$3"

  if [ "${#myarray[@]}" != "${#expected_arr[@]}" ]; then
    puts "test_read_arr: Got ${#myarray[@]} elements instead of ${#expected_arr[@]}."
    has_problems=true
  fi

  idx=0
  while (( idx < "${#expected_arr[@]}" )); do
    if [ "${myarray[$idx]}" != "${expected_arr[$idx]}" ]; then
      puts "Wrong element at $idx, expected: '${expected_arr[$idx]}', got: '${myarray[$idx]}'."
      has_problems=true
    fi
    (( ++idx ))
  done

  if var_is_true has_problems; then return 3; fi

  log_success "Array parsed as expected!"
}

test_arr_to_str() {
  local has_problems=false

  assert_cmd_output_and_err arr_to_str : one two three <<<'one:two:three'
  assert_cmd_output_and_err arr_to_str ' ' one-1 two-2 three-3 <<<'one-1 two-2 three-3'

  if var_is_true has_problems; then return 3; fi

  log_success "arr_to_str works!"
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

    puts '' \
      "$(color_str 5 "- Failed call:")" "$(arr_to_str ' ' "$@")" '' \
      "$(color_str 5 "-- Output: in: $GIT_ROOT/output/expected/cmd_output/$1/out.log")" "$out" \
      '--' \
      "$(color_str 5 -- Diff:)" "$(diff <(echo "$out") <(echo "$expected"))" \
      '--'
    has_problems=true
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

    puts '' \
      "$(color_str 5 "- Failed call:")" "$(arr_to_str ' ' "$@")" '' \
      "$(color_str 5 "-- Output: in: $GIT_ROOT/output/expected/link_root/$1/out.log")" "$out" \
      '--' \
      "$(color_str 5 -- Diff:)" "$(diff <(echo "$out") <(echo "$expected"))" \
      '--'
    has_problems=true
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

    puts '' \
      "$(color_str 5 "- Failed call:")" "$(arr_to_str ' ' "$@")" '' \
      "$(color_str 5 "-- Output in: $GIT_ROOT/output/expected/mock_root/$1/out.log")" "$out" \
      '--' \
      "$(color_str 5 -- Diff:)" "$(diff <(echo "$out") <(echo "$expected"))" \
      '--'
    has_problems=true
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

    puts '' \
      "$(color_str 5 "- Failed call:")" "$(arr_to_str ' ' "$@")" '' \
      "$(color_str 5 "-- Output in: $GIT_ROOT/output/expected/mock_root/$1/out.log")" "$out" \
      '--' \
      "$(color_str 5 -- Diff:)" "$(diff <(echo "$out") <(echo "$expected"))" \
      '--'
    has_problems=true
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
    echo "$out" >"$GIT_ROOT/output/expected/mock_root/$1/out.log"

    puts '' \
      "$(color_str 5 "- Failed call:")" "$(arr_to_str ' ' "$@")" '' \
      "$(color_str 5 "-- Output in: $GIT_ROOT/output/expected/mock_root/$1/out.log")" "$out" \
      '--' \
      "$(color_str 5 -- Diff:)" "$(diff <(echo "$out") <(echo "$expected"))" \
      '--'
    has_problems=true
  fi
}

function test_xfile_children() { ## Check how helper tasks works with link_child_xfile
  local has_problems=false

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

  if var_is_true has_problems; then return 3; fi

  log_success "Xfile children links works as expected!"
}

function test_xfile_dispatch() { ## Check how tasks are called and logged
  local has_problems=false

  assert_mock_root_output_and_err test_tasks_chain_in_root <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_root(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_root > (mock_root.sh) func root_stack_1(B[m
root_stack_1 start
from test_tasks_chain_in_root
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_root > (mock_root.sh) func root_stack_1 > (mock_root.sh) func root_stack_2(B[m
root_stack_2 start
from root_stack_1
root_stack_2 end without err
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_in_root > (mock_root.sh) func root_stack_1 < (mock_root.sh) func root_stack_2(B[m
root_stack_1 end without err
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_in_root < (mock_root.sh) func root_stack_1(B[m
👍 [34mdone: (mock_root.sh) func test_tasks_chain_in_root(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_root_fails <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_root_fails(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_root_fails > (mock_root.sh) func root_stack_1(B[m
root_stack_1 start
from test_tasks_chain_in_root_fails
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_root_fails > (mock_root.sh) func root_stack_1 > (mock_root.sh) func root_stack_2(B[m
root_stack_2 start
from root_stack_1
💥 [31mat: (mock_root.sh) func test_tasks_chain_in_root_fails > (mock_root.sh) func root_stack_1 > (mock_root.sh) func root_stack_2(B[m
💥 7 from command:
💥 return "$1"
💥 [31mat: (mock_root.sh) func test_tasks_chain_in_root_fails > (mock_root.sh) func root_stack_1(B[m
💥 [31mfailed: (mock_root.sh) func test_tasks_chain_in_root_fails(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_from_root_to_child <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_from_root_to_child(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_from_root_to_child > (mock_child.sh) child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_from_root_to_child
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_from_root_to_child > (mock_child.sh) child_stack_1 > (mock_child.sh) func child_stack_2(B[m
child_stack_2 start
from child_stack_1
child_stack_2 end without err
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_from_root_to_child > (mock_child.sh) child_stack_1 < (mock_child.sh) func child_stack_2(B[m
child_stack_1 end without err
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_from_root_to_child < (mock_child.sh) child_stack_1(B[m
👍 [34mdone: (mock_root.sh) func test_tasks_chain_from_root_to_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_from_root_to_child_fails_in_child <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_from_root_to_child_fails_in_child(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_from_root_to_child_fails_in_child > (mock_child.sh) child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_from_root_to_child_fails_in_child
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_from_root_to_child_fails_in_child > (mock_child.sh) child_stack_1 > (mock_child.sh) func child_stack_2(B[m
child_stack_2 start
from child_stack_1
💥 [31mat: (mock_root.sh) func test_tasks_chain_from_root_to_child_fails_in_child > (mock_child.sh) child_stack_1 > (mock_child.sh) func child_stack_2(B[m
💥 7 from command:
💥 return "$1"
💥 [31mat: (mock_root.sh) func test_tasks_chain_from_root_to_child_fails_in_child > (mock_child.sh) child_stack_1(B[m
💥 7 from command:
💥 child_stack_1 'from test_tasks_chain_from_root_to_child_fails_in_child'
💥 [31mfailed: (mock_root.sh) func test_tasks_chain_from_root_to_child_fails_in_child(B[m
💥 7 from command:
💥 return "$code"
HEREDOC

  assert_mock_root_output_and_err test_process_in_logic_expression <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_process_in_logic_expression(B[m
started test_process_in_logic_expression
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_process_in_logic_expression > (mock_root.sh) func root_stack_2(B[m
root_stack_2 start
root_stack_2 end without err
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_process_in_logic_expression < (mock_root.sh) func root_stack_2(B[m
task root_stack_2 succeeded as expected. Because errexit is implicitly disabled (sadly)
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_process_in_logic_expression > (mock_root.sh) root_stack_2(B[m
root_stack_2 start
💥 [31mat: (mock_root.sh) func test_process_in_logic_expression > (mock_root.sh) root_stack_2(B[m
💥 89 from command:
💥 root_stack_2
process root_stack_2 failed as expected, new process does not inherit disabled errexit
ended test_process_in_logic_expression without err
👍 [34mdone: (mock_root.sh) func test_process_in_logic_expression(B[m
HEREDOC


  assert_mock_root_output_and_err test_tasks_chain_in_loaded_source <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source > (mock_root.sh) func loaded_source_stack_1(B[m
started loaded_source_stack_1
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2(B[m
started loaded_source_stack_2
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2 > (mock_root.sh) func loaded_source_stack_3(B[m
started loaded_source_stack_3
finished loaded_source_stack_3 as planned
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_in_loaded_source > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2 < (mock_root.sh) func loaded_source_stack_3(B[m
finished loaded_source_stack_2 as planned
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_in_loaded_source > (mock_root.sh) func loaded_source_stack_1 < (mock_root.sh) func loaded_source_stack_2(B[m
finished loaded_source_stack_1 as planned
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_tasks_chain_in_loaded_source < (mock_root.sh) func loaded_source_stack_1(B[m
👍 [34mdone: (mock_root.sh) func test_tasks_chain_in_loaded_source(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_loaded_source_fails <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails > (mock_root.sh) func loaded_source_stack_1(B[m
started loaded_source_stack_1
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2(B[m
started loaded_source_stack_2
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2 > (mock_root.sh) func loaded_source_stack_3(B[m
started loaded_source_stack_3
💥 [31mat: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2 > (mock_root.sh) func loaded_source_stack_3(B[m
💥 24 from command:
💥 return "$1"
💥 [31mat: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails > (mock_root.sh) func loaded_source_stack_1 > (mock_root.sh) func loaded_source_stack_2(B[m
💥 [31mat: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails > (mock_root.sh) func loaded_source_stack_1(B[m
💥 [31mfailed: (mock_root.sh) func test_tasks_chain_in_loaded_source_fails(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_child <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_tasks_chain_in_child(B[m
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_tasks_chain_in_child > (mock_child.sh) func child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_in_child
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_tasks_chain_in_child > (mock_child.sh) func child_stack_1 > (mock_child.sh) func child_stack_2(B[m
child_stack_2 start
from child_stack_1
child_stack_2 end without err
🏃🏻‍♀️ [34mout: (mock_child.sh) test_tasks_chain_in_child > (mock_child.sh) func child_stack_1 < (mock_child.sh) func child_stack_2(B[m
child_stack_1 end without err
🏃🏻‍♀️ [34mout: (mock_child.sh) test_tasks_chain_in_child < (mock_child.sh) func child_stack_1(B[m
👍 [34mdone: (mock_child.sh) test_tasks_chain_in_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_tasks_chain_in_child_fails <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_tasks_chain_in_child_fails(B[m
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_tasks_chain_in_child_fails > (mock_child.sh) func child_stack_1(B[m
child_stack_1 start
from test_tasks_chain_in_child_fails
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_tasks_chain_in_child_fails > (mock_child.sh) func child_stack_1 > (mock_child.sh) func child_stack_2(B[m
child_stack_2 start
from child_stack_1
💥 [31mat: (mock_child.sh) test_tasks_chain_in_child_fails > (mock_child.sh) func child_stack_1 > (mock_child.sh) func child_stack_2(B[m
💥 7 from command:
💥 return "$1"
💥 [31mat: (mock_child.sh) test_tasks_chain_in_child_fails > (mock_child.sh) func child_stack_1(B[m
💥 [31mfailed: (mock_child.sh) test_tasks_chain_in_child_fails(B[m
💥 7 from command:
💥 test_tasks_chain_in_child_fails
HEREDOC

  assert_mock_root_output_and_err test_root_task_from_child_without_link_fails <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_child.sh) test_root_task_from_child_without_link_fails(B[m
❌ [31m🤔 No task named: 'root_stack_2' in this Xfile or linked children!(B[m
Maybe misspelled?
Try: x help
Call args:
root_stack_2
from test_root_task_from_child_without_link_fails
💥 [31mfailed: (mock_child.sh) test_root_task_from_child_without_link_fails(B[m
💥 8 from command:
💥 test_root_task_from_child_without_link_fails
HEREDOC

  assert_mock_root_output_and_err test_child_cannot_call_child_that_not_linked_directly <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_child_two.sh) test_child_cannot_call_child_that_not_linked_directly(B[m
❌ [31m🤔 No task named: 'child_stack_1' in this Xfile or linked children!(B[m
Maybe misspelled?
Try: x help
Call args:
child_stack_1
from test_child_cannot_call_child_that_not_linked_directly
💥 [31mfailed: (mock_child_two.sh) test_child_cannot_call_child_that_not_linked_directly(B[m
💥 8 from command:
💥 test_child_cannot_call_child_that_not_linked_directly
HEREDOC

  assert_mock_root_output_and_err test_root_task_from_child <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_child_two.sh) test_root_task_from_child(B[m
🏃‍♀️‍➡️ [36min: (mock_child_two.sh) test_root_task_from_child > (mock_root.sh) root_stack_2(B[m
root_stack_2 start
from test_root_task_from_child
root_stack_2 end without err
🏃🏻‍♀️ [34mout: (mock_child_two.sh) test_root_task_from_child < (mock_root.sh) root_stack_2(B[m
👍 [34mdone: (mock_child_two.sh) test_root_task_from_child(B[m
HEREDOC

  assert_mock_root_output_and_err test_failure_after_ignored_process_failure_logging <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_failure_after_ignored_process_failure_logging(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_failure_after_ignored_process_failure_logging > (mock_root.sh) return_code(B[m
💥 [31mat: (mock_root.sh) func test_failure_after_ignored_process_failure_logging > (mock_root.sh) return_code(B[m
💥 88 from command:
💥 return_code '88'
la la la
💥 [31mfailed: (mock_root.sh) func test_failure_after_ignored_process_failure_logging(B[m
💥 1 from command:
💥 false
HEREDOC

  if var_is_true has_problems; then return 3; fi

  log_success "Xfile dispatch works as expected!"
}

# - Note:
# 1) tee may mix up lines, get err and out separately
# 2) tasks inherit streams forwarding, so caller task tail is in the logs of child task
function test_forward_out_and_err_to_dir() { ## Check how streams are being proxied
  local has_problems=false

  assert_mock_root_output test_forward_out_and_err_to_dir <<'HEREDOC'
out 1 in test_forward_out_and_err_to_dir
out in foo
out in bar
out 2 in test_forward_out_and_err_to_dir
HEREDOC

  assert_mock_root_err test_forward_out_and_err_to_dir <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_forward_out_and_err_to_dir(B[m
💁‍♀️ [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir/main
- called inside of 'test_forward_out_and_err_to_dir'
started test_forward_out_and_err_to_dir
in test_forward_out_and_err_to_dir
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar(B[m
in bar
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar > (mock_root.sh) func foo(B[m
💁‍♀️ [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir/foo
- called inside of 'foo'
❗️ [33mRepetitive forwarding of output and error streams in the same shell (script/subshell) – 0.(B[m
Called inside of 'foo'
Will do.
But previous forwarding will remain in effect globally in this shell, fd will be chained like:
tee -> tee -> >1 (process fd)
Consider refactor to 'run_with_status_marker' or subshelling the task that must forward itself

in foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar < (mock_root.sh) func foo(B[m
in bar after foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_forward_out_and_err_to_dir < (mock_root.sh) func bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [34mdone: (mock_root.sh) func test_forward_out_and_err_to_dir(B[m
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
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar(B[m
in bar
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar > (mock_root.sh) func foo(B[m
💁‍♀️ [35mForwarding this shell (script/subshell) output and error streams(B[m
- to: ./output/xfile_tests/forward_out_and_err_to_dir/foo
- called inside of 'foo'
❗️ [33mRepetitive forwarding of output and error streams in the same shell (script/subshell) – 0.(B[m
Called inside of 'foo'
Will do.
But previous forwarding will remain in effect globally in this shell, fd will be chained like:
tee -> tee -> >1 (process fd)
Consider refactor to 'run_with_status_marker' or subshelling the task that must forward itself

in foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar < (mock_root.sh) func foo(B[m
in bar after foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_forward_out_and_err_to_dir < (mock_root.sh) func bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [34mdone: (mock_root.sh) func test_forward_out_and_err_to_dir(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/foo/out.log" <<'HEREDOC'
out in foo
out in bar
out 2 in test_forward_out_and_err_to_dir
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/forward_out_and_err_to_dir/foo/err.log" <<'HEREDOC'
in foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_forward_out_and_err_to_dir > (mock_root.sh) func bar < (mock_root.sh) func foo(B[m
in bar after foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_forward_out_and_err_to_dir < (mock_root.sh) func bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [34mdone: (mock_root.sh) func test_forward_out_and_err_to_dir(B[m
HEREDOC

  if var_is_true has_problems; then return 3; fi

  log_success "forward_out_and_err_to_dir works as expected!"
}

function test_run_with_status_marker() { ## Check how streams are being proxied
  local has_problems=false

  assert_mock_root_output test_run_with_status_marker <<'HEREDOC'
out 1 in test_forward_out_and_err_to_dir
out in foo
out in bar
out 2 in test_forward_out_and_err_to_dir
HEREDOC

  assert_mock_root_err test_run_with_status_marker <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_run_with_status_marker(B[m
started test_forward_out_and_err_to_dir
in test_forward_out_and_err_to_dir
💁‍♀️ [35mForwarding output and error streams:(B[m
- of: task bar
- to: ./output/xfile_tests/test_run_with_status_marker/bar
💁‍♀️ [35mWill create 'success' file in forwarding dir, unless command fails(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar(B[m
in bar
💁‍♀️ [35mForwarding output and error streams:(B[m
- of: task foo
- to: ./output/xfile_tests/test_run_with_status_marker/foo
💁‍♀️ [35mWill create 'success' file in forwarding dir, unless command fails(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar > (mock_root.sh) func foo(B[m
in foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar < (mock_root.sh) func foo(B[m
in bar after foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_run_with_status_marker < (mock_root.sh) func bar(B[m
in test_forward_out_and_err_to_dir after bar
ended test_forward_out_and_err_to_dir
👍 [34mdone: (mock_root.sh) func test_run_with_status_marker(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/bar/out.log" <<'HEREDOC'
out in foo
out in bar
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/bar/err.log" <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar(B[m
in bar
💁‍♀️ [35mForwarding output and error streams:(B[m
- of: task foo
- to: ./output/xfile_tests/test_run_with_status_marker/foo
💁‍♀️ [35mWill create 'success' file in forwarding dir, unless command fails(B[m
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar > (mock_root.sh) func foo(B[m
in foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar < (mock_root.sh) func foo(B[m
in bar after foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_run_with_status_marker < (mock_root.sh) func bar(B[m
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/foo/out.log" <<'HEREDOC'
out in foo
HEREDOC

  assert_cmd_output_and_err cat "$GIT_ROOT/output/xfile_tests/test_run_with_status_marker/foo/err.log" <<'HEREDOC'
🏃‍♀️‍➡️ [36min: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar > (mock_root.sh) func foo(B[m
in foo
🏃🏻‍♀️ [34mout: (mock_root.sh) func test_run_with_status_marker > (mock_root.sh) func bar < (mock_root.sh) func foo(B[m
HEREDOC

  if var_is_true has_problems; then return 3; fi

  log_success "forward_out_and_err_to_dir works as expected!"
}

begin_xfile_task
