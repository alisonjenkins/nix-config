# 03 — Control schemes

Goal: controls work out-of-the-box across emulators, declaratively. **Verdict: ship now —
low risk.** Every targeted emulator stores its *input bindings* as plain text → shippable
via `home.file`. The only non-declarative dependency is *external* (Steam Input, §3.2).

## 3.1 RetroArch — fully declarative (the strong case)

Three plain-text layers under `~/.config/retroarch/` (the EmuDeck
`~/.var/app/org.libretro.RetroArch/…` paths are Flatpak-specific — rewrite for the nixpkgs
`retroarch`):

1. **`retroarch.cfg`** — unified hotkey block (EmuDeck values, from
   `functions/EmuScripts/RetroArch_maincfg.sh`):
   - `input_enable_hotkey_btn = "4"` (Select), `input_save_state_btn = "10"` (R1),
     `input_load_state_btn = "9"` (L1), `input_pause_toggle_btn = "0"` (B).
   - Menu/exit use **combos**: `input_menu_toggle_gamepad_combo = "2"` (L3+R3),
     `input_quit_gamepad_combo = "4"` (Select+Start); `input_exit_emulator_btn` /
     `input_menu_toggle_btn = "nul"`.
   - Combo enum **confirmed against source** (`input/input_defines.h`,
     `enum input_combo_type`, tag v1.22.0 = nixpkgs 1.22.2): `0=NONE 1=DOWN_Y_L_R
     2=L3_R3 3=L1_R1_START_SELECT 4=START_SELECT …`. Append-only historically, but
     positional — **re-verify on any RetroArch bump**.
   - Also: `config_save_on_exit = "false"` (**mandatory**, see §3.4),
     `notification_show_autoconfig="false"`, `menu_swap_ok_cancel_buttons="true"`,
     `rewind_enable="false"`, `input_hotkey_block_delay="5"`, `input_joypad_driver="udev"`.
   - Keyboard fallbacks (`input_menu_toggle="f1"`, `input_exit_emulator="escape"`,
     `input_save_state="f2"`…) remain — useful in Plasma.
2. **`autoconfig/<driver>/<Pad>.cfg`** — per-controller profiles (auto-bound by
   driver+vid:pid+name). Source from `libretro/retroarch-joypad-autoconfig` (Deck internal
   pad, Xbox, 8BitDo, Switch Pro). Read-only-safe.
3. **`config/remaps/<core>/<core>.rmp`** — per-core remaps (priority game > content-dir >
   core > global). Read-only-safe.

