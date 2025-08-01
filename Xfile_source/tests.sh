#!/usr/bin/env bash

function test_xfile { ## Test Xfile implementation (arguments handling)
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
    "$(task test_read_arr -a 'first second')"
    "$(task test_read_arr -a 'first:second' :)"
    "$(task test_read_arr -a 'first second' ' ')"
    "$(task test_read_arr -a $'first\nsecond' '\n')"
    "$(task test_read_arr -a '  first   second   ' ' ')"
    "$(task test_read_arr -a '::first:second:' :)"
    "$(task test_read_arr -a $'\nfirst\nsecond\n' '\n')"
    "$(task test_task_in_context --text "two words" -f VERSION="42  20")"
    "$(task test_task_in_context VERSION="42  20" -t "two words" --force)"
  )

  log "${test_logs[@]}"

  local log
  for log in "${test_logs[@]}"; do
    if [[ "$log" == *'❌'* ]]; then
      log_warn "Some Xfile tests has failed, see log above ^^^"
      return 3
    fi
  done

  log_success "Xfile test succeeded!"
}

function test_var_is_true {
  local has_problems=false

  assert_bool() {
    # shellcheck disable=SC2034
    local FT_TEST=$1
    if var_is_true FT_TEST; then
      if [ "$2" != true ]; then
        log_error "'$1' should be treated as false"
        has_problems=true
      fi
    elif [ "$2" != false ]; then
      log_error "'$1' should be treated as true"
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

  if [ "$has_problems" = true ]; then
    return 3
  fi
  log_success "var_is_true works as expected!"
}

function test_assert_defined {
  local value_one=1
  local value_two=work
  local has_problems=false

  if ! assert_defined value_one value_two >/dev/null; then
    log_error "Assert is triggered on existing values!"
    has_problems=true
  fi
  if assert_defined not_present_value >/dev/null; then
    log_error "Assert is not triggered on non-existing values!"
    has_problems=true
  fi

  if var_is_true has_problems; then
    return 3
  fi
  log_success "assert_defined works as expected!"
}

function test_args_parsing {
  read_opt -w --word WORD
  read_opt -t --text TEXT
  read_args VERSION BETA_NUMBER

  local has_problems=false

  if ! read_flags --force -f; then
    log_error "Missing expected --force -f flag!"
    has_problems=true
  fi

  if ! read_flags --local -l; then
    log_error "Missing expected --local -l flag!"
    has_problems=true
  fi

  if read_flags --missing; then
    log_error "Unexpected --missing flag resolved to true!"
    has_problems=true
  fi

  if [ "$WORD" != "word" ]; then
    log_error "$WORD != word"
    has_problems=true
  fi

  if [ "$TEXT" != "Text with  3   words and spaces" ]; then
    log_error "$TEXT != Text with  3   words and spaces"
    has_problems=true
  fi

  if [ "$VERSION" != "42  20" ]; then
    log_error "$VERSION != 42  20"
    has_problems=true
  fi

  if [ "$BETA_NUMBER" != "beta" ]; then
    log_error "$BETA_NUMBER != beta"
    has_problems=true
  fi

  if var_is_true has_problems; then
    return 3
  fi

  log_success "Args parsed as expected!"
}
function test_read_flags {
  local has_problems=false

  if read_flags -m --missing; then
    log_error "Got unexpected --missing flag!"
  fi
  if ! read_flags -e --expected; then
    log_error "Failed to read --expected flag!"
  fi

  if var_is_true has_problems; then
    return 3
  fi
  log_success "Flags parsed as expected!"
}

function test_read_arr {
  read_arr -a myarray "$3"

  local has_problems=false
  if [ ! "${#myarray[@]}" -eq 2 ]; then
    log_error "Got ${#myarray[@]} elements instead of 2. Delimiter is $3"
    has_problems=true
  fi
  if [ "${myarray[0]}" != first ]; then
    log_error "Missing first array element! Delimiter is $3"
    has_problems=true
  fi
  if [ "${myarray[1]}" != second ]; then
    log_error "Missing second array element! Delimiter is $3"
    has_problems=true
  fi

  if var_is_true has_problems; then
    return 3
  fi
  log_success "Array parsed as expected!"
}

function test_task_in_context {
  task_in_context __task_in_context
}

function __task_in_context {
  read_opt -t --text TEXT
  read_args VERSION

  local has_problems=false

  if ! read_flags --force -f; then
    log_error "Missing expected --force -f flag!"
    has_problems=true
  fi

  if [ "$VERSION" != "42  20" ]; then
    log_error "$VERSION != 42  20"
    has_problems=true
  fi

  if [ "$TEXT" != "two words" ]; then
    log_error "$TEXT != two words"
    has_problems=true
  fi

  if var_is_true has_problems; then
    return 3
  fi

  log_success "Args parsed as expected!"
}
