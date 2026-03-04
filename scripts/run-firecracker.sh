#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

exec hook infra firecracker run "$@"
