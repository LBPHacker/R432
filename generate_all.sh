#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

# this script requires that submodules be checked out, i.e. git submodule update --init
# set SPAGHETTI_INSTALL_DIR if spaghetti is installed somewhere where luajit can't find it by default
if [[ ! -z "${SPAGHETTI_INSTALL_DIR:-}" ]]; then
	export LUA_CPATH="$SPAGHETTI_INSTALL_DIR/?.so"
fi
only="${1:-}"

function generate() {
	if [[ ! -z "${only:-}" ]] && [[ "$only" != "$1" ]]; then
		return
	fi
	luajit TPT-Script-Manager/modulepack.lua modulepack.build.conf:spaghetti/modulepack.build.conf run "$1" plot none build "$2"
}
generate "r4.comp.cpu.memory_rw" r4/comp/cpu/memory_rw/generated.lua
generate "r4.comp.cpu.reg_r"     r4/comp/cpu/reg_r/generated.lua
generate "r4.comp.cpu.core.head" r4/comp/cpu/core/generated_head.lua
generate "r4.comp.cpu.core.tail" r4/comp/cpu/core/generated_tail.lua
