#!/usr/bin/env bash

set -eo pipefail

export HISTIGNORE='*sudo -S*'
WORKSPACE="$OUTPUT_DIR"

while getopts v:c:b: flag; do
  case "${flag}" in
  b) BETA_NUMBER=${OPTARG} ;; # номер beta версии (только если устанавливается бета)
  v) XCODE_VERSION=${OPTARG} ;;
  c) ADCDownloadAuth=${OPTARG} ;; # строка ADCDownloadAuth из cookies после логина (ссылку можно брать с xcodereleases.com)
  esac
done

if [ -z "$BETA_NUMBER" ]; then
  APP_NAME='Xcode'
else
  APP_NAME='Xcode-beta'
  XCODE_VERSION="${XCODE_VERSION}_beta_${BETA_NUMBER}"
fi

echo "[SD] 🎫 Params are: APP_NAME = ${APP_NAME}, XCODE_VERSION = ${XCODE_VERSION}"

function load() {
  echo "[SD] 💿 Installing aria2 using brew (if missing)"
  brew list aria2 || brew install aria2

  echo "[SD] ⌛️ Loading Xcode ${XCODE_VERSION} using aria2"
  aria2c \
    --header "Host: adcdownload.apple.com" \
    --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    --header "Upgrade-Insecure-Requests: 1" \
    --header "Cookie: ADCDownloadAuth=${ADCDownloadAuth}" \
    --header "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 10_1 like Mac OS X) AppleWebKit/602.2.14 (KHTML, like Gecko) Version/10.0 Mobile/14B72 Safari/602.1" \
    --header "Accept-Language: en-us" \
    -x 16 \
    -s 16 \
    "https://download.developer.apple.com/Developer_Tools/Xcode_${XCODE_VERSION}/Xcode_${XCODE_VERSION}.xip" \
    -d "$WORKSPACE" \
    -o "Xcode-${XCODE_VERSION}.xip"
}

function move_archive() {
  echo "[SD] 🚚 Moving Xcode ${XCODE_VERSION} archive to /Applications"
  mv "${WORKSPACE}/Xcode-${XCODE_VERSION}.xip" "/Applications/Xcode-${XCODE_VERSION}.xip"
}

function unpack() {
  echo "[SD] 📦 Unpacking Xcode ${XCODE_VERSION} archive"
  cd /Applications
  xip -x Xcode-${XCODE_VERSION}.xip
  echo "[SD] 📦 Unpacked Xcode ${XCODE_VERSION} archive"
  cd -
}

function move_app() {
  echo "[SD] 🚚 Moving Xcode ${XCODE_VERSION} app to /Applications"
  mv /Applications/${APP_NAME}.app /Applications/Xcode-${XCODE_VERSION}.app
}

function remove_archive() {
  echo "[SD] 🗑️ Deleting Xcode archive"
  rm -rf /Applications/Xcode-${XCODE_VERSION}.xip
}

function activate() {
  if [ -z "$SUDO_PASS" ]; then
    echo "[SD] 🎫 Missing SUDO_PASS in ENV!"
    exit 3
  fi

  echo "[SD] 💿 Intaling system resources pkg"
  echo "$SUDO_PASS" | sudo -S installer -pkg /Applications/Xcode-${XCODE_VERSION}.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /

  echo "[SD] 💿 Selecting Xcode ${XCODE_VERSION}"
  echo "$SUDO_PASS" | sudo -S xcode-select -s /Applications/Xcode-${XCODE_VERSION}.app

  echo "[SD] 📄 Accepting Xcode license"
  echo "$SUDO_PASS" | sudo -S /Applications/Xcode-${XCODE_VERSION}.app/Contents/Developer/usr/bin/xcodebuild -license accept

  echo "[SD] 📄 Running Xcode first launch"
  echo "$SUDO_PASS" | sudo -S /Applications/Xcode-${XCODE_VERSION}.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch

  echo "[SD] ✅ Installed Xcode ${XCODE_VERSION}"
}

if [ "$SKIP_LOAD" != true ]; then
  load
fi

if [ "$SKIP_MOVE_ARCHIVE" != true ]; then
  move_archive
fi

if [ "$SKIP_UNPACK" != true ]; then
  unpack
fi

if [ "$SKIP_MOVE_APP" != true ]; then
  move_app
fi

if [ "$SKIP_REMOVE_ARCHIVE" != true ]; then
  remove_archive
fi

activate
