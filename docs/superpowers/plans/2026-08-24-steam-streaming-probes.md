# Steam Remote Play probe log — ali-desktop

Each entry records one probe against one tree state. Outcomes are drawn from
the fixed set in the design spec §7: `no-discovery`, `black-screen`,
`cursor-only`, `audio-only`, `works-poor`, `works`.

| UTC timestamp | Tree state | Client | Discovery | Outcome | Notes |
|---|---|---|---|---|---|
| 2026-08-24T22:00Z | pre-change | deck | — | (issues, undiagnosed) | Reported from memory; never diagnosed, no logs kept. Not a measurement. |
| 2026-08-24T23:05Z | tasks-1-2-4-5-9 | deck | ok | works-poor | Capture, audio and input all fine — `-pipewire` did its job and no black screen appeared. Defect is geometry only: the stream carries the whole 5120x1440 DP-2 output rather than the game. Exactly the failure predicted in design spec §6h. Discovery worked with docker0, the docker bridge, three veths and tailscale0 all up, so Task 7 is not needed. |
| 2026-08-25T00:00Z | tasks-1-2-4-5-9 + fullscreen | deck | ok | works-poor | Content correct after fullscreening the game on DP-2, but still letterboxed: the stream carries the whole 5120x1440 output. Steam's picker offers only monitors — no Window tab — while another client's picker on the same portal shows Window and Display tabs, so no window-scoped source (including niri's dynamic cast target) can reach Steam. |
| 2026-08-25T09:00Z | patched niri (virtual outputs) | deck | ok | §5b PASS | `niri msg create-virtual-output --width 1280 --height 800` works on the live TTY session, not just the headless backend as its help text claims. Created HEADLESS-2 at 1280x800 alongside DP-2 at 5120x1440. Steam's picker lists the virtual output as a Display. The blocking unknown in the virtual-output design is resolved: a monitor-only client can select a niri virtual output. |
