#!/bin/bash
# set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

function pull_with_force_rebase {
  local branch="${1}"

  git reset --hard HEAD
  rm -fr ".git/rebase-merge" || echo "nothing to reset"
  if [ "$(git ls-remote origin "${branch}" | wc -l)" -gt 0 ]; then
    git pull --depth=1 --rebase origin "$current_branch" 2>&1
  else
    git pull --depth=1 --rebase origin main 2>&1
  fi
}

current_branch=$(git rev-parse --abbrev-ref HEAD)

if [ ! -d "authentication-frontend" ]; then
  git clone --depth=1 -b "$current_branch" git@github.com:govuk-one-login/authentication-frontend.git authentication-frontend \
    || git clone --depth=1 -b main git@github.com:govuk-one-login/authentication-frontend.git authentication-frontend
else
  pushd authentication-frontend || exit
  retries=3
  echo "Refreshing authentication-frontend subdirectory..."
  for ((i = 0; i < retries; i++)); do
    echo "retry: $i"
    ret=$(pull_with_force_rebase "${current_branch}")
    if [ "$(echo "$ret" | grep -o "error" | wc -l)" -eq 0 ]; then
      popd || exit
      exit 0
    fi
  done
  popd || exit
fi
