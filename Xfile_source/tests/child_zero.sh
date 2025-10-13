#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

## --something -v
function main() { ## child_zero main task
  echo "main in child_zero"
}

begin_xfile_task
