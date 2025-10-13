#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

function install_chruby {
  local DX_DIR_unexported=false
  if [ -z "$DX_DIR" ]; then
    DX_DIR_unexported=true
    export DX_DIR="$HOME/Development/DX"
  fi


  mkdir -p "$DX_DIR/packs/Cellar/chruby"
  rm -rf "$DX_DIR/packs/Cellar/chruby"
  cp -rf "$GIT_ROOT/tools/sh/chruby" "$DX_DIR/packs/Cellar"

  mkdir -p "$DX_DIR/packs/bin"
  cd "$DX_DIR/packs/bin"
  rm -f chruby-init chruby-exec
  ln -s "../Cellar/chruby/chruby-init" chruby-init
  ln -s "../Cellar/chruby/chruby-exec" chruby-exec

  cd "$GIT_ROOT"

  log_success "Installed chruby-init to $DX_DIR/packs/bin"
  log
  if [ "$DX_DIR_unexported" = true ]; then
    log_warn "(Must have) To enable installed commands calls from Terminal" "Put to ~/.zprofile for ZSH (OR ~/.bash_profile for BASH):" \
      "export DX_DIR=\"\$HOME/Development/DX\"" \
      "export PATH=\"\$DX_DIR/packs/bin:\$PATH\"" \
      ''
  fi
  log_info "(Recomended) To enable chruby in Terminal and pick ruby version" "Put to ~/.zprofile for ZSH (OR ~/.bash_profile for BASH):" \
    "eval \"\$(chruby-init core)\"" "chruby $(get_ruby_repository_version)" \
    ''
  log_info "(Optionaly) To enable auto ruby switch in any dir" "Put next code to ~/.zshrc for ZSH (OR ~/.bashrc for BASH):" \
    "eval \"\$(chruby-init auto)\""
}

function get_ruby_repository_version {
  cat "$GIT_ROOT/.ruby-version"
}

chruby_activate_repository_version() { ## Fill ENV with current ruby version
  if ! command -v chruby >/dev/null; then
    log "No chruby command in script scope, will source chruby.sh from repo"
    source "$GIT_ROOT/tools/sh/chruby/chruby.sh"
  fi

  local ruby_version="$(get_ruby_repository_version)"
  log_info "Setting ruby $ruby_version"
  chruby "$ruby_version"
}

function fastlane { ## run fastlane lane / action
  ruby_bundle exec fastlane "$@"
}

function cocoapods { ## run pods cmd
  ruby_bundle exec pod "$@"
}

function ruby_run { ## run ruby cmd in repository bundle context
  ruby_bundle exec ruby "$@"
}

function ruby_bundle { ## run bundle cmd
  chruby_activate_repository_version
  bundle "$@"
}

function gems_install_bundle {
  local BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" "$GIT_ROOT/Gemfile.lock" | grep -oE "[0-9]+.[0-9]+.[0-9]+")

  if gem list --installed bundler --version "$BUNDLER_VERSION" >/dev/null; then
    log "Bundler $BUNDLER_VERSION is already installed"
    return
  fi

  gem install bundler --version "$BUNDLER_VERSION" --config-file "$GIT_ROOT/.gemrc"
}

function gems_freeze { ## Forbid changes in Gemfile.lock
  ruby_bundle config set --local frozen true
}

function gems_defrost { ## Allow changes in Gemfile.lock
  ruby_bundle config set --local frozen false
}

function gems_update { ## Update gems and Gemfile.lock
  ruby_bundle update
}

function gems_install { ## Setup locked gems from Gemfile.lock
  ruby_bundle install
}

## --version --skip-existing
function ruby_lang_installer {
  local ruby_version short_ruby_version target_dir sources_dir

  read_opt --version ruby_version
  assert_defined ruby_version

  short_ruby_version="${ruby_version%.*}"
  target_dir="$HOME/.rubies/${ruby_version}"

  log_info "Resolved versions:"
  log "$ruby_version" "$short_ruby_version"

  if read_flags --skip-existing; then
    if [ -x "$target_dir/bin/ruby" ]; then
      log_warn "Ruby seems to be already present at chruby folder:"
      log "$target_dir"
      log "Aborting..."
      return
    fi
    if [ -x "$HOME/.rbenv/versions/$ruby_version/bin/ruby" ]; then
      log_warn "Ruby seems to be already present at rbenv folder:"
      log "$target_dir"
      log "Aborting..."
      return
    fi
  fi

  mkdir -p "$OUTPUT_DIR"
  cd "$OUTPUT_DIR"

  sources_dir="ruby-${ruby_version}"
  log_info "Loading ruby to: $OUTPUT_DIR/$sources_dir"
  rm -rf "$sources_dir"
  curl "https://cache.ruby-lang.org/pub/ruby/${short_ruby_version}/ruby-${ruby_version}.tar.xz" | tar -x

  log_info "Resolving lib dirs..."
  local gmp_path libyaml_path openssl_path readline_path zlib_path

  if command -v brew >/dev/null; then
    log "Using lib dirs from brew:"
    gmp_path="$(brew --prefix gmp)"
    libyaml_path="$(brew --prefix libyaml)"
    openssl_path="$(brew --prefix openssl)"
    readline_path="$(brew --prefix readline)"
    zlib_path="$(brew --prefix zlib)"
  elif [ -d "$DX_SHELL_UTILS_DIR" ]; then
    log "Using lib dirs from dx_utils: $DX_SHELL_UTILS_DIR"
    gmp_path="$DX_SHELL_UTILS_DIR/opt/gmp"
    libyaml_path="$DX_SHELL_UTILS_DIR/opt/libyaml"
    openssl_path="$DX_SHELL_UTILS_DIR/opt/openssl"
    readline_path="$DX_SHELL_UTILS_DIR/opt/readline"
    zlib_path="$DX_SHELL_UTILS_DIR/opt/zlib"
  fi
  log_info "Resolved lib dirs:" "$gmp_path" "$libyaml_path" "$openssl_path" "$readline_path" "$zlib_path"

  log_info "Compiling ruby..."
  # script source: https://github.com/postmodern/chruby/wiki/Ruby
  cd "$sources_dir"
  ./configure \
    --prefix="$target_dir" \
    --with-gmp-dir="$gmp_path" \
    --with-libyaml-dir="$libyaml_path" \
    --with-openssl-dir="$openssl_path" \
    --with-readline-dir="$readline_path" \
    --with-zlib-dir="$zlib_path"
  make
  make install
}

begin_xfile_task
