# Feature Specification: Foveated rendering for VR games that lack it

**Feature Branch**: `spec/005-vr-foveated-rendering-injector`

**Created**: 2026-10-05

**Status**: Draft

**Input**: User description: "Foveated rendering injection for VR games that lack it, on Linux/Proton (AMD RDNA4). A per-game-configurable fragment-shading-rate foveation injector for Proton games, starting with fixed centre foveation in D3D11 games, packaged in this repository, with measurement before and after and a go/no-go per game. Eye-tracked gaze for the Steam Frame is designed for but deferred until the hardware is in hand."

## Context

The owner is preparing for a Steam Frame and owns about 100 VR games. The heavy ones render
at a very high pixel count and have no foveated rendering: Skyrim VR, Fallout 4 VR,
BONEWORKS, Blade & Sorcery, Elite Dangerous, Project CARS 2, and Unity and Unreal titles.
Many of the studios have closed or are too small to patch them, so the games will not gain
the feature from their makers.

Foveated rendering spends fewer pixel-shading cycles on the edges of the view, where the eye
sees little detail. The Steam Frame's own foveated *streaming* only lowers bitrate and
encode cost; the PC GPU still shades every pixel. Only foveated *rendering* reduces PC GPU
work.

What research on 2026-10-05 found about existing tools:

- No tool was found that injects foveated rendering into unmodified VR games on Linux with an
  AMD GPU; the search was not exhaustive. OpenXR-Toolkit is discontinued, VRPerfKit and PimaxMagic4All depend on Nvidia-only
  D3D11 extensions, and Quad-Views-Foveated only works for games that already support
  quad views.
- Under Proton, D3D11 games run on DXVK, which has no variable-rate-shading code, so none of
  the Windows tools reach them. The only Linux precedent is a patched DXVK that works for
  VRChat alone, tested on Nvidia.
- Most of the owner's heavy VR games are expected to be D3D11, but only two titles were
  confirmed from their logs (Beat Saber and Arizona Sunshine Remake, both light). The rest is
  from general knowledge and is confirmed per game once each is installed. Half-Life: Alyx is
  expected to be Vulkan with a Linux build, and D3D12 titles are few.

What was measured on the owner's GPU (RX 9070 XT, Mesa 26.2.3) with a probe program kept in
this spec's `research/vrs-probe/` folder, with its recorded output:

- Per-region shading rates work, in 8x8-pixel tiles, with and without a depth buffer.
- The coarsest rate is 2x2 (a quarter of the shading work in the periphery). 4x4 is not
  available.
- Multiview rendering shares one rate map between both eyes.
- 1x, 2x and 4x MSAA honour the rate. 8x MSAA ignores it.
- On this driver, existing pipelines work with a rate map applied without being rebuilt. The
  Vulkan validation layer reports a creation flag as missing and treats it as required; this
  driver does not enforce it, and other drivers were not tested, so behaviour there may be
  undefined.

What is not known and decides parts of this work:

- Whether any of the owner's heavy games are limited by pixel shading on this GPU. In a game
  limited by the CPU or by geometry, frame rate will not improve, but the GPU may still draw
  less power; the measurement reports both.
- Whether the render passes that make up each game's eye image can be told apart from shadow,
  UI and post-processing passes reliably.
- Whether the Steam Frame delivers eye-gaze data to a PC app on a Linux host, and by which
  route. Community tools receive it as OSC messages over UDP; whether Valve's OpenXR and
  OpenVR eye-tracking interfaces reach streamed apps is unverified.
- How the visual artefacts of 2x2 periphery shading look in each game.

The first release is therefore measurement and a fixed (not eye-tracked) foveation region,
which needs no Steam Frame and no gaze data. Eye-tracked gaze is designed for but not built.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Know whether a game can benefit, before any foveation (Priority: P1)

The owner wants a go/no-go answer per game. For a chosen VR game, the owner runs a measurement
that reports whether the game is limited by pixel shading on this GPU, and how much GPU time
and GPU power a foveated region saves. This is the cheapest check and it records which games
gain and by how much.

**Why this priority**: The gain differs a lot between games, and the owner wants it measured
rather than assumed. Any gain beyond noise counts, in frame time or in power, because less GPU
work also means less heat, noise and energy.

**Independent Test**: Run the measurement on one installed VR game and read a report that
states GPU frame time, GPU power draw, how much GPU frame time the eye-image pass takes, and
a go, no-go or inconclusive verdict with the evidence.

**Acceptance Scenarios**:

1. **Given** an installed D3D11 VR game and a headset session, **When** the owner runs the
   measurement for a fixed number of frames, **Then** a report is written with average and 99th
   percentile GPU frame time, average GPU power draw, and the share of GPU frame time taken by
   the eye-image pass.
