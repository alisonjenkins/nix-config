# Contract: `hardware.aquaeroCtl` NixOS module

**Spec**: [../spec.md](../spec.md) | **CLI**: [cli.md](cli.md)

File: `modules/hardware-aquaero-ctl.nix`, exported as `flake.nixosModules.hardware-aquaero-ctl`. Enabled per host; machine-specific values live in the host configuration, not here.

## Options

| Option | Type | Default | Meaning |
|--------|------|---------|---------|
| `enable` | bool | `false` | Turn the module on |
| `package` | package | `pkgs.aquaero-ctl` | The tool |
| `mode` | `"apply"` or `"check"` | `"apply"` | `apply` writes when the device differs; `check` only reports drift and never writes |
| `serial` | string or null | `null` | Which device; null means the only aquaero present |
| `fans.<n>.sensor` | integer 1 to 8 | none | Controlling temperature sensor (v1: fan 4, sensor 1 only) |
| `fans.<n>.minPercent` | integer 0 to 100 | none | Speed floor |
| `fans.<n>.points` | list of `{ temp, percent }` | none | Curve points, °C and percent |
| `backupDir` | path | `/var/lib/aquaero-ctl/backups` | Where automatic backups go |

Example of intent for `ali-desktop` (radiators on fan 4, coolant on Sensor 1):

```nix
hardware.aquaeroCtl = {
  enable = true;
  fans."4" = {
    sensor = 1;
    minPercent = 30;
    points = [ { temp = 30; percent = 30; } { temp = 45; percent = 100; } ];
  };
};
```

## Evaluation-time assertions (FR-016)

The build fails, naming the value, when: `minPercent` is outside 0 to 100; fewer than 2 points; temperatures are not strictly increasing; a point's percent is below `minPercent` or decreases; the fan or sensor is not supported in v1.

## Generated units

| Unit | Behaviour |
|------|-----------|
| `aquaero-ctl-apply.service` | Oneshot running `aquaero-ctl apply --desired <store json>` (with `--check` in `check` mode). Restarted when the desired-state JSON changes, so a switch applies it. |
| udev rule | On the aquaero appearing (`ATTRS{idVendor}=="0c70"`, `ATTRS{idProduct}=="f001"`), starts the service through `TAG+="systemd"` and `SYSTEMD_WANTS`, the pattern used by `hardware-scarlett-mixer.nix`. |
| udev permission rule | Gives the service the access to the `hidraw` node it needs without running anything else as root. |

## Behaviour guarantees

- Applying twice in a row writes nothing the second time (SC-004).
- A missing device does not fail the switch: the service exits 0 with a warning in the journal (FR-015).
- In `check` mode the service never writes; drift is logged.
- The kernel driver is not touched; nothing in the module unloads it.
- The module does not enable anything that writes `pwmN` through the driver.
