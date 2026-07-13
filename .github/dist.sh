#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

if [[ -d dist ]]; then
	rm -r dist
fi
mkdir dist
cp -r r4 r4.plot.modulepack dist/
cd dist
git submodule update --init
luajit ../TPT-Script-Manager/modulepack.lua r4.plot.modulepack:../spaghetti/spaghetti.plot.modulepack > r4plot.lua
