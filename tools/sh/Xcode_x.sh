#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

# ---------- Xcode.app Install ----------

## --version --start_step --beta_number --cookie
function xcode:install {
  read_opt --version XCODE_VERSION
  read_opt --beta_number BETA_NUMBER
  read_opt --cookie COOKIE
  read_opt --start_step start_step

  # COOKIE – устаревший параметр реализации через aria2
  # временно оставлен для возможности запуска старой реализации
  assert_defined XCODE_VERSION

  start_step=${start_step:-0}

  if [ -z "$BETA_NUMBER" ]; then
    APP_NAME='Xcode'
  else
    APP_NAME='Xcode-beta'
    XCODE_VERSION="${XCODE_VERSION}_beta_${BETA_NUMBER}"
  fi

  log_info "🎫 Params are: APP_NAME = ${APP_NAME}, XCODE_VERSION = ${XCODE_VERSION}"

  # - Important: шаги запускаются как функции в том же scope, а не как отдельные task
  local script_steps=(
    xcode:load
    xcode:move_archive
    xcode:unpack
    xcode:rename_app
    xcode:remove_archive
    xcode:activate
  )
  local idx=0
  log_info 'Script steps:'
  for step in ${script_steps[@]}; do
    log "$idx – $step"
    idx=$(( idx+1 ))
  done
  log_info "Will start from step: $start_step"

  mkdir -p output
  for step in ${script_steps[@]:$start_step}; do
    log_info "Step: $step"
    $step
  done
}

function xcode:load {
  if [ -n "$COOKIE" ]; then xcode:load_with_aria2; else xcode:load_with_s3; fi
}

function xcode:load_with_s3 {
  local target="${GIT_ROOT}/output/Xcode-${XCODE_VERSION}.xip"
  local uri="https://obs.ru-moscow-1.hc.sbercloud.ru/d-starosfw-fwstorage/packages/Xcode/Xcode-${XCODE_VERSION}.xip"

  rm -rf "$target"
  curl "$uri" -o "${GIT_ROOT}/output/Xcode-${XCODE_VERSION}.xip"

  local file_size="$(stat -f%z "$target")"
  log ".xip file size in bytes: $file_size"

  if [ "$file_size" -lt 2000 ]; then
    log_error "Too small Xcode.xip size, seems to be missing on: $uri"
    return 6
  fi
}

function xcode:load_with_aria2 {
  if [ -z "$(command -v aria2c)" ]; then
    log_error "Missing aria2c utility, to setup: brew install aria2"
    return 4
  fi

  log_info "⌛️ Loading Xcode ${XCODE_VERSION} using aria2"
  aria2c \
    --header "Host: adcdownload.apple.com" \
    --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    --header "Upgrade-Insecure-Requests: 1" \
    --header "Cookie: ADCDownloadAuth=${COOKIE}" \
    --header "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 10_1 like Mac OS X) AppleWebKit/602.2.14 (KHTML, like Gecko) Version/10.0 Mobile/14B72 Safari/602.1" \
    --header "Accept-Language: en-us" \
    -x 16 \
    -s 16 \
    "https://download.developer.apple.com/Developer_Tools/Xcode_${XCODE_VERSION}/Xcode_${XCODE_VERSION}.xip" \
    -d "${GIT_ROOT}/output" \
    -o "Xcode-${XCODE_VERSION}.xip"
}

function xcode:move_archive {
  log_info "🚚 Moving Xcode ${XCODE_VERSION} archive to /Applications"
  mv "${GIT_ROOT}/output/Xcode-${XCODE_VERSION}.xip" "/Applications/Xcode-${XCODE_VERSION}.xip"
}

function xcode:unpack {
  log_info "📦 Unpacking Xcode ${XCODE_VERSION} archive"
  cd /Applications
  xip -x Xcode-${XCODE_VERSION}.xip
  log_info "📦 Unpacked Xcode ${XCODE_VERSION} archive"
  cd -
}

function xcode:rename_app {
  log_info  "🚚 Moving Xcode ${XCODE_VERSION} app to /Applications"
  mv "/Applications/${APP_NAME}.app" "/Applications/Xcode-${XCODE_VERSION}.app"
}

function xcode:remove_archive {
  log_info "🗑️ Deleting Xcode archive"
  rm -rf "/Applications/Xcode-${XCODE_VERSION}.xip"
}

