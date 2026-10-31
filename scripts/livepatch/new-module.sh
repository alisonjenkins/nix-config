#!/usr/bin/env bash
# Scaffold a livepatch module that replaces one function. The author fills in the body.
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat >&2 <<'USAGE'
usage: new-module.sh --name NAME --target FUNC --ret TYPE --args 'ARGLIST' --out FILE.c
         [--object MODULE] [--cve ID]
  NAME is the module name (C identifier, becomes /sys/kernel/livepatch/NAME). FUNC is the
  function to replace, with the return type and argument list it has in the kernel source.
  Without --object the function is looked up in vmlinux; with it, in that loadable module.
USAGE
}

name="" target="" ret="" args="" out="" object="" cve="none"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name=${2:?}; shift 2 ;;
    --target) target=${2:?}; shift 2 ;;
    --ret) ret=${2:?}; shift 2 ;;
    --args) args=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    --object) object=${2:?}; shift 2 ;;
    --cve) cve=${2:?}; shift 2 ;;
    *) echo "new-module.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$name" ] || [ -z "$target" ] || [ -z "$ret" ] || [ -z "$args" ] || [ -z "$out" ]; then
  echo "new-module.sh: --name, --target, --ret, --args and --out are required" >&2
  usage
  exit 1
fi
ident='^[A-Za-z_][A-Za-z0-9_]*$'
for v in "$name" "$target"; do
  [[ $v =~ $ident ]] || { echo "new-module.sh: not a C identifier: $v" >&2; exit 1; }
done
[ -z "$object" ] || [[ $object =~ $ident ]] || { echo "new-module.sh: not a module name: $object" >&2; exit 1; }
[ -z "$cve" ] || [[ $cve =~ ^[A-Za-z0-9._:-]+$ ]] || { echo "new-module.sh: --cve must be an advisory id such as CVE-2026-1234, got: $cve" >&2; exit 1; }
[ ! -e "$out" ] || { echo "new-module.sh: $out exists, not overwriting" >&2; exit 1; }

object_line=""
[ -z "$object" ] || object_line="		.name = \"$object\","

# Values go through awk's ENVIRON so nothing in them is read as sed syntax.
NAME=$name TARGET=$target RET=$ret ARGS=$args CVE=$cve OBJECT_LINE=$object_line awk '
  {
    gsub(/@NAME@/, ENVIRON["NAME"]); gsub(/@TARGET@/, ENVIRON["TARGET"])
    gsub(/@RET@/, ENVIRON["RET"]); gsub(/@ARGS@/, ENVIRON["ARGS"]); gsub(/@CVE@/, ENVIRON["CVE"])
    if ($0 == "@OBJECT_NAME@") { if (ENVIRON["OBJECT_LINE"] != "") print ENVIRON["OBJECT_LINE"]; next }
    print
  }' "$DIR/template/livepatch.c.in" > "$out"
echo "wrote $out"
