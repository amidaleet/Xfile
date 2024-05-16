#!/bin/bash

set -eo pipefail

if [ "$IS_CI" = true ]; then
  echo "[CI] Skip swiftlint because of CI"
  exit 0
fi

pushd "$(git rev-parse --show-toplevel)" || exit 1

if [[ "$(uname -m)" == arm64 ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

# Without this trick MacOS executable SPM wont work in pre-build phase of iOS product.
#
# Xcode sets iOS Simulator during iOS target building,
# so swift run fails on launch when this value filled
unset SDKROOT

./Xfile lint_swift || exit 0

popd || exit 1
