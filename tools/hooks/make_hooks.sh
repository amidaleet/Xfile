#!/usr/bin/env bash

set -eo pipefail

if [[ "${IS_CI}" = true ]]; then
  echo "[CI] Skip installing git hooks for local development"
  git config --local --unset core.hooksPath || echo "✅ hooksPath seem to be missing in local config"
  exit 0
fi

CURRENT_PATH="$(git config --local --get core.hooksPath || echo "<not specified in config>")"
echo "Local hooksPath: ${CURRENT_PATH}"

HOOKS_DIR="$(cd -- "$(dirname "$0")"; pwd -P)"

if [[ "${CURRENT_PATH}" = "${HOOKS_DIR}" ]]; then
  echo "✅ Local hooksPath meets expectations, won't change"
  exit 0
fi

echo "♻️  Reset local hooksPath to: ${HOOKS_DIR}"
git config --local --replace-all core.hooksPath "${HOOKS_DIR}"
