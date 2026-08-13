#!/usr/bin/env bash

set -eo pipefail

export GIT_ROOT=${GIT_ROOT:-"${PWD:-"$(pwd)"}"}

source "$GIT_ROOT/Xfile_source/impl.sh"

link_child_xfile "$GIT_ROOT/Xfile_source/tests/tests.sh" '' test_xfile

begin_xfile_task
