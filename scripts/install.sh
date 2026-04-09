#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"

install -d "${BIN_DIR}"
install -m 0755 "./ttune" "${BIN_DIR}/ttune"
echo "Installed ttune to ${BIN_DIR}/ttune"