2. **Given** a game whose frame time is dominated by the CPU, **When** measured, **Then** the
   report says the game is CPU-bound and still states the GPU power change, so the verdict
   reflects power as well as frame time.
3. **Given** a measurement was done, **When** the owner re-reads the report later, **Then** it
   names the game, build, driver version, headset or display settings, and the date.

---

### User Story 2 - Turn on fixed centre foveation in a D3D11 VR game (Priority: P1)

For a game that passed the go check, the owner adds one Steam launch option and the game
renders its eye image with full quality in the middle and reduced shading toward the edges,
with no change to the game's files.

**Why this priority**: This is the deliverable. It proves the approach on the hardware the
owner has today, without a Steam Frame.

**Independent Test**: Launch one heavy D3D11 VR game twice, with and without the launch
option, over the same scene, and compare GPU frame time and screenshots.

**Acceptance Scenarios**:

1. **Given** a game with a profile and the launch option set, **When** it runs, **Then** GPU
   frame time over the same scene is lower than without the option, and the report shows the
   difference.
2. **Given** the launch option is removed, **When** the game runs, **Then** it behaves exactly
   as before, with no foveation code active.
3. **Given** the foveation is on, **When** the owner looks at the centre of the view, **Then**
   there is no visible quality loss there, and a recorded side-by-side check (see SC-002)
   shows the periphery loss is one the owner accepts.

---

### User Story 3 - A failure never breaks the game (Priority: P1)

If the feature cannot find the eye image, the driver lacks the needed support, or a profile is
wrong, the game still starts and plays at normal quality.

**Why this priority**: The feature touches the rendering path of games the owner wants to
play. A crash or a corrupted picture is worse than no foveation.

**Independent Test**: Force each failure (no matching profile, a profile that matches nothing,
a driver without the extension) and confirm the game runs at full quality and a clear message
is logged.

**Acceptance Scenarios**:

1. **Given** the launch option is set but no pass matches the profile, **When** the game runs,
   **Then** no foveation is applied, the game plays normally, and the log says which profile
   field matched nothing.
2. **Given** a driver without per-region shading, **When** the game starts, **Then** it
   starts normally and the log says the feature is disabled and why.
3. **Given** a game with anti-cheat, **When** the owner reads the documentation before trying
   the option, **Then** it states that such games are unsupported and that the owner decides
   at their own risk. The feature cannot tell from inside the game that it has anti-cheat, so
   the warning lives in the documentation only.

---

### User Story 4 - Per-game profiles and a documented verdict per game (Priority: P2)

Each supported game has a small profile saying how to recognise its eye image and how large
the full-quality region is. The owner can adjust a profile without recompiling anything, and
each game has a recorded verdict.

**Why this priority**: Games differ, and the eye image cannot be recognised by one rule. The
profiles are what make the injector usable on more than one game.

**Independent Test**: Edit one game's profile (region size), relaunch, and see the change in
the picture. Read the verdicts file and find an entry for each game tried.

**Acceptance Scenarios**:

1. **Given** a profile with a region size, **When** the owner changes the size and relaunches,
   **Then** the full-quality region changes accordingly.
2. **Given** a game was measured and tried, **When** the owner opens the verdicts record,
   **Then** it has the game, verdict (go, no-go, inconclusive), measured gain, artefact notes
   and date.
3. **Given** a new game, **When** the owner runs the injector without a profile, **Then** it
   offers a discovery mode that logs the candidate eye-image passes so a profile can be
   written.

---

### User Story 5 - Reach Vulkan and D3D12 titles (Priority: P3)

The same fixed foveation works in games that render through Vulkan natively (for example
Half-Life: Alyx) or through D3D12.

**Why this priority**: These games are fewer than the D3D11 set, and D3D12 VR titles rarely
need it. It extends reach once the D3D11 path is proven.

**Independent Test**: Launch one Vulkan-native VR game with the option and compare GPU frame
time and picture as in Story 2.

**Acceptance Scenarios**:

1. **Given** a Vulkan-native VR game with a profile, **When** run with the option, **Then**
   GPU frame time over the same scene drops and the picture stays tolerable.
2. **Given** a D3D12 game that already sets its own shading rates, **When** run with the
   option, **Then** the injector leaves the game's own rates in place and logs that it did.

---

### User Story 6 - Switch to eye-tracked foveation when the Frame arrives (Priority: P4)

When the owner has a Steam Frame, the full-quality region follows their gaze instead of staying
fixed. Gaze comes from whichever route the hardware turns out to support.

**Why this priority**: It needs hardware the owner does not have, and its feasibility on a
Linux host is unverified. The first release only has to leave a clean place to add it.

