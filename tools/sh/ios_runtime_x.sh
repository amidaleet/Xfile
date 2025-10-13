#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

# Дока Apple
# https://developer.apple.com/documentation/xcode/installing-additional-simulator-runtimes

## --version --cookie
function install {
  read_opt --cookie COOKIE

  if [ -n "$COOKIE" ]; then install_with_aria2; else install_with_xcode; fi
}

## --version
install_with_xcode() {
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
install_with_aria2() {
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

function fix_missing { ## Fix "missing" iOS images, reinstalling runtime (bug with image unmount in /Library/Developer/CoreSimulator/Volumes)
  local tmp_folder="$HOME/dx_cache/images"
  log "Will use $tmp_folder as temporary iOS runtime images store"
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

begin_xfile_task
