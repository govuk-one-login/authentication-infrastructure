#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

current_branch=$(git rev-parse --abbrev-ref HEAD)

if [ ! -d "authentication-frontend" ]; then
  git clone --depth=1 -b "$current_branch" git@github.com:govuk-one-login/authentication-frontend.git authentication-frontend ||
  git clone --depth=1 -b main git@github.com:govuk-one-login/authentication-frontend.git authentication-frontend
else
  pushd authentication-frontend
  git reset --hard HEAD
  rm -fr ".git/rebase-merge" || echo "nothing to reset"
  git pull --depth=1 --rebase origin "$current_branch" --force ||
  git pull --depth=1 --rebase origin main --force
  popd
fi
