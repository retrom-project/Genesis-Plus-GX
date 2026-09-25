#!/usr/bin/env bash
set -euo pipefail
umask 022

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
output=${1:?absolute empty output directory is required}
recipe="$root/.github/rpg-runtime/candidate_descriptor.py"
python3 "$recipe" prepare "$output"
test -n "${RETROM_EMSDK_ROOT:-}" && test -f "$RETROM_EMSDK_ROOT/emsdk_env.sh"
source "$RETROM_EMSDK_ROOT/emsdk_env.sh" >/dev/null 2>&1

mkdir -p "$root/.retrom-build"
work=$(mktemp -d "$root/.retrom-build/candidate.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/core" "$work/retroarch" "$work/EmulatorJS/data/cores" "$work/stage"
source_digest=$(python3 "$recipe" digest "$output")
python3 "$recipe" paths "$output" > "$work/paths"
tar --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=go-w -C "$root" \
  --null --verbatim-files-from -T "$work/paths" -cf "$work/source.tar"
tar -C "$work/core" -xf "$work/source.tar"

retroarch_commit=6dd4353937ef48b6ec0bfbdbb15d1c5992d86927
git -C "$work/retroarch" init -q
git -C "$work/retroarch" remote add origin https://github.com/EmulatorJS/RetroArch.git
git -C "$work/retroarch" fetch -q --depth=1 origin "$retroarch_commit"
git -C "$work/retroarch" checkout -q --detach FETCH_HEAD
test "$(git -C "$work/retroarch" rev-parse HEAD)" = "$retroarch_commit"
python3 - "$work/retroarch/emulatorjs/build-emulatorjs.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'noCHD=("mame2003" "mame2003_plus" "pcsx_rearmed")'
if source.count(old) != 1:
    raise SystemExit("pinned RetroArch CHD build setting changed")
# The core owns CHD decoding; do not also link RetroArch's older libchdr objects.
path.write_text(source.replace(old, 'noCHD=("mame2003" "mame2003_plus" "pcsx_rearmed" "genesis_plus_gx")', 1))
PY
python3 - "$work/retroarch/Makefile.emulatorjs" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'LDFLAGS += -s ASYNCIFY=1 -s ASYNCIFY_STACK_SIZE=8192\n'
if source.count(old) != 1:
    raise SystemExit("pinned RetroArch Asyncify build setting changed")
# The shared JS FS read can suspend while fd_read is on the Wasm stack.
path.write_text(source.replace(old, old.rstrip('\n') + ' -s ASYNCIFY_IMPORTS=wasi_snapshot_preview1.fd_read\n', 1))
PY
export SOURCE_DATE_EPOCH=1722900000
emmake make -C "$work/core" -f Makefile.libretro clean platform=emscripten > "$work/build.log" 2>&1
emmake make -C "$work/core" -j4 -f Makefile.libretro platform=emscripten >> "$work/build.log" 2>&1 || { tail -100 "$work/build.log" >&2; exit 1; }
install -m 0644 "$work/core/genesis_plus_gx_libretro_emscripten.bc" "$work/retroarch/emulatorjs/"
(
  cd "$work/retroarch/emulatorjs"
  emmake ./build-emulatorjs.sh --clean
) >> "$work/build.log" 2>&1 || { tail -100 "$work/build.log" >&2; exit 1; }
if grep -q 'undefined symbol:' "$work/build.log"; then tail -100 "$work/build.log" >&2; exit 1; fi

7z x -bd -bso0 -bsp0 -o"$work/stage" \
  "$work/EmulatorJS/data/cores/genesis_plus_gx-wasm.data" >/dev/null
test -f "$work/stage/genesis_plus_gx_libretro.js" && test -f "$work/stage/genesis_plus_gx_libretro.wasm"
python3 "$root/.github/rpg-runtime/expose-content-io-asyncify.py" "$work/stage/genesis_plus_gx_libretro.js"
{
  printf '%s\n\n' '# Genesis Plus GX browser core license' '## Genesis Plus GX'
  cat "$root/LICENSE.txt"
  printf '\n\n%s\n\n' '## EmulatorJS RetroArch frontend'
  cat "$work/retroarch/COPYING"
} > "$work/stage/license.txt"
printf '%s\n' '{"minimumEJSVersion":"4.2.3","version":"2.0.2"}' > "$work/stage/build.json"
printf '%s\n' '{"name":"genesis_plus_gx","extensions":["chd","cue","iso","md","bin","sms","gg","sg"],"options":{},"license":"LICENSE.txt","repo":"https://github.com/retrom-project/Genesis-Plus-GX"}' > "$work/stage/core.json"
(
  cd "$work/stage"
  7z a -mtm=off -mta=off -mtc=off -bd -bso0 -bsp0 -t7z \
    "$output/genesis_plus_gx-wasm.data" genesis_plus_gx_libretro.js genesis_plus_gx_libretro.wasm build.json core.json license.txt
) >/dev/null
install -m 0644 "$work/stage/license.txt" "$output/LICENSE.txt"
gzip -n -c "$work/source.tar" > "$output/source.tar.gz"
test "$source_digest" = "$(python3 "$recipe" digest "$output")"
python3 "$recipe" finalize "$output" --core-id genesis_plus_gx
