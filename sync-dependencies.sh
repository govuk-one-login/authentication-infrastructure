#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

if [ ! -d "authentication-frontend" ]; then
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  git clone --depth=1 -b "$current_branch" git@github.com:govuk-one-login/authentication-frontend.git authentication-frontend ||
  git clone --depth=1 -b main git@github.com:govuk-one-login/authentication-frontend.git authentication-frontend
else
  pushd authentication-frontend
  git pull --depth=1 --rebase
  popd
fi