function xcode:activate {
  export HISTIGNORE='*sudo -S*'

  if [ -z "$SUDO_PASS" ]; then
    log_error "🎫 Missing SUDO_PASS value in ENV, it is required to put Xcode.app into /Applications"
    return 3
  fi

  log_info "💿 Intaling system resources pkg"
  echo "$SUDO_PASS" | sudo -S installer -pkg /Applications/Xcode-${XCODE_VERSION}.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /

  log_info "💿 Selecting Xcode ${XCODE_VERSION}"
  echo "$SUDO_PASS" | sudo -S xcode-select -s /Applications/Xcode-${XCODE_VERSION}.app

  log_info "📄 Accepting Xcode license"
  echo "$SUDO_PASS" | sudo -S /Applications/Xcode-${XCODE_VERSION}.app/Contents/Developer/usr/bin/xcodebuild -license accept

  log_info "📄 Running Xcode first launch"
  echo "$SUDO_PASS" | sudo -S /Applications/Xcode-${XCODE_VERSION}.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch

  log_success "Installed Xcode ${XCODE_VERSION}"
}

# ---------- iOS Runtime ----------

# Дока Apple
# https://developer.apple.com/documentation/xcode/installing-additional-simulator-runtimes

## --version --cookie
function ios_runtime:install {
  read_opt --cookie COOKIE

  if [ -n "$COOKIE" ]; then ios_runtime:install_with_aria2; else ios_runtime:install_with_xcode; fi
}

## --version
function ios_runtime:install_with_xcode {
  read_opt --version VERSION
  assert_defined VERSION

  log_info "Active Xcode will be used"
  xcode-select -p

  log_info "Stopping CoreSimulator if active"
  launchctl remove com.apple.CoreSimulator.CoreSimulatorService || true

  local dmg_file="$GIT_ROOT/output/iOS_${VERSION}_Simulator_Runtime.dmg"

  log_info "⌛️ Loading iOS ${VERSION} Runtime"
  xcodebuild -downloadPlatform iOS -buildVersion "$VERSION" -exportPath "$dmg_file"

  log_info "💿 Installing iOS ${VERSION} Runtime"
  xcrun simctl runtime add "$dmg_file"

  # docs method seems to be not working
  # xcodebuild -importPlatform "$dmg_file"

  rm -rf "$dmg_file"

  log_success "Installed iOS ${VERSION} Runtime"
}

## --version --cookie
function ios_runtime:install_with_aria2 {
  read_opt --version VERSION
  read_opt --cookie COOKIE
  assert_defined VERSION COOKIE

  if [ -z "$(command -v aria2c)" ]; then
    log_error "Missing aria2c utility, to setup: brew install aria2"
    return 4
  fi

  log_info "⌛️ Loading iOS ${VERSION} Runtime"
  aria2c \
    --header "Host: adcdownload.apple.com" \
    --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    --header "Upgrade-Insecure-Requests: 1" \
    --header "Cookie: ADCDownloadAuth=${COOKIE}" \
    --header "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 10_1 like Mac OS X) AppleWebKit/602.2.14 (KHTML, like Gecko) Version/10.0 Mobile/14B72 Safari/602.1" \
    --header "Accept-Language: en-us" \
    -x 16 \
    -s 16 \
    "https://download.developer.apple.com/Developer_Tools/iOS_${VERSION}_Simulator_Runtime/iOS_${VERSION}_Simulator_Runtime.dmg" \
    -d "${GIT_ROOT}/output" \
    -o "iOS_${VERSION}_Simulator_Runtime.dmg"

  log_info "Stopping CoreSimulator if active"
  launchctl remove com.apple.CoreSimulator.CoreSimulatorService || true

  local dmg_file="$GIT_ROOT/output/iOS_${VERSION}_Simulator_Runtime.dmg"

  log_info "💿 Installing iOS ${VERSION} Runtime"
  xcrun simctl runtime add "$dmg_file"

  rm -rf "$dmg_file"

  log_success "Installed iOS ${VERSION} Runtime"
}

function ios_runtime:fix_missing { ## Вернуть "потерянные" iOS образы, переустановив runtime (unmount образа в /Library/Developer/CoreSimulator/Volumes)
  local tmp_folder="$HOME/dx_cache/images"
  log "Will use $tmp_folder as tempopary iOS runtime images store"
  rm -rf "$tmp_folder"
  mkdir -p "$tmp_folder"

  cd /Library/Developer/CoreSimulator/Images
  log_info "Next images exist:"
  ls -- *.dmg

  log_info "Saving runtime images"
  for image in *.dmg; do
    if [ ! -f "$image" ]; then
      continue
    fi
    log "Coping ios image named: $image"
    cp "$image" "$tmp_folder/$image"
  done

  log_info "Removing all runtimes"
  xcrun simctl runtime delete all || true

  log_info "Adding runtime images"
  cd "$tmp_folder"
  for image in *.dmg; do
    if [ ! -f "$image" ]; then
      continue
    fi
    log "Adding image: $image"
    xcrun simctl runtime add "$tmp_folder/$image"
  done

  rm -rf "$tmp_folder"
  log_success "All iOS runtimes has been re-added!"
}

run_task "$@"
