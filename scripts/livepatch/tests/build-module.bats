#!/usr/bin/env bats

# make, nm and modinfo are stubs: what is under test is the gate logic, not the kernel build.

setup() {
  SD=$BATS_TEST_DIRNAME/..
  W=$BATS_TEST_TMPDIR
  KDEV=$W/kdev
  BUILD=$KDEV/lib/modules/6.18.59/build
  mkdir -p "$BUILD" "$W/bin" "$W/out"
  # Module.symvers: crc symbol module type namespace
  printf '0x1\tklp_enable_patch\tvmlinux\tEXPORT_SYMBOL_GPL\t\n0x2\tseq_printf\tvmlinux\tEXPORT_SYMBOL\t\n' > "$BUILD/Module.symvers"
  SRC=$W/lp_example.c
  printf '/* ready */\nint x;\n' > "$SRC"
  cat > "$W/bin/make" <<EOF
#!/bin/sh
echo "make \$*" >> "$W/calls"
touch "$W/out/lp_example.ko"
EOF
  cat > "$W/bin/nm" <<EOF
#!/bin/sh
cat "$W/undefined"
EOF
  chmod +x "$W/bin/make" "$W/bin/nm"
  printf '                 U klp_enable_patch\n                 U seq_printf\n' > "$W/undefined"
  export PATH="$W/bin:$PATH" LIVEPATCH_NO_NIX_SHELL=1
}

build() { run "$SD/build-module.sh" --kernel-dev "$KDEV" --src "$SRC" --out "$W/out" "$@"; }

@test "builds against the kernel dev tree and reports the module path" {
  build
  [ "$status" -eq 0 ]
  grep -Fq "make -C $BUILD" "$W/calls"
  [[ "$output" == *"$W/out/lp_example.ko"* ]]
}

@test "refuses a source that still carries the scaffold marker" {
  printf '/* LIVEPATCH-TODO: write the body */\n' > "$SRC"
  build
  [ "$status" -eq 2 ]
  [ ! -e "$W/calls" ]
}

@test "preflight: an undefined symbol the kernel does not export is a named refusal" {
  printf '                 U klp_enable_patch\n                 U some_static_helper\n' > "$W/undefined"
  build
  [ "$status" -eq 3 ]
  [[ "$output" == *"some_static_helper"* ]]
  [[ "$output" == *"kpatch"* ]]
}

@test "preflight ignores the toolchain symbols every module carries" {
  printf '                 U klp_enable_patch\n                 U __fentry__\n                 U __x86_return_thunk\n                 U __x86_indirect_thunk_rax\n' > "$W/undefined"
  build
  [ "$status" -eq 0 ]
}

@test "missing Module.symvers is a refusal, not a pass" {
  rm "$BUILD/Module.symvers"
  build
  [ "$status" -eq 3 ]
}

@test "a kernel dev tree without a build directory exits 1" {
  rm -r "$KDEV"
  build
  [ "$status" -eq 1 ]
}

@test "a modpost undefined-symbol failure is the same named refusal as the preflight" {
  cat > "$W/bin/make" <<EOF
#!/bin/sh
echo 'ERROR: modpost: "linux_proc_banner" [$W/out/lp_example.ko] undefined!' >&2
exit 2
EOF
  build
  [ "$status" -eq 3 ]
  [[ "$output" == *"linux_proc_banner"* ]]
  [[ "$output" == *"kpatch"* ]]
}

@test "a failing make exits 4" {
  printf '#!/bin/sh\nexit 2\n' > "$W/bin/make"
  build
  [ "$status" -eq 4 ]
}

@test "missing flags exit 1 with usage" {
  run "$SD/build-module.sh" --src "$SRC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}
