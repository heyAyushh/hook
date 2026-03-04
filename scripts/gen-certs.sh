#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if [ "$#" -gt 0 ] && [[ "${1}" != --* ]]; then
  dir="$1"
  shift
  exec hook infra certs gen --dir "${dir}" "$@"
fi

exec hook infra certs gen "$@"
