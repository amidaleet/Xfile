#!/usr/bin/env bash

if [ -f /etc/os-release ]; then
  source /etc/os-release
  echo "$VERSION_ID"
else
  sw_vers -productVersion
fi
