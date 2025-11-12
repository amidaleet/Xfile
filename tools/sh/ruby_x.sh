# shellcheck shell=bash

if false; then # Shall not run, it just enables shellcheck impl.sh visibility
  # shellcheck source=./Xfile_source/impl.sh
  source "$GIT_ROOT/Xfile_source/impl.sh"
fi

function get_ruby_repository_version {
  cat "$GIT_ROOT/.ruby-version"
}

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

  pushd "$DX_DIR/packs/bin" >&2
  rm -f chruby-init chruby-exec
  ln -s "../Cellar/chruby/chruby-init" chruby-init
  ln -s "../Cellar/chruby/chruby-exec" chruby-exec
  popd >&2

  if [ "$DX_DIR_unexported" = true ]; then
    log_warn "(Must have) To enable installed commands calls from Terminal" "Put to ~/.zprofile for ZSH (OR ~/.bash_profile for BASH):" \
      "export DX_DIR=\"\$HOME/Development/DX\"" \
      "export PATH=\"\$DX_DIR/packs/bin:\$PATH\"" \
      ''
  fi
  log_info "(Recommended) To enable chruby in Terminal and pick ruby version" "Put to ~/.zprofile for ZSH (OR ~/.bash_profile for BASH):" \
    "eval \"\$(chruby-init core)\"" "chruby $(get_ruby_repository_version)" \
    ''
  log_info "(Optionally) To enable auto ruby switch in any dir" "Put next code to ~/.zshrc for ZSH (OR ~/.bashrc for BASH):" \
    "eval \"\$(chruby-init auto)\"" \
    ''
  log_success "Installed chruby-init to $DX_DIR/packs/bin"
}

chruby_activate_repository_version() { ## Fill ENV with current ruby version
  if command -v chruby >/dev/null; then
    log "chruby func is present, won't source it again"
  else
    log "Sourcing chruby from repo..."
    source "$TOOLS_DIR/sh/chruby/chruby.sh"
  fi

  local ruby_version=$(get_ruby_repository_version)
  log_info "Setting ruby $ruby_version"
  chruby "$ruby_version"
}

function fastlane { ## Выполнить fastlane lane / action
  ruby_bundle exec fastlane "$@"
}

function cocoapods { ## Выполнить pods команду
  ruby_bundle exec pod "$@"
}

function ruby_run { ## Выполнить ruby команду в контексте репозиторного bundle
  ruby_bundle exec ruby "$@"
}

function ruby_bundle { ## Выполнить bundle команду
  chruby_activate_repository_version
  bundle "$@"
}

function gems_install_bundle {
  chruby_activate_repository_version

  local BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" "$GIT_ROOT/Gemfile.lock" | grep -oE "[0-9]+.[0-9]+.[0-9]+")

  if gem list --installed bundler --version "$BUNDLER_VERSION" >/dev/null; then
    log "Bundler $BUNDLER_VERSION is already installed"
    return
  fi

  gem install bundler --version "$BUNDLER_VERSION" --config-file "$GIT_ROOT/.gemrc"
}

## --skip-existing
function ruby_bundle_reset_config { ## Затереть локальный (ruby) bundle конфиг стандартными значениями
  if read_flags --skip-existing && [ -f "$GIT_ROOT/.bundle/config" ]; then
    log_warn "Won't reset ruby bundle config, it is already exist" "Skipping..."
    return
  fi

  mkdir -p "$GIT_ROOT/.bundle"
  {
    echo '---'
    echo 'BUNDLE_RETRY: "3"'
    echo 'BUNDLE_JOBS: "4"'
    echo 'BUNDLE_FROZEN: "true"'
  } > "$GIT_ROOT/.bundle/config"

  log "Has set bundle config to:"
  cat "$GIT_ROOT/.bundle/config"
}

## xcode:fastlane:code:test
function gems_exclude_groups { ## Установить перечень групп gems из Gemfile в локальный конфиг ($1 is ' ' or ':' -separated str)
  local groups=$1

  if [ -z "$groups" ]; then
    log "Will unset BUNDLE_WITHOUT, no exceptions passed"
    ruby_bundle config unset --local without
  else
    log "Will set BUNDLE_WITHOUT to: $groups"
    ruby_bundle config set --local without "$groups"
  fi
}

function gems_freeze { ## запретить изменения Gemfile.lock (смена списка/версий gems)
  ruby_bundle config set --local frozen true
}

function gems_defrost { ## разблокировать Gemfile.lock (смена списка/версий gems)
  ruby_bundle config set --local frozen false
}

function gems_update { ## зарезолвить и обновить зависимости в Gemfile.lock
  ruby_bundle update -V
}

function gems_install { ## установить зависимости из Gemfile (ruby) и Pluginfile (fastlane)
  ruby_bundle install -V
}

## --version --force-reinstall --from-ruby-org
function ruby_lang_installer {
  local caller_dir=$PWD
  local ruby_version short_ruby_version target_dir sources_dir

  read_opt --version ruby_version
  assert_defined ruby_version

  short_ruby_version=${ruby_version%.*}
  target_dir="$HOME/.rubies/${ruby_version}"

  log_info "Requested ruby: $ruby_version"

  if ! read_flags --force-reinstall; then
    if [ -x "$target_dir/bin/ruby" ]; then
      log_warn "Ruby seems to be already present at chruby folder:" \
        "$target_dir" \
        "Aborting..."
      return
    fi
    if [ -x "$HOME/.rbenv/versions/$ruby_version/bin/ruby" ]; then
      log_warn "Ruby seems to be already present at rbenv folder:" \
        "$target_dir" \
        "Aborting..."
      return
    fi
  fi

  mkdir -p "$OUTPUT_DIR"
  cd "$OUTPUT_DIR"

  sources_dir="ruby-${ruby_version}"
  log_info "Loading ruby to: $OUTPUT_DIR/$sources_dir"
  rm -rf "$sources_dir"

  curl "https://cache.ruby-lang.org/pub/ruby/${short_ruby_version}/ruby-${ruby_version}.tar.xz" -o "ruby-${ruby_version}.tar.xz"
  tar -xf "ruby-${ruby_version}.tar.xz"

  log_info "Resolving dylib dirs..."
  local gmp_path libyaml_path openssl_path readline_path zlib_path

  if command -v brew >/dev/null; then
    log "Using lib dirs from brew"
  else
    log_error "No brew to link dylibs!"
    return 23
    gmp_path=$(brew --prefix gmp)
    libyaml_path=$(brew --prefix libyaml)
    openssl_path=$(brew --prefix openssl)
    readline_path=$(brew --prefix readline)
    zlib_path=$(brew --prefix zlib)
  fi
  log "Resolved dylib dirs:" "$gmp_path" "$libyaml_path" "$openssl_path" "$readline_path" "$zlib_path"

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

  log_success "ruby has been installed at:" \
    "$target_dir"
  cd "$caller_dir"
}
