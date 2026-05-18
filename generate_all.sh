#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

# this script requires that submodules be checked out, i.e. git submodule update --init
# set SPAGHETTI_INSTALL_DIR if spaghetti is installed somewhere where luajit can't find it by default
spaghetti_path=spaghetti
if [[ ! -z "${SPAGHETTI_INSTALL_DIR:-}" ]]; then
	export LUA_CPATH="$SPAGHETTI_INSTALL_DIR/?.so"
	spaghetti_path="$SPAGHETTI_INSTALL_DIR"
fi
only="${1:-}"

function generate() {
	if [[ ! -z "${only:-}" ]] && [[ "$only" != "$1" ]]; then
		return
	fi
	luajit TPT-Script-Manager/modulepack.lua r4.build.modulepack:"$spaghetti_path"/spaghetti.build.modulepack run "$1" plot none build "$2"
}
generate "r4.comp.cpu.bus_control"         r4/comp/cpu/bus_control/generated.lua
generate "r4.comp.cpu.memory_rw"           r4/comp/cpu/memory_rw/generated.lua
generate "r4.comp.cpu.reg_r"               r4/comp/cpu/reg_r/generated.lua
generate "r4.comp.cpu.core.head"           r4/comp/cpu/core/generated_head.lua
generate "r4.comp.cpu.core.tail"           r4/comp/cpu/core/generated_tail.lua
generate "r4.comp.cpu.core.alu.multiplier" r4/comp/cpu/core/alu/generated_multiplier.lua
generate "r4.comp.terminal.core.screen"    r4/comp/terminal/core/generated_screen.lua
generate "r4.comp.terminal.core.keyboard"  r4/comp/terminal/core/generated_keyboard.lua