**Do NOT hardcode `input_player<N>_joypad_index`** — it reflects volatile OS enumeration
order and reshuffles on connect/disconnect/dock (issues #13294/#13180). EmuDeck writes the
identity mapping (= RetroArch's own default), so omitting it changes nothing. For multi-pad
/ docked, prefer **device reservation** (PR #16647): `input_player<N>_reserved_device`
(+ optional `input_vendor_id`/`input_product_id`) + `reserved`/`preferred`. Single internal
pad: leave unset.

## 3.2 Standalone emulators — declarative bindings

| Emulator | nixpkgs attr | Input config path | Format | Device ref | Native controller hotkeys? |
|---|---|---|---|---|---|
| PCSX2 | `pcsx2` | `~/.config/PCSX2/inis/PCSX2.ini` (+ `inputprofiles/*.ini`) | INI | index `SDL-0/A` | **Yes** (`[Hotkeys]`, chords ok) |
| Dolphin | `dolphin-emu` | `~/.config/dolphin-emu/Config/{Dolphin,GCPadNew,WiimoteNew,Hotkeys}.ini` | INI | name+index | **Yes** |
| RPCS3 | `rpcs3` | `~/.config/rpcs3/input_configs/global/<p>.yml` | YAML | name | No |
| Cemu | `cemu` | `~/.config/Cemu/controllerProfiles/controllerN.xml` | XML | `<uuid>` (SDL GUID) | No → Steam Input |
| PPSSPP | `ppsspp` | `~/.config/ppsspp/PSP/SYSTEM/controls.ini` | INI | device-code int | **Yes** |
| melonDS | `melonds` | `~/.config/melonDS/melonDS.toml` | TOML | int | **Partial** (see below) |
| Flycast | `flycast` | `~/.config/flycast/emu.cfg` + `mappings/SDL_<name>.cfg` | INI | name | **Yes** |
| MAME | `mame` | `ctrlr/<profile>.cfg` (declarative) + `cfg/<sys>.cfg` (rewritten) | XML | evdev | **Yes** |
| Switch ryubing | `ryubing` | `~/.config/Ryujinx/Config.json` | **JSON** | SDL GUID | No |
| Switch citron/eden | `citron`/`eden` | `~/.config/<emu>/qt-config.ini` | **INI (QSettings)** | SDL GUID | No |
| azahar (3DS) | `azahar` | `~/.config/azahar-emu/qt-config.ini` | INI | `guid:` token | No → Steam Input |
| xemu | `xemu` | `xemu.toml` | TOML | name/guid | No |

**Corrections (verified — do not repeat the refuted originals):**

- **melonDS has controller hotkeys** (fast-forward/pause/reset bind to a pad). The narrow
  gap: save/load-state + slot-nav were historically hardcoded (non-pad-bindable) — that's
  what EmuDeck layers a Steam Input chord for. Attr is `melonds` (lowercase).
- **Switch forks split by lineage:** `ryubing` (Ryujinx) = JSON `Config.json`;
  `citron`/`eden` (Yuzu) = `qt-config.ini` INI. (The original finding had this reversed.)
- **azahar** config dir is `~/.config/azahar-emu/` (with `-emu`). `[Controls]` grammar:
  `button_a="port:0,button:1,engine:sdl,guid:<guid>"`. A read-only shipped `qt-config.ini`
  is safest (issue #1507 drops some UI-state writes).

### Device-binding fragility

Index- and GUID/name-based bindings are both host/hotplug-dependent. The Deck's **internal**
pad has a stable GUID → a shipped config targeting it is reliable; an external pad won't
match. Mitigation: prefer GUID/name forms, generate config at activation from the detected
pad, or document external-pad reconfig as manual.

## 3.3 Steam Input — simplified by the RetroFE-only model

**Architecture decision (supersedes the per-emulator approach):** we launch **only the
RetroFE frontend** as a single non-Steam shortcut (see 05-frontend.md). The emulators are
**child processes of RetroFE**, not separate Steam shortcuts. This collapses the Steam Input
problem:

- **One Steam Input layout** — RetroFE's — applied once to the single shortcut. **No
  per-emulator/per-AppID `.vdf` templates, no per-game binding drift, none of the imperative
  per-emulator SRM apply.** (The earlier per-emulator template+per-AppID design is dropped.)
- In **Gaming Mode**, Steam Input presents **one virtual gamepad** (xbox360-style) to RetroFE
  **and its child emulators** → every emulator sees the *same* stable controller. So the
  emulator-native configs (§3.1/§3.2) map against **one consistent device** — that's the
  "works out of the box" lever: tune the bundled defaults to the **Steam-Input virtual pad**
  and everything inherits it.

**Device-target nuance** (banked, not a blocker): the device the emulators see differs by
launch path — Gaming-Mode-via-RetroFE = Steam Input's *virtual xbox360 pad*; pure
desktop-direct (launching an emulator outside Steam) = the *raw Steam Deck pad* (different
SDL GUID/name). Since RetroFE-via-Steam is the primary path, tune the bundled standalone
defaults to the **virtual pad**; desktop-direct may need the emulator's own bind step or a
second profile. RetroArch (§3.1) matches by name/udev so it's robust to both.

**What remains imperative:** essentially just the **one-time RetroFE Steam Input layout** (set
once in Steam's controller UI, or shipped as a single template + applied via steam-rom-manager
when RetroFE is imported as the shortcut). No longer per emulator. The
`controls.steamInput.templates` option still exists (ship the RetroFE layout `.vdf`), but is
now used for the *single* RetroFE template rather than one-per-emulator.

## 3.4 Stateful gotcha

`retroarch.cfg` is rewritten on exit → clobbers a read-only `home.file` symlink. Fix:
`config_save_on_exit = "false"` (then ship `retroarch.cfg` read-only). `autoconfig/*.cfg`,
`*.rmp`, and standalone input files are read-only-safe (rewritten only on explicit in-GUI
save). MAME's per-system `cfg/<sys>.cfg` *is* rewritten on exit — ship control schemes via
the read-mostly `ctrlr/<profile>.cfg` (selected by `mame.ini`'s `ctrlr` key), not `cfg/`.

## 3.5 Option schema (sketch)

```nix
options.modules.emulation.controls = {
  enable = lib.mkEnableOption "declarative emulator control schemes";

  retroarch = {
    enable = lib.mkEnableOption "RetroArch unified hotkeys + autoconfig + remaps";
    hotkeyScheme = lib.mkOption { type = lib.types.enum [ "emudeck" "none" ]; default = "emudeck"; };
    autoconfigProfiles = lib.mkOption { type = lib.types.attrsOf lib.types.path; default = {}; };  # name -> .cfg
    remaps = lib.mkOption { type = lib.types.attrsOf lib.types.path; default = {}; };               # "<core>/<core>.rmp" -> file
    deviceReservations = lib.mkOption {                                                              # PR #16647, not joypad_index
      type = lib.types.listOf (lib.types.submodule { options = {
        player = lib.mkOption { type = lib.types.ints.positive; };
        deviceName = lib.mkOption { type = lib.types.str; };
        vendorId = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; };
        productId = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; };
        reservation = lib.mkOption { type = lib.types.enum [ "reserved" "preferred" ]; default = "reserved"; };
      }; });
      default = [];
    };
  };

  standalone = lib.mkOption {                # per-emulator config files shipped verbatim
    type = lib.types.attrsOf (lib.types.submodule { options = {
      configFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
      targetPath = lib.mkOption { type = lib.types.str; };   # HOME-relative, e.g. .config/azahar-emu/qt-config.ini
      readOnly   = lib.mkOption { type = lib.types.bool; default = true; };
    }; });
    default = {};
  };

  steamInput = {
    enable = lib.mkEnableOption "ship Steam Input templates + SRM config (Gaming Mode only)";
    templates = lib.mkOption { type = lib.types.attrsOf lib.types.path; default = {}; };  # "<name>.vdf" -> file
  };
};
```
