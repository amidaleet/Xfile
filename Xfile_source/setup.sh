#!/usr/bin/env bash

set -eo pipefail

rm -rf Xfile_source
mkdir -p Xfile_source

function load_script {
  curl \
    -s "https://raw.githubusercontent.com/amidaleet/Xfile/HEAD/Xfile_source/$1.sh" \
    -o "Xfile_source/$1.sh"
  chmod +x "Xfile_source/$1.sh"
}

load_script xlib
load_script impl
load_script completion

export GIT_ROOT="$(realpath .)"

source Xfile_source/impl.sh

impl:write_xfile_template './Xfile'
