#!/usr/bin/env bash
set -eo pipefail

XFILE_REF=${XFILE_REF:-main}

load_scripts() {
  local s file

  for s in "$@"; do
    file="Xfile_source/$s.sh"
    echo "Loading $file" 1>&2

    curl \
      -fsSL "https://raw.githubusercontent.com/amidaleet/Xfile/$XFILE_REF/$file" \
      -o "$file" \
    && chmod +x "$file" \
    &
  done
  wait
}

init_xfile_from_repo() {
  echo "Will install Xfile from ref $XFILE_REF to dir $PWD" 1>&2

  rm -rf Xfile_source
  mkdir -p Xfile_source/tests

  load_scripts xlib impl template completion \
    tests/tests \
    tests/link_root \
    tests/child_zero tests/child_one  tests/child_two

  if [ ! -f ./Xfile ]; then
    echo "Will add Xfile template, as ./Xfile is missing" 1>&2
    cp ./Xfile_source/template.sh ./Xfile
  fi

  echo "Installed Xfile!" 1>&2
}

init_xfile_from_repo
