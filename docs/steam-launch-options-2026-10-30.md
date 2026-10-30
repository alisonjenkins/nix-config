# Steam launch options before the steam-command-runner migration

Captured 2026-10-30 from `ali-framework-laptop`,
`~/.local/share/Steam/userdata/31466631/config/localconfig.vdf` (cloud-synced,
same account as the desktop). Grouped by option string; `?` = no store name
(Steam runtimes, Proton, redistributables). Strings are the raw VDF text, so
`\"\"` is a literal `""` in the real option. PEAK (3527290) has two
`LaunchOptions` entries in the file; the capture kept the later one, and the
earlier was empty.

### `/home/ali/.local/bin/gamescope -- %command%`
- 20 Minutes Till Dawn (1966900)
- ? (1070560)
- ? (1391110)
- ? (1493710)
- ? (1628350)
- ? (2180100)
- ? (228980)
- ? (2805730)
- Baldur's Gate 3 (1086940)
- Be My Horde (2499520)
- Clair Obscur: Expedition 33 (1903340)
- Crawl (293780)
- DEATH STRANDING DIRECTOR'S CUT (1850570)
- Dome Keeper (1637320)
- Elite Dangerous (359320)
- FINAL FANTASY VII REBIRTH (2909400)
- Geometry Wars: Retro Evolved (8400)
- Hardspace: Shipbreaker (1161580)
- Hollow Knight: Silksong (1030300)
- Iron Harvest (826630)
- Lossless Scaling (993090)
- Megabonk (3405340)
- PEAK (3527290)
- Phasmophobia (739630)
- SHENZHEN I/O (504210)
- Shadow of the Tomb Raider: Definitive Edition (750920)
- The Elder Scrolls IV: Oblivion Remastered (2623190)
- Turing Complete (1444480)
- XCOM® 2 (268500)

### `gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%`
- 1000xRESIST (1675830)
- Assassin’s Creed Shadows (3159330)
- Command & Conquer Red Alert™ 2 and Yuri’s Revenge™ (2229850)
- Command & Conquer™ Generals Zero Hour (2732960)
- Command & Conquer™ Tiberian Sun™ and Firestorm™ (2229880)
- DOOM: The Dark Ages (3017860)
- KINGDOM HEARTS -HD 1.5+2.5 ReMIX- (2552430)
- PAYDAY 2 (218620)
- Tempest Rising (1486920)

### `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%`
- ? (2465270)
- Audio Trip (826540)
- Beat Saber (620980)
- Holopoint (457960)
- Pistol Whip (1079800)
- VRChat (438100)

### `LD_PRELOAD=\"\" gamescope -w 2540 -h 1440 -b -- gamemoderun %command%`
- Assassin's Creed Mirage (3035570)
- Assassin's Creed® Odyssey (812140)
- Assassin's Creed® Origins (582160)
- VOIN (2464530)

### `PROTON_LOG=1 PROTON_LOG_DIR=%HOME%/proton-steamvr-log %command%`
- SteamVR (250820)

### `VK_LOADER_DRIVERS_DISABLE=lvp_icd %command%`
- Risk of Rain 2 (632360)

### (empty)
- Golf With Your Friends (431240)

### `LD_PRELOAD=\"\" gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%`
- Subnautica (264710)

### `gamemoderun %command%`
- FINAL FANTASY VII REMAKE INTERGRADE (1462040)

## Raw capture (appid -> LaunchOptions)

```json
{
  "268500": "/home/ali/.local/bin/gamescope -- %command%",
  "1444480": "/home/ali/.local/bin/gamescope -- %command%",
  "2623190": "/home/ali/.local/bin/gamescope -- %command%",
  "228980": "/home/ali/.local/bin/gamescope -- %command%",
  "250820": "PROTON_LOG=1 PROTON_LOG_DIR=%HOME%/proton-steamvr-log %command%",
  "1628350": "/home/ali/.local/bin/gamescope -- %command%",
  "1391110": "/home/ali/.local/bin/gamescope -- %command%",
  "1070560": "/home/ali/.local/bin/gamescope -- %command%",
  "504210": "/home/ali/.local/bin/gamescope -- %command%",
  "750920": "/home/ali/.local/bin/gamescope -- %command%",
  "632360": "VK_LOADER_DRIVERS_DISABLE=lvp_icd %command%",
  "2180100": "/home/ali/.local/bin/gamescope -- %command%",
  "1493710": "/home/ali/.local/bin/gamescope -- %command%",
  "2805730": "/home/ali/.local/bin/gamescope -- %command%",
  "739630": "/home/ali/.local/bin/gamescope -- %command%",
  "3527290": "/home/ali/.local/bin/gamescope -- %command%",
  "3405340": "/home/ali/.local/bin/gamescope -- %command%",
  "993090": "/home/ali/.local/bin/gamescope -- %command%",
  "826630": "/home/ali/.local/bin/gamescope -- %command%",
  "1030300": "/home/ali/.local/bin/gamescope -- %command%",
  "1161580": "/home/ali/.local/bin/gamescope -- %command%",
  "431240": "",
  "8400": "/home/ali/.local/bin/gamescope -- %command%",
  "2909400": "/home/ali/.local/bin/gamescope -- %command%",
  "359320": "/home/ali/.local/bin/gamescope -- %command%",
  "1637320": "/home/ali/.local/bin/gamescope -- %command%",
  "1850570": "/home/ali/.local/bin/gamescope -- %command%",
  "293780": "/home/ali/.local/bin/gamescope -- %command%",
  "1903340": "/home/ali/.local/bin/gamescope -- %command%",
  "2499520": "/home/ali/.local/bin/gamescope -- %command%",
  "1086940": "/home/ali/.local/bin/gamescope -- %command%",
  "1966900": "/home/ali/.local/bin/gamescope -- %command%",
  "218620": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "264710": "LD_PRELOAD=\\\"\\\" gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "438100": "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%",
  "457960": "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%",
  "582160": "LD_PRELOAD=\\\"\\\" gamescope -w 2540 -h 1440 -b -- gamemoderun %command%",
  "620980": "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%",
  "812140": "LD_PRELOAD=\\\"\\\" gamescope -w 2540 -h 1440 -b -- gamemoderun %command%",
  "1079800": "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%",
  "1462040": "gamemoderun %command%",
  "2229850": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "2229880": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "2732960": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "3035570": "LD_PRELOAD=\\\"\\\" gamescope -w 2540 -h 1440 -b -- gamemoderun %command%",
  "2464530": "LD_PRELOAD=\\\"\\\" gamescope -w 2540 -h 1440 -b -- gamemoderun %command%",
  "2465270": "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%",
  "3159330": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "2552430": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "1486920": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "3017860": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "1675830": "gamemoderun mangohud gamescope -w 2540 -h 1600 -- %command%",
  "826540": "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%"
}
```
