# Steam Remote Play probe log — ali-desktop

Each entry records one probe against one tree state. Outcomes are drawn from
the fixed set in the design spec §7: `no-discovery`, `black-screen`,
`cursor-only`, `audio-only`, `works-poor`, `works`.

| UTC timestamp | Tree state | Client | Discovery | Outcome | Notes |
|---|---|---|---|---|---|
| 2026-08-24T22:00Z | pre-change | deck | — | (issues, undiagnosed) | Reported from memory; never diagnosed, no logs kept. Not a measurement. |
| 2026-08-24T23:05Z | tasks-1-2-4-5-9 | deck | ok | works-poor | Capture, audio and input all fine — `-pipewire` did its job and no black screen appeared. Defect is geometry only: the stream carries the whole 5120x1440 DP-2 output rather than the game. Exactly the failure predicted in design spec §6h. Discovery worked with docker0, the docker bridge, three veths and tailscale0 all up, so Task 7 is not needed. |
