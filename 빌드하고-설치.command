#!/bin/zsh
set -eu
rightnook_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$rightnook_root/scripts/build.py"
python3 "$rightnook_root/scripts/install.py"
open "$HOME/Applications/RightNook.app"
