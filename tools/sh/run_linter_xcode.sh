#!/usr/bin/env bash

set -eo pipefail

if [ "$IS_CI" = true ]; then
  echo "[CI] Skip swiftlint because of CI"
  exit 0
fi

ROOT_DIR="${GIT_ROOT:-"$(git rev-parse --show-toplevel)"}"

pushd "$ROOT_DIR" || exit 3

if [[ "$(uname -m)" == arm64 ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
  # Нужно для доступа к mint на Apple Silicone
  # Xcode выполняет скрипты в НЕ интерактивном shell
  # То есть $HOME/.zshrc файл не применяется
fi

# Without this trick MacOS executable SPM wont work in pre-build phase of iOS product.
#
# Xcode sets iOS Simulator during iOS target building,
# so swift run fails on launch when this value filled
unset SDKROOT

./Xfile lint_swift || exit 0

popd || exit 3