**Independent Test**: Not testable in this feature. The acceptance check for this story
is that the gaze input is a separate, replaceable part, tested with a synthetic gaze source
that moves the region on a known path.

**Acceptance Scenarios**:

1. **Given** a synthetic gaze source, **When** it moves along a known path, **Then** the
   full-quality region follows within one frame of each update.
2. **Given** the gaze source stops sending, **When** longer than a set timeout passes,
   **Then** the region returns to the fixed centre without a visible jump.

---

### Edge Cases

- The game uses 8x MSAA: the rate has no effect, so the injector must detect this, skip the
  pass, and log it.
- The game renders both eyes into one image side by side, or into a two-layer image: the region
  must be placed correctly for each eye, and the shared rate map must be accounted for.
- The game changes resolution, supersampling or render scale while running: the region must
  follow the new image size.
- The game renders several passes of similar size to the eye image (for example a mirror or
  a second camera): the profile must pick the right one and ignore the others.
- A post-processing or temporal pass reads the coarse pass: visible blockiness spreads, and
  the verdict must record it.
- The game is launched on a machine whose driver is older than the one tested: the
  feature must disable itself rather than guess.
- Two overlays or layers (frame generation, upscalers) are active at once: the injector must
  not break them, and the documentation lists known conflicts.
- The game's own anti-cheat or integrity check rejects a replaced graphics library: the game
  refuses to start. The documentation must say which games are out of scope.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a measurement mode that reports, for a chosen game and
  scene, GPU frame time (average and 99th percentile), average GPU power draw, and the share of
  GPU frame time taken by the eye-image pass, with and without foveation, and writes a go, no-go or
  inconclusive verdict with the evidence.
- **FR-002**: The feature MUST apply a fixed full-quality region at the centre of each eye
  image, with reduced shading rates toward the edges, for Proton games that render through
  D3D11, without changing any file in the game's install.
- **FR-003**: The feature MUST be off unless the owner opts in per game through the game's
  Steam launch options.
- **FR-004**: The feature MUST fall back to normal, unmodified rendering, without crashing
  and with a log message that names the cause, when the eye image is not found, the driver
  lacks the needed support, the profile is invalid, or the game uses a sample count that
  ignores the rates.
- **FR-005**: The feature MUST recognise the eye image through a per-game profile that can
  match on image size, layer count, format and sample count, and that the owner can edit as
  configuration without recompiling the graphics component. A configuration path the owner
  can point a single launch at must exist, so a profile can be tuned without a system switch.
- **FR-006**: The feature MUST offer a discovery mode that lists candidate eye-image passes of
  a running game so a profile can be written.
