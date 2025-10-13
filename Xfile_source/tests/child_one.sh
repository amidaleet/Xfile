#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

function  child_one_task() { ## child_one task
  echo 'child_one_task in child_one'
}

## --one
function two:child_two_task() { ## child_one task that should not override child_two
  echo 'two:child_two_task in child_one'
}

## -a --name
function main() { ## child_one main task
  echo 'main in child_one'
}

begin_xfile_task
