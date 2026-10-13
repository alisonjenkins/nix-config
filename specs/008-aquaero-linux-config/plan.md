# Implementation Plan: Aquaero Fan Controller Configuration on Linux

**Branch**: `008-aquaero-linux-config` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-aquaero-linux-config/spec.md`

## Summary

A small Rust tool, `aquaero-ctl`, reads and writes the aquaero's stored configuration (one 0xa93-byte HID feature report) through `hidraw`, from user space, with the kernel driver left loaded. It can snapshot and compare configurations, and it can set a coolant-driven fan curve for fan 4 with backup, dry run, firmware check, read-back verification and restore. A NixOS module, `hardware.aquaeroCtl`, declares the curve and applies it on switch (or only reports drift on a check-only host).

The layout of the stored configuration is not known well enough to write safely, so the work is staged: read-only dump and diff first; layout discovery against Aquasuite in a Windows VM (snapshot diffs for *what* is stored, a one-off USB capture for *how it is saved*); then the write path developed against an in-memory fake device with injected failures; then the first real write in three owner-approved stages; then the NixOS module and the written record.

## Technical Context

**Language/Version**: Rust 2021, toolchain from the flake's dev shell (same as `scripts/retrieval-eval`); Nix for the package and module.

**Primary Dependencies**: `clap`, `thiserror`, `anyhow` (binary edge only), `serde`, `serde_json`, `toml`, `sha2`, `nix` (ioctls, `flock`), `tracing`, `tracing-subscriber`; tests: `proptest`, `tempfile`. No native library.

**Storage**: files. Snapshots and backups are raw `.bin` plus a `.json` sidecar (see [data-model.md](data-model.md)); backups under `/var/lib/aquaero-ctl/backups/<serial>/`; a lock file under `/run`.

**Testing**: `cargo test` with clippy `-D warnings` and `cargo fmt --check` as gates, run by the Nix build (`doCheck`); apply logic tested against an in-memory fake device with injected failures; a module-evaluation flake check for the NixOS options and assertions. Hardware steps are manual and named as untestable glue (first real write, power-cycle persistence, sensor-loss).

**Target Platform**: NixOS on `ali-desktop` (x86_64-linux). Linux only (`hidraw`).

**Project Type**: command-line tool (library plus thin binary) with a NixOS module and a systemd oneshot.

**Performance Goals**: an apply completes in under 10 s (a 0xa93-byte report read and write with a mandatory 200 ms gap between control operations); nothing is time-critical.

**Constraints**: never unload or detach the kernel driver; at least 200 ms between control operations; no write without a saved backup, a matching firmware profile and a read-back; the tool must never fail a system switch because the device is absent.

**Scale/Scope**: one device, one fan channel and one temperature source in v1; the layout notes cover only the in-scope settings.

## Constitution Check

*GATE: passes before Phase 0; re-checked after Phase 1.*

| Principle | Status | How |
|-----------|--------|-----|
| I. Atomic, revertable history | Pass | Each task is one commit; the Rust crate, package, module and host enable land as separate buildable commits. |
| II. Test first, evidence before done | Pass, with named exceptions | Behaviour is test-first against the fake device. The first real write, the power-cycle persistence check and the sensor-loss check need the real device and are named as untestable glue in the tasks; each reports its command output. |
| III. IaC, live changes by consent | Pass | Applying on switch is the owner's declared config (and a per-host check-only mode exists). The first real device writes are staged and each needs the owner's explicit go-ahead in that session. |
| IV. Errors carry context | Pass | One error enum per fallible function with operation-named variants; clippy restriction lints denied; Nix wrapper resolves its tools from the store. |
| V. Right altitude, single source of truth | Pass | One profile data file per firmware version holds every offset; the module renders the desired state to one JSON the tool reads; sensor and channel numbers are not duplicated in Rust. |
| VI. Record the why | Pass, planned | ADR for "user space, not a kernel module" and for the discovered layout and the persistence/commit finding; topic doc `docs/aquaero-config.md`; both in the same pull request as the code. |
| VII. Fork patches generated | N/A | No fork or patch. |
| Operational | Pass | Times ISO 8601 UTC; no secrets; the serial number is redacted in committed fixtures. |

No violations, so the Complexity Tracking table is empty.

**Post-design re-check (after Phase 1)**: still passes. The design adds no second project and no abstraction beyond the `HidDevice` trait, which the fake device needs.

## Project Structure

### Documentation (this feature)

```text
specs/008-aquaero-linux-config/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli.md           # Command-line contract
│   └── nix-module.md    # NixOS module contract
└── tasks.md             # Phase 2 output (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
scripts/aquaero-ctl/
├── Cargo.toml                 # lints table, deps
├── Cargo.lock
├── src/
│   ├── main.rs                # argument parsing, exit codes only
│   ├── lib.rs
│   ├── cli.rs                 # clap definitions
│   ├── hid.rs                 # HidDevice trait, hidraw implementation, node selection
│   ├── lock.rs                # advisory lock and the 200 ms control gap
│   ├── fake.rs                # in-memory device with failure injection (behind a Cargo feature for integration tests)
│   ├── snapshot.rs            # read, write, name, hash, compare
│   ├── diff.rs                # byte-position comparison with volatile marking
│   ├── profile.rs             # firmware profile loading and lookup
│   ├── curve.rs               # curve type, validation, encode and decode
│   ├── plan.rs                # desired state versus device: what would change
│   ├── apply.rs               # backup, write, verify, restore
│   └── error.rs
├── profiles/
│   └── <firmware>.toml        # added once the layout is verified
└── tests/
    ├── apply.rs               # apply and restore against the fake device
    ├── failure.rs             # injected failures
    └── fixtures/              # redacted real dumps

