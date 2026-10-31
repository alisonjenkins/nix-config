#!/usr/bin/env bats

setup() {
  SD=$BATS_TEST_DIRNAME/..
  OUT=$BATS_TEST_TMPDIR/lp-example.c
}

scaffold() {
  run "$SD/new-module.sh" --name lp_example --target version_proc_show \
    --ret int --args 'struct seq_file *m, void *v' --out "$OUT" "$@"
}

@test "writes a module that patches the named function of vmlinux" {
  scaffold
  [ "$status" -eq 0 ]
  grep -Fq '.old_name = "version_proc_show"' "$OUT"
  grep -Fq '.new_func = livepatch_version_proc_show' "$OUT"
  grep -Fq 'static int livepatch_version_proc_show(struct seq_file *m, void *v)' "$OUT"
  grep -Fq 'MODULE_INFO(livepatch, "Y")' "$OUT"
  grep -Fq '.replace = true' "$OUT"
  ! grep -Fq '.name =' "$OUT"
}

@test "--object targets a loadable module instead of vmlinux" {
  scaffold --object nf_tables
  [ "$status" -eq 0 ]
  grep -Fq '.name = "nf_tables"' "$OUT"
}

@test "--cve is recorded in the file header" {
  scaffold --cve CVE-2099-0001
  [ "$status" -eq 0 ]
  head -n 5 "$OUT" | grep -Fq 'CVE-2099-0001'
}

@test "the fresh scaffold carries the marker that build-module.sh refuses" {
  scaffold
  grep -Fq 'LIVEPATCH-TODO' "$OUT"
}

@test "no placeholder is left unexpanded" {
  scaffold --cve CVE-2099-0001
  ! grep -E '@[A-Z_]+@' "$OUT"
}

@test "refuses to overwrite an existing file" {
  : > "$OUT"
  scaffold
  [ "$status" -eq 1 ]
  [ ! -s "$OUT" ]
}

@test "rejects a module name or target that is not a C identifier" {
  run "$SD/new-module.sh" --name 'bad name' --target f --ret int --args void --out "$OUT"
  [ "$status" -eq 1 ]
  run "$SD/new-module.sh" --name ok --target 'f;rm' --ret int --args void --out "$OUT"
  [ "$status" -eq 1 ]
  [ ! -e "$OUT" ]
}

@test "missing required flags exit 1 with usage" {
  run "$SD/new-module.sh" --name lp_example
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}
