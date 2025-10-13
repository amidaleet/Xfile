#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

top_level_deps=(
  bash       # Берем свежую версию, системная отстает (3 мажор, актуалка 5)
  git        # Берем свежую версию, системная отстает
  git-lfs    # Для хранения больших файлов вне git истории (картинки)
  coreutils  # bash утилиты (н-р timeout)
  yq         # YAML formatter и парсер
  watchman   # Hot Reloading React Native
  rbenv      # Менеджер версий ruby
  chruby     # Менеджер для смены активной версии ruby
  bison gmp libffi libyaml openssl readline zlib # ruby build requiments
  node n npm # менеджеры зависимостей для работы с node и JS
  pyenv      # Менеджер версий python
  aria2      # Многопоточная загрузка файлов
  xcbeautify # Форматтер логов xcodebuild команд
  mint       # Менеджер зависимостей Swift (Packages)
  carthage   # Менеджер iOS framework
)

# ---------- Brew setup ----------

function install_brew_arm() {
  /bin/bash -c "$(curl -fsS https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

function install_brew_x86_64() {
  arch -x86_64 /bin/bash -c "$(curl -fsS https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

# ---------- Deps ----------

## --upgrade
function install_deps { ## install repository deps from homebrew (CLI tools and dylibs)
  if ! read_flags --upgrade; then
    export HOMEBREW_NO_INSTALL_UPGRADE=true
    export HOMEBREW_NO_AUTO_UPDATE=true
  fi

  log_info "Install Homebrew dependencies:" \
    "${top_level_deps[@]}"
  log_info 'Error: & Warning: in log are expected for already installed deps'

  brew install "${top_level_deps[@]}"
  log_success "brew install complete!"
}

function repack_installed_deps { ## pack installed repository brew deps to .zip
  local brew_bins_dir
  local required_deps_str
  local repo_deps=()
  local deps_cellar_dirs=()
  local deps_opt_symlinks=()
  local deps_lib_symlinks=()
  local deps_symlinks=()
  local path_to_pack=()

  log_next "Resolving repo deps list..."

  for dep in "${top_level_deps[@]}"; do
    repo_deps+=("$dep")
  done

  required_deps_str=$(brew deps --union "${top_level_deps[@]}")

  for dep in $required_deps_str; do
    repo_deps+=("$dep")
  done

  eval 'repo_deps=('$(printf "%q\n" "${repo_deps[@]}" | sort -u)')'

  log_info "Resolved all required deps list:" \
    "${repo_deps[@]}"

  log_next "Asking brew for deps path..."

  while read -r line; do
    dep_cellar_dir="${line% (*}"
    deps_cellar_dirs+=("$dep_cellar_dir")
  done < <(brew info "${repo_deps[@]}" | grep '/Cellar/')

  log_info "Resolved deps dirs for packing:" \
    "${deps_cellar_dirs[@]}"

  log_info "Deps and dirs count:" \
    "Total deps: ${#repo_deps[@]} | Total dirs: ${#deps_cellar_dirs[@]}" \
    '- Note: deps may share dir sometimes!'

  brew_bins_dir="$(which brew)"
  brew_bins_dir="${brew_bins_dir%/*}"
  brew_root="${brew_bins_dir%/*}"
  log_info 'Resolved brew bins dir:' \
    "$brew_bins_dir"

  log_next "Resolving needed bin dir symlinks list..."
  for symlink in "$brew_bins_dir"/*; do
    real_bin_path="$(realpath "$symlink")"

    for dir in "${deps_cellar_dirs[@]}"; do
      if [[ "$real_bin_path" == "$dir"* ]]; then
        deps_symlinks+=("$symlink")
        break
      fi
    done
  done
  log_info 'Resolved bin dir symlinks for packing:' \
    "${deps_symlinks[@]}"

  log_next "Resolving needed opt dir symlinks list..."
  for symlink in "$brew_root/opt"/*; do
    real_bin_path="$(realpath "$symlink")"

    for dir in "${deps_cellar_dirs[@]}"; do
      if [[ "$real_bin_path" == "$dir"* ]]; then
        deps_opt_symlinks+=("$symlink")
        break
      fi
    done
  done
  log_info 'Resolved opt dir symlinks for packing:' \
    "${deps_opt_symlinks[@]}"

  log_next "Resolving needed lib dir symlinks list..."
  for symlink in "$brew_root/lib"/*; do
    real_bin_path="$(realpath "$symlink")"

    for dir in "${deps_cellar_dirs[@]}"; do
      if [[ "$real_bin_path" == "$dir"* ]]; then
        deps_lib_symlinks+=("$symlink")
        break
      fi
    done
  done
  log_info 'Resolved lib dir symlinks for packing:'
  log "${deps_lib_symlinks[@]}"

  log_next "Resolving special cases..."
  for dep in "${repo_deps[@]}"; do
    if [ "$dep" = 'npm' ]; then
      # У npm нет своего Cellar, он размещается внутри node и требует lib/node_modules
      deps_symlinks+=("$brew_bins_dir/npm")
      deps_lib_symlinks+=("$brew_root/lib/node_modules")
      log "Added npm as special case"
    fi
  done

  # We must provide relative path in order to eliminate parent absolute folders
  # zip resolves path relative to workdir
  log_next 'Resolving final path list for zip...'

  for dir in "${deps_cellar_dirs[@]}" "${deps_symlinks[@]}" "${deps_opt_symlinks[@]}" "${deps_lib_symlinks[@]}"; do
    path_to_pack+=("$(grealpath -s --relative-to="$brew_root" "$dir")")
  done

  log_next 'Resolved final path list for zip:' \
    "${path_to_pack[@]}"

  log_next 'Zipping deps to repack...'

  local mac_arch
  case "$brew_root" in
  /opt/homebrew)
    mac_arch="arm64"
    ;;
  /usr/local)
    mac_arch="x86_64"
    ;;
  *)
    log_error "Unable to guess brew arch! Unexpected brew dir: $brew_root"
    return 78
    ;;
  esac

  local zip_path="$GIT_ROOT/output/bin_repack_${mac_arch}.zip"

  cd "$brew_root"
  # -y means store symlinks in ./bin, not resolved files
  zip -qyr "$zip_path" "${path_to_pack[@]}"
  cd -

  log_success '✅ Repack archive is ready!' \
    "$zip_path"
}

begin_xfile_task
