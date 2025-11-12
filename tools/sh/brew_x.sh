#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

link_child_xfile "$GIT_ROOT/Xfile"

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

function brew:install_brew_native {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

function brew:install_brew_x86_64 {
  arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

# ---------- Deps ----------

## --upgrade
function brew:install_deps {
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

function brew:repack_installed_deps { ## zip deps from brew (semi-portable archive)
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
    dep_cellar_dir=${line% (*}
    deps_cellar_dirs+=("$dep_cellar_dir")
  done < <(brew info "${repo_deps[@]}" | grep '/Cellar/')

  log_info "Resolved deps dirs for packing:" \
    "${deps_cellar_dirs[@]}"

  log_info "Deps and dirs count:" \
    "Total deps: ${#repo_deps[@]} | Total dirs: ${#deps_cellar_dirs[@]}"
  log_note 'deps may share dir sometimes!'

  brew_bins_dir=$(which brew)
  brew_bins_dir=${brew_bins_dir%/*}
  brew_root=${brew_bins_dir%/*}
  log_info 'Resolved brew bins dir:' \
    "$brew_bins_dir"

  log_next "Resolving needed bin dir symlinks list..."
  for symlink in "$brew_bins_dir"/*; do
    real_bin_path=$(realpath "$symlink")

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
    real_bin_path=$(realpath "$symlink")

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
    real_bin_path=$(realpath "$symlink")

    for dir in "${deps_cellar_dirs[@]}"; do
      if [[ "$real_bin_path" == "$dir"* ]]; then
        deps_lib_symlinks+=("$symlink")
        break
      fi
    done
  done
  log_info 'Resolved lib dir symlinks for packing:' \
    "${deps_lib_symlinks[@]}"

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

  pushd "$brew_root" >&2
  # -y means store symlinks in ./bin, not resolved files
  zip -qyr "$zip_path" "${path_to_pack[@]}"
  popd >&2

  log_success '✅ Repack archive is ready at:' \
    "$zip_path"
}

function remap_dylib_to_utils_dir { ## переписать пути до библиотек с /opt/homebrew до DX_SHELL_UTILS_DIR
  local file file_extension

  log_info "dx_utils dir:" "$DX_SHELL_UTILS_DIR"

  log_next "Searching for executables in dx_utils..."
  while read -r file; do
    file_name=${file##*/}
    file_extension=${file_name##*.}

    if value_in_list "$file_extension" 'sh' 'py' 'js' 'rb' 'perl' 'pl' 'cgi' 'sample'; then continue; fi
    if [ ! -x "$file" ] && ! value_in_list "$file_extension" 'dylib' 'a' 'so'; then continue; fi

    task map_dylibs_in_file "$file"
  done < <(find "$DX_SHELL_UTILS_DIR" -type f)

  log_success "Remapped all dx_utils!"
}

map_dylibs_in_file() {
  local file file_name lib_id lib_dep_path new_lib_dep_path needs_codesign
  file=$1
  needs_codesign=false

  log_next "Mapping file..." "$file"

  lib_id=$(otool -D "$file" | grep '/opt/homebrew' || true)
  if [ -n "$lib_id" ]; then
    needs_codesign=true
    lib_id="$DX_SHELL_UTILS_DIR/${lib_id##/opt/homebrew/}"

    log_next "Spotted shared dylib:" \
      "- at: $file"

    log_next "changing identification name of shared dylib..."
    install_name_tool -id "$lib_id" "$file"
  fi

  while read -r lib_dep_path; do
    needs_codesign=true
    new_lib_dep_path="$DX_SHELL_UTILS_DIR/${lib_dep_path##/opt/homebrew/}"

    log_next "Spotted dylib dep to re-link:" \
      "- at: $file" \
      "- from: $lib_dep_path" \
      "- to: $new_lib_dep_path"

    log_next "Re-linking dep dylib..."
    install_name_tool -change "$lib_dep_path" "$new_lib_dep_path" "$file"
  done < <(otool -L "$file" | grep '/opt/homebrew' | sed -E 's/[[:space:]]*\(.*$//' | sed -E 's/^[[:space:]]+//' || true)

  if [ "$needs_codesign" = true ]; then
    codesign --force --sign - --timestamp=none "$file"
  fi
}

begin_xfile_task
