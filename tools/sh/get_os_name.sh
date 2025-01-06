#!/usr/bin/env bash

case "$(uname)" in
'Linux')
  echo "linux"
  ;;
'Darwin')
  echo "macOS"
  ;;
*)
  echo "unknown"
  ;;
esac
