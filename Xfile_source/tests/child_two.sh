#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

## --two
function child_two_task() { ## child_two task
  echo 'child_two_task in child_two'
}

function main() { ## child_two main task
  echo 'main in child_two'
}

begin_xfile_task
