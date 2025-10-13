#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

# Idea source: https://blog.kulman.sk/faster-way-to-download-and-install-xcode/
## --version --start_step --beta_number --apple-silicon --universal --apps_dir --cookie
function install { ## Load and install Xcode.app of specified version
  read_opt --version XCODE_VERSION
  read_opt --beta_number BETA_NUMBER
  read_opt --cookie COOKIE
  read_opt --start_step start_step
  read_opt --apps_dir APPS_DIR

  assert_defined XCODE_VERSION COOKIE

  export APPS_DIR=${APPS_DIR:-'/Applications'}
  if [ ! -d "$APPS_DIR" ]; then
    mkdir -p "$APPS_DIR"
  fi

  if read_flags --apple-silicon; then
    XCODE_ARCH='Apple_silicon'
  elif read_flags --universal; then
    XCODE_ARCH='Universal'
  fi

  case "$BETA_NUMBER" in
  '')  APP_NAME='Xcode.app' ;;
  0|1) APP_NAME='Xcode-beta.app'; XCODE_VERSION="${XCODE_VERSION}_beta" ;;
  *)   APP_NAME='Xcode-beta.app'; XCODE_VERSION="${XCODE_VERSION}_beta_${BETA_NUMBER}" ;;
  esac

  XIP_NAME="Xcode_${XCODE_VERSION}${XCODE_ARCH:+"_$XCODE_ARCH"}.xip"
  TARGET_APP_NAME="Xcode-${XCODE_VERSION}.app"

  export XCODE_VERSION XIP_NAME APP_NAME TARGET_APP_NAME COOKIE

  log_info "🎫 Params are:"
  log "XCODE_VERSION = $XCODE_VERSION" "XIP_NAME = $XIP_NAME" "APP_NAME = $APP_NAME" "TARGET_APP_NAME = $TARGET_APP_NAME" "APPS_DIR = $APPS_DIR"

  # - Important: шаги запускаются как функции в том же scope, а не как отдельные task
  local script_steps=(
    load
    move_archive
    unpack
    rename_app
    remove_archive
    activate
  )
  local idx=0
  log_info 'Script steps:'
  for step in ${script_steps[@]}; do
    log "$idx – $step"
    idx=$(( idx+1 ))
  done

  local start_step=${start_step:-0}
  log_info "Will start from step: $start_step"

  mkdir -p output
  for step in ${script_steps[@]:$start_step}; do
    log_info "Step: $step"
    task "$step"
  done

  log_success "Installed Xcode $XCODE_VERSION"
}

load() {
  if [ -z "$(command -v aria2c)" ]; then
    log_error "Missing aria2c utility, to setup: brew install aria2"
    return 4
  fi

  log_info "⌛️ Loading Xcode using aria2"
  aria2c \
    --header "Host: adcdownload.apple.com" \
    --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    --header "Upgrade-Insecure-Requests: 1" \
    --header "Cookie: ADCDownloadAuth=$COOKIE" \
    --header "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 10_1 like Mac OS X) AppleWebKit/602.2.14 (KHTML, like Gecko) Version/10.0 Mobile/14B72 Safari/602.1" \
    --header "Accept-Language: en-us" \
    -x 16 \
    -s 16 \
    "https://download.developer.apple.com/Developer_Tools/Xcode_${XCODE_VERSION}/$XIP_NAME" \
    -d "$GIT_ROOT/output" \
    -o "$XIP_NAME"
}

move_archive() {
  log_info "🚚 Moving $XIP_NAME to $APPS_DIR"
  mv "$GIT_ROOT/output/$XIP_NAME" "$APPS_DIR/$XIP_NAME"
}

unpack() {
  log_info "📦 Unpacking $XIP_NAME"
  cd "$APPS_DIR"
  xip -x "$XIP_NAME"
  log_info "📦 Unpacked $XIP_NAME"
  cd -
}

rename_app() {
  log_info  "🚚 Moving $APP_NAME to $APPS_DIR/$TARGET_APP_NAME"
  mv "$APPS_DIR/$APP_NAME" "$APPS_DIR/$TARGET_APP_NAME"
}

remove_archive() {
  log_info "🗑️ Deleting Xcode archive"
  rm -rf "$APPS_DIR/$XIP_NAME"
}

activate() {
  export HISTIGNORE='*sudo -S*'

  if [ -z "$SUDO_PASS" ]; then
    log_error "🎫 Missing SUDO_PASS value in ENV, it is required to activate Xcode"
    return 3
  fi

  log_info "💿 Installing system resources pkg"
  echo "$SUDO_PASS" | sudo -S installer -pkg "$APPS_DIR/$TARGET_APP_NAME/Contents/Resources/Packages/XcodeSystemResources.pkg" -target /

  log_info "💿 Selecting Xcode $XCODE_VERSION"
  echo "$SUDO_PASS" | sudo -S xcode-select -s "$APPS_DIR/$TARGET_APP_NAME"

  log_info "📄 Accepting Xcode license"
  echo "$SUDO_PASS" | sudo -S "$APPS_DIR/$TARGET_APP_NAME/Contents/Developer/usr/bin/xcodebuild" -license accept

  log_info "📄 Running Xcode first launch"
  echo "$SUDO_PASS" | sudo -S "$APPS_DIR/$TARGET_APP_NAME/Contents/Developer/usr/bin/xcodebuild" -runFirstLaunch
}

begin_xfile_task
