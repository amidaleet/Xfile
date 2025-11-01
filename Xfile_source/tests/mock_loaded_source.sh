# shellcheck shell=bash

function test_tasks_chain_in_loaded_source {
  task loaded_source_stack_1 'from test_tasks_chain_in_loaded_source'
}

function test_tasks_chain_in_loaded_source_fails {
  MOCKED_END_CODE=24 task loaded_source_stack_1 'from test_tasks_chain_in_loaded_source_fails'
}

function loaded_source_stack_1 {
  puts "started loaded_source_stack_1"

  task loaded_source_stack_2 'from loaded_source_stack_1'

  puts "finished loaded_source_stack_1 as planned"
}

loaded_source_stack_2() {
  puts "started loaded_source_stack_2"

  task loaded_source_stack_3 'from loaded_source_stack_2'

  puts "finished loaded_source_stack_2 as planned"
}

loaded_source_stack_3() {
  puts "started loaded_source_stack_3"

  if [ -n "$MOCKED_END_CODE" ]; then
    return_code "$MOCKED_END_CODE"
  fi

  puts "finished loaded_source_stack_3 as planned"
}
