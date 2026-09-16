#!/bin/bash
set -e

git submodule update --init --recursive

git submodule foreach '
  branch=$(git config -f "$toplevel/.gitmodules" "submodule.$name.branch")
  if [ -n "$branch" ]; then
    git checkout "$branch"
  fi
'