- **FR-007**: The feature MUST limit its coarsest rate to what the GPU supports (2x2 on the
  owner's GPU) and MUST check support at start-up rather than assume it.
- **FR-008**: The feature MUST handle two-eye rendering with the single shared rate map the
  GPU allows, and MUST document the consequence for eye placement.
- **FR-009**: The feature MUST leave rendering that already sets its own shading rates
  untouched and say so in the log.
- **FR-010**: The feature MUST keep the source of gaze separate from the part that applies
  rates, so a gaze source can be added or replaced without changing the pass-recognition or
  rate-application parts. Only the fixed-centre source is required in this feature.
- **FR-011**: The feature MUST provide a synthetic gaze source for testing the interface in
  Story 6, and MUST fall back to the fixed centre when a gaze source stops sending.
- **FR-012**: The feature MUST keep a record of each game tried: verdict, measured gain,
  artefact notes, driver version and date.
- **FR-013**: The feature MUST write one log line per decision (profile chosen, pass matched
  or not, rates applied or skipped, fallback taken) in a form readable by a person and by a
  script, with ISO 8601 UTC timestamps.
- **FR-014**: The feature MUST be installable and configurable declaratively from this
  repository, including choosing which games get the launch option, with every tool it needs
  supplied by the repository and none assumed to be on the machine.
- **FR-015**: The feature MUST have automated tests for the pass-recognition rules and the
  fallback paths that run without a headset or a game, and MUST be checked against the existing
  probe program's results on the owner's GPU.
- **FR-016**: The feature MUST NOT claim support for games with anti-cheat, and the
  documentation MUST list them as out of scope.
- **FR-017**: The feature MUST apply rates only on GPU and driver combinations it has been
  verified on (this feature verifies the owner's RX 9070 XT with Mesa 26.x), and MUST disable
  itself with a log line naming the GPU and driver on any other combination, unless the owner
  overrides it explicitly.

### Key Entities

- **Game profile**: the per-game recipe: how to recognise the eye image, how large the
  full-quality region is, which rates to use at which distance, and any known conflicts.
- **Eye-image pass**: the render pass or passes that produce the picture shown to the headset,
  distinct from shadow, UI and post-processing passes.
- **Foveation region**: the full-quality area and the rate bands around it, expressed in the
  eye image's own coordinates.
- **Gaze source**: where the centre of the region comes from; fixed centre in this feature,
  and later network messages, shared memory, or an OpenXR layer.
- **Measurement report**: GPU frame time, share of GPU frame time taken by the eye-image pass, game build, driver
  version, headset or display settings, date.
- **Verdict**: go, no-go or inconclusive for one game, with measured gain and artefact notes.
  Go means GPU frame time or GPU power drops by more than run-to-run noise and the artefacts
  are tolerable. No-go means neither drops beyond noise, or the artefacts are not tolerable.
  Inconclusive means the runs were too noisy to tell.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On at least one heavy D3D11 VR game the owner owns, average GPU frame time or
  average GPU power draw over a fixed, repeatable scene is lower with fixed foveation than
  without it by more than the run-to-run noise, measured across at least 3 runs each. There is
  no minimum percentage: any measured reduction is a go if the artefacts are tolerable.
- **SC-001a**: Each measurement report states the noise level (spread across runs) next to the
  gain, so a gain can be told apart from noise.
- **SC-002**: For that game, a recorded side-by-side comparison shows no visible quality
  change in the centre of the view, and the owner accepts the periphery change. The comparison
  uses screenshots taken with foveation off and on at the same fixed positions in the same
  scene (centre, mid-periphery and edge), and the owner's accept or reject decision is written
  into the game's verdict next to the screenshots.
- **SC-003**: Every VR game tried has a written verdict (go, no-go or inconclusive) with a
  measured number and the reason, including games where foveation does not help.
- **SC-004**: In 100% of forced-failure tests (no profile, no match, driver without support,
  unverified GPU and driver, 8x MSAA), the game starts and runs at normal quality and a log line names the cause.
- **SC-005**: Removing the launch option returns the game to the same GPU frame time as before
  installing the feature, within measurement noise.
- **SC-006**: A new D3D11 game can go from "not supported" to a working profile in one
  sitting (under 2 hours) using the discovery mode, for games where the eye image can be
  told apart.
- **SC-007**: The automated tests for pass recognition and fallbacks pass on a machine with no
  headset and no game installed.
- **SC-008**: The gaze source can be swapped for the synthetic one with no change to the
  parts that recognise the eye image or apply the rates.

## Assumptions

- The owner tests on ali-desktop (RX 9070 XT, Mesa 26.x) with a headset they already have,
  streaming through Steam Link, and has not yet received a Steam Frame.
- Heavy D3D11 titles such as Skyrim VR, Fallout 4 VR or BONEWORKS are installed for testing as
  the work proceeds; none of them is installed today. Which one becomes the success-criteria
  game is decided by the first measurements.
- Foveation is enabled per game in two steps: the owner selects the foveation-enabled
  compatibility tool for that game in Steam, and sets the launch option from FR-003. Without
  the launch option the tool behaves like the standard one.
- No minimum gain gates the feature. A small reduction in GPU time still saves power, heat and
  fan noise, and the saving adds up across every session and every user, so any measured
  reduction beyond noise is worth keeping. The expected range from published figures is about
  10% to 25% GPU time on pixel-shading-bound games; this is an estimate, not a promise.
- Fixed foveation at a 2x2 coarsest rate is enough to show a measurable gain. A game where
  neither GPU time nor power drops beyond noise gets a no-go verdict and is not tuned further.
- GPU power draw is readable on the owner's GPU from the driver's own sensor (a power-average
  reading on the discrete card). The machine also has an integrated GPU that exposes a
  similarly named sensor, so the measurement harness must pick the discrete card explicitly.
  If a sensor is missing on another machine, power is reported as unavailable and the verdict
  rests on frame time.
- Other Linux VR users could reuse the feature, and its profiles and verdicts are kept in a
  form that can be shared. Publishing it is not part of this spec, and on any GPU and driver
  not yet verified it stays disabled (FR-017).
- Games with anti-cheat, online multiplayer integrity checks or kernel drivers are out of scope.
  VRChat is out of scope for the same reason.
- Eye-tracked foveation, any gaze source that needs a Steam Frame, and verifying gaze delivery
  to a Linux host are out of scope; they get their own spec when the hardware is in hand.
- D3D12 and Vulkan-native support (Story 5) follow once the D3D11 path has a go verdict.
- Any change to a third-party graphics component is maintained the way this repository already
  maintains other forks. The choice between patching the translation library and writing a
  separate layer, and how it is built and carried, is for the plan, not this spec.
- Research that supports this spec, and what it could not verify, is in this session's findings
  on Steam Frame eye-tracking exposure, existing foveation tools, and the shading-rate probe; the
  plan should link or copy the relevant findings into `docs/`.
