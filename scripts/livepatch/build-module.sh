#!/usr/bin/env bash
# Build a livepatch module against a kernel's dev output and refuse it if it needs symbols the
# kernel does not export (the module would fail to load, or worse, need relocations we do not do).
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: build-module.sh --kernel-dev DIR --src FILE.c --out DIR
  DIR is the kernel's dev output (the one holding lib/modules/*/build). The module is built as
  OUT/<basename of FILE>.ko. Needs make and gcc; they come from nix shell unless on PATH via
  LIVEPATCH_NO_NIX_SHELL=1.
  exit: 0 built; 1 usage; 2 scaffold marker left in the source; 3 symbol preflight refused;
        4 the kernel build failed
USAGE
}

log() { printf '%s step=%s result=%s msg="%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:-}" >&2; }

if [ -z "${LIVEPATCH_NO_NIX_SHELL:-}" ]; then
  exec nix shell nixpkgs#gnumake nixpkgs#gcc nixpkgs#bc nixpkgs#flex nixpkgs#bison nixpkgs#perl \
    nixpkgs#openssl nixpkgs#elfutils nixpkgs#binutils nixpkgs#pkg-config nixpkgs#libelf \
    -c env LIVEPATCH_NO_NIX_SHELL=1 "${BASH_SOURCE[0]}" "$@"
fi

kdev="" src="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kernel-dev) kdev=${2:?}; shift 2 ;;
    --src) src=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    *) log args error "unknown argument: $1"; usage; exit 1 ;;
  esac
done
if [ -z "$kdev" ] || [ -z "$src" ] || [ -z "$out" ]; then
  log args error "--kernel-dev, --src and --out are required"
  usage
  exit 1
fi

build=$(compgen -G "$kdev/lib/modules/*/build" | head -n1 || true)
if [ -z "$build" ] || [ ! -d "$build" ]; then
  log args error "no lib/modules/*/build under $kdev"
  exit 1
fi
[ -f "$src" ] || { log args error "no such source file: $src"; exit 1; }

if grep -q 'LIVEPATCH-TODO' "$src"; then
  log marker refused "$src still has LIVEPATCH-TODO; write the fixed body first"
  exit 2
fi
if [ ! -f "$build/Module.symvers" ]; then
  log preflight refused "$build/Module.symvers is missing, cannot check the module's symbols"
  exit 3
fi

mod=$(basename "$src" .c)
mkdir -p "$out"
cp "$src" "$out/$mod.c"
printf 'obj-m += %s.o\n' "$mod" > "$out/Makefile"

refuse_symbols() {
  log preflight refused "$mod uses symbols the kernel does not export: $1"
  log preflight refused "a fix that needs them cannot be a hand-written module; use kpatch or klp relocations"
  exit 3
}

log build start "make -C $build M=$out modules"
build_log=$(mktemp)
trap 'rm -f "$build_log"' EXIT
if ! make -C "$build" M="$out" modules 2>&1 | tee "$build_log" >&2 || [ "${PIPESTATUS[0]}" -ne 0 ]; then
  # modpost reports an unexported symbol before the preflight below can see the .ko
  unexported=$(sed -n 's/^ERROR: modpost: "\([^"]*\)".*undefined!$/\1/p' "$build_log" | sort -u | tr '\n' ' ')
  [ -z "$unexported" ] || refuse_symbols "$unexported"
  log build failed "kernel build of $mod failed"
  exit 4
fi

# Toolchain symbols every module carries; the kernel provides them even if Module.symvers omits one.
ignore='^(__fentry__|__x86_return_thunk|__x86_indirect_thunk_.*|_GLOBAL_OFFSET_TABLE_)$'
missing=$(nm -u "$out/$mod.ko" | awk '$1 == "U" { print $2 }' | grep -Ev "$ignore" | sort -u \
  | while read -r sym; do
      awk -F'\t' -v s="$sym" '$2 == s { found = 1 } END { exit !found }' "$build/Module.symvers" || echo "$sym"
    done)
[ -z "$missing" ] || refuse_symbols "$(tr '\n' ' ' <<<"$missing")"

log build ok "$out/$mod.ko"
echo "$out/$mod.ko"