pkgs/aquaero-ctl/default.nix              # buildRustPackage, same pattern as pkgs/token-tools
modules/hardware-aquaero-ctl.nix          # NixOS module and systemd oneshot
flake-modules/nixos-modules.nix           # export hardware-aquaero-ctl
flake-modules/hosts/ali-desktop/default.nix   # enable it
docs/aquaero-config.md                    # layout, discovery method, recovery
docs/adr/0040-aquaero-config-in-user-space.md
```

**Structure Decision**: one crate with a library plus binary under `scripts/`, because that is where this repository keeps its Rust tools and the package follows `pkgs/token-tools`. The NixOS module is one file because `modules/hardware-scarlett-mixer.nix` shows that is the convention for a single-device hardware module.

## Delivery Order

1. **Read-only dump and compare** (story 1, partly): the `HidDevice` trait, the `hidraw` node, snapshot files and `diff`. No writes exist yet.
2. **Layout discovery** (story 1): first a static read of the vendor software's readable settings model (decompiled outside the repository, never committed, treated as leads), then single-setting changes in Aquasuite in the VM with snapshot diffs, plus one USB capture of a save. The device's original configuration is exported before any experiment and restored afterwards. Output is the profile file, `docs/aquaero-config.md` and the ADR draft, which land with the code that rests on them.
3. **Write path against the fake device** (stories 2 and 3): curve type and validation, plan, backup, apply, verify, restore, with injected failures. Test-first.
4. **First real writes**, in three stages each needing the owner's go-ahead: write the unchanged snapshot back; change one benign value and restore; then the curve. Includes the power-cycle and sensor-loss checks.
5. **NixOS module** (story 4, and story 5): options, assertions, oneshot, udev trigger, `mode = "check"`; enable on `ali-desktop`.
6. **Record the why** (story 6): ADR and topic doc finalised; offer the verified layout upstream (kernel driver or liquidctl) as a separate step.

Steps 1 and 2 need the device back on the host, so the Windows VM has to release it between discovery sessions.

## Complexity Tracking

*Empty: the Constitution Check has no violations.*
