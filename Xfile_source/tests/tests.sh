#!/usr/bin/env bash

source "$GIT_ROOT/Xfile_source/impl.sh"

function test_xfile() { ## Test Xfile implementation (arguments handling)
  local test_logs=(
    "$(task test_var_is_true)"
    "$(task test_assert_defined)"
    "$(task test_args_parsing -l VERSION="42  20" --word 'word' -f -t "Text with  3   words and spaces" BETA_NUMBER='beta')"
    "$(task test_args_parsing -l -f -w 'word' -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20")"
    "$(task test_args_parsing -lf -w 'word' -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20")"
    "$(task test_args_parsing --local --word 'word' --force -t "Text with  3   words and spaces" BETA_NUMBER='beta' VERSION="42  20")"
    "$(task test_args_parsing BETA_NUMBER=beta --local --word 'word' --force --text "Text with  3   words and spaces" VERSION="42  20")"
    "$(task test_read_flags -e -o)"
    "$(task test_read_flags --expected --other)"
    "$(task test_arr_to_str)"
    "$(EXPECTED='first:second' task test_read_arr -a 'first second')"
    "$(EXPECTED='first:second' task test_read_arr -a 'first:second' :)"
    "$(EXPECTED='first:second' task test_read_arr -a 'first second' ' ')"
    "$(EXPECTED='first:second' task test_read_arr -a '  first   second   ' ' ')"
    "$(EXPECTED='first:second' task test_read_arr -a '::first:second:' :)"
    "$(EXPECTED=' first: second' task test_read_arr -a ': first: second:' :)"
    "$(EXPECTED='first:second' task test_read_arr -a $'first\nsecond' '\n')"
    "$(EXPECTED='first:second' task test_read_arr -a $'\nfirst\nsecond\n' '\n')"
    "$(EXPECTED='first  :second  ' task test_read_arr -a $'\nfirst  \nsecond  \n' '\n')"
    "$(task test_xfile_children)"
  )

  local log has_problems

  for log in "${test_logs[@]}"; do
    if [ -z "$log" ]; then continue; fi

    if [ "$has_problems" != true ]; then
      log_error "Xfile test failed with problems:"
    fi
    log "$log"
    has_problems=true
  done

  if var_is_true has_problems; then return 3; fi

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
  fi
  if ! read_flags -e --expected; then
    puts "test_read_flags: Failed to read --expected flag!"
  fi

  if var_is_true has_problems; then return 3; fi

  log_success "Flags parsed as expected!"
}

test_read_arr() {
  local expected_arr idx
  IFS=':' read -a expected_arr <<<"$EXPECTED"

  read_arr -a myarray "$3"

  local has_problems=false
  if [ ! "${#myarray[@]}" -eq "${#expected_arr[@]}" ]; then
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

  assert_output() {
    local out expected

    out=$("$@")
    if test ! -t 0; then
      expected=$(cat)
    else
      expected=''
    fi

    if [ "$out" != "$expected" ]; then
      puts "Failed call:" "$(arr_to_str ' ' "$@")" "output:" "$out"
      has_problems=true
    fi
  }

  assert_output arr_to_str : one two three <<<'one:two:three'
  assert_output arr_to_str ' ' one-1 two-2 three-3 <<<'one-1 two-2 three-3'

  unset assert_output

  if var_is_true has_problems; then return 3; fi

  log_success "arr_to_str works!"
}

function test_xfile_children() { ## Check how tasks dispatch after link_child_xfile
  local has_problems=false

  assert_output() {
    local out expected

    out=$("$GIT_ROOT/Xfile_source/tests/link_root.sh" "$@")
    if test ! -t 0; then
      expected=$(cat)
    else
      expected=''
    fi

    if [ "$out" != "$expected" ]; then
      puts "Failed call:" "$(arr_to_str ' ' "$@")" \
        "$(color_str 5 output:)" "$out" \
        "$(color_str 5 diff:)" "$(diff <(echo "$out") <(echo "$expected"))"
      has_problems=true
    fi
  }

  assert_output main <<<'main in child_zero'
  assert_output link_root_task <<<'link_root_task in link_root'
  assert_output one:child_one_task <<<'child_one_task in child_one'
  assert_output two:child_two_task <<<'child_two_task in child_two'
  assert_output one:main <<<'main in child_one'
  assert_output task_args two:child_two_task <<<'--two'
  assert_output task_args main <<<'--something -v'
  assert_output task_args one:main <<<'-a --name'
  assert_output task_args two:main <<<''
  assert_output task_names <<'HEREDOC'
link_root_task
main
one:two:child_two_task
one:main
two:child_two_task
two:main
HEREDOC
  assert_output show_tasks <<'HEREDOC'
[34m# Xfile_source/tests/link_root.sh tasks:(B[m
  [93mlink_root_task                                [92m   link_root task[0m

[34m# Xfile_source/tests/child_zero.sh tasks:(B[m
  [93mmain                                          [92m   child_zero main task[0m

[34m# Xfile_source/tests/child_one.sh tasks:(B[m
  [93mone:two:child_two_task                        [92m   child_one task that should not override child_two[0m
  [93mone:main                                      [92m   child_one main task[0m

[34m# Xfile_source/tests/child_two.sh tasks:(B[m
  [93mtwo:child_two_task                            [92m   child_two task[0m
  [93mtwo:main                                      [92m   child_two main task[0m
HEREDOC
  unset assert_output

  if var_is_true has_problems; then return 3; fi

  log_success "Xfile children links works as expected!"
}

begin_xfile_task
