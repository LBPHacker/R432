#!/usr/bin/env bash
set -euo pipefail

TARGET="riscv32i-unknown-none-elf"
PROFILE="release"
NAME="showcase"
OBJCOPY="rust-objcopy"

cargo build --release --target "${TARGET}"

ELF="target/${TARGET}/${PROFILE}/${NAME}"
BIN="target/${TARGET}/${PROFILE}/${NAME}.bin"

echo "==> Converting ELF to binary..."
"$OBJCOPY" \
    -O binary \
    "${ELF}" \
    "${BIN}"

BIN_ABS="$(realpath "${BIN}")"

echo "==> Done:"
echo "    BIN: ${BIN_ABS}"
