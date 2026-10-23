# Fixing a library that packages bundle themselves

Read when a CVE sits in a library (ffmpeg, openssl, libxml2 ...) that each
consumer pulls in at its own version, and no released version has the fix.
Worked example: ffmpeg on `ali-desktop`, where kodi (6.1.6), lutris (6.1.6),
blender (7.1.5), citron (8.1.2), makemkv (8.1.3) and zen (9.0.2) each carried a
different one.

## 1. Measure before editing

An override rebuilds every dependent, and none of it is in a cache.

```bash
nix-store -q --requisites "$toplevel" > closure.txt
for lib in $(grep -E -- '-<lib>-[0-9.]+-lib$' closure.txt); do
  echo "$lib $(nix-store -q --referrers-closure "$lib" | grep -Fxf closure.txt | wc -l)"
done
```

The shared default (`ffmpeg` 8.1.2 on 26.05) had 169 dependent paths: mpv, OBS,
opencv, KDE. Overriding it would recompile all of that locally, so override
per consumer instead, and say the cost to the user before starting.

## 2. Find each consumer's way in

Read the consumer's `package.nix` (the path is in `<pkg>.meta.position`).

| What you find | Override |
|---|---|
| A top-level argument (`ffmpeg`, `ffmpeg_7`) | `pkg.override { ffmpeg_7 = patched; }` |
| An argument for a *different* attribute than you expected | Override that attribute. makemkv moved from `ffmpeg` to `ffmpeg_8`; overriding the old name is an eval error |
| A name resolved inside a `buildFHSEnv` `targetPkgs`/`multiPkgs` callback (lutris `ffmpeg_6`) | Not overridable with arguments: the callback's own `pkgs` supplies it, 32-bit too. Report it |
| A home-manager or flake module option that builds the package for you (zen's `programs.zen-browser.unwrappedPackage`) | Set the option, and pass through whatever the module would have overridden itself (`policies`, `enablePrivateDesktopEntry`); setting it skips that |

Also report, do not force:
- A soname change breaks binaries that expect the old one (ffmpeg 6 to 9 moves
  `libavcodec.so.60` to `.63`). That is why kodi was removed instead.
- The consumer may not compile against a newer major (makemkv's `libffabi`
  does not build against ffmpeg 9).

## 3. Build the fix from upstream master

When the CVE text says "through <newest release>", or the fix lives only on
the default branch, build the upstream tree. Add `pkgs/<name>-git/default.nix`:

```nix
{ lib, fetchFromGitHub, base }:
base.overrideAttrs (old: {
  version = "<next>-unstable-<date>";
  src = fetchFromGitHub { owner = "..."; repo = "..."; rev = "<sha>"; hash = lib.fakeHash; };
  patches = [ ];                                   # target the release tarball
  configureFlags = lib.subtractLists [ "<dropped flag>" ] old.configureFlags;
})
```

- **`base` must come from the same nixpkgs set as the consumer.** One built from
  `pkgs.unstable` links glibc symbols (`GLIBC_2.43`, `GLIBC_2.44`) that a 26.05
  consumer's libc lacks, and the consumer fails at link time with
  `undefined reference`. Define one variant per set (`<name>-git` on
  `pkgs.<attr>`, `<name>-git-unstable` on `pkgs.unstable.<attr>`).
- Get the hash by building with `lib.fakeHash` and copying `got:`.
- Master drops options that releases still pass. `configure` reports one
  `Unknown option` per run, so compare in bulk: list `base.configureFlags`
  (`nix eval --json`), then check each `--enable-X`/`--disable-X` against
  `./configure --help` in the built `src`. `--help` omits components and some
  options master still accepts, so treat the list as candidates and confirm by
  building.
- Confirm master contains the fixes the CVEs cite:
  `gh api repos/<o>/<r>/compare/<fix-sha>...<master-sha> --jq .status` is
  `ahead` or `identical` when it does. Most CVEs cite no commit; say how many
  were checked and that the rest are assumed.
- Say plainly that vulnix will stop flagging the package because of the new
  version string, whether or not each CVE is really fixed.
- Register the override as a pin (`workaround`) with a probe for "released
  version has the fix".

## 4. Build and verify

- `pkgs/` entries are not flake packages. Build one through a host's package
  set: `nix build .#nixosConfigurations.<host>.pkgs.<attr>`.
- A compile can run past a tool timeout. Run builds in the background, one heavy
  build at a time, after `free -g`; chain dependents so the chain stops at the
  first failure.
- Read failures with `nix log <drv>` and grep for `undefined reference`,
  `Unknown option` and `error:`.
- Finish with the whole host: build the toplevel and rescan with `vulnix -C`.
