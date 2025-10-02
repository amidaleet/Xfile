#!/usr/bin/env bash

set -eo pipefail

XFILE_REF=${XFILE_REF:-5.0.0}

load_scripts() {
  for s in "$@"; do
    curl \
      -fsS "https://raw.githubusercontent.com/amidaleet/Xfile/$XFILE_REF/Xfile_source/$s.sh" \
      -o "Xfile_source/$s.sh"
    chmod +x "Xfile_source/$s.sh"
  done
}

write_xfile_template() {
  cat <<'HEREDOC' >"$1"
#!/usr/bin/env bash

set -eo pipefail

export GIT_ROOT="${GIT_ROOT:-"$(realpath .)"}"

source "$GIT_ROOT/Xfile_source/impl.sh"

begin_xfile_task
HEREDOC
  chmod +x "$1"
}

init_xfile_from_repo() {
  echo "Will install Xfile from ref $XFILE_REF to dir $PWD" 1>&2

  rm -rf Xfile_source
  mkdir -p Xfile_source

  load_scripts xlib impl tests completion
  if [ ! -f ./Xfile ]; then
    echo "Will add Xfile template, as ./Xfile is missing"
    write_xfile_template ./Xfile
  fi

  echo "Installed Xfile!" 1>&2
}

init_xfile_from_repo
