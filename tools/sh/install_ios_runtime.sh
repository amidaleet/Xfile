#!/usr/bin/env bash

set -eo pipefail

WORKSPACE="$OUTPUT_DIR"

while getopts v:c: flag; do
  case "${flag}" in
  c) ADCDownloadAuth=${OPTARG} ;; # строка ADCDownloadAuth из cookies после логина (ссылку можно брать с xcodereleases.com)
  v) VERSION=${OPTARG} ;;
  esac
done

echo "[SD] 💿 Installing aria2 using brew (if missing)"
brew list aria2 || brew install aria2

echo "[SD] ⌛️ Loading iOS ${VERSION} Platform"
aria2c \
  --header "Host: adcdownload.apple.com" \
  --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  --header "Upgrade-Insecure-Requests: 1" \
  --header "Cookie: ADCDownloadAuth=${ADCDownloadAuth}" \
  --header "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 10_1 like Mac OS X) AppleWebKit/602.2.14 (KHTML, like Gecko) Version/10.0 Mobile/14B72 Safari/602.1" \
  --header "Accept-Language: en-us" \
  -x 16 \
  -s 16 \
  "https://download.developer.apple.com/Developer_Tools/iOS_${VERSION}_Simulator_Runtime/iOS_${VERSION}_Simulator_Runtime.dmg" \
  -d "${WORKSPACE}" \
  -o "iOS_${VERSION}_Simulator_Runtime.dmg"

echo "[SD] 💿 Installing iOS ${VERSION} Platform"
xcrun simctl runtime add "${WORKSPACE}/iOS_${VERSION}_Simulator_Runtime.dmg"

echo "[SD] ✅ Installed iOS ${VERSION} runtime"
