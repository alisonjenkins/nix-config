# Camoufox — an anti-detect Firefox fork (daijro/camoufox), built FROM SOURCE.
#
# Camoufox is a patch set + C++ "additions" layered on a pinned vanilla Firefox
# release, exactly like LibreWolf. We therefore reuse nixpkgs' `buildMozillaMach`
# (the same machinery that builds `firefox`/`librewolf`) so the Rust/clang/node
# toolchain comes from Nix rather than Camoufox's `mach bootstrap` (which would
# curl-pipe rustup and download toolchains — the whole point of building from
# source for security is to avoid those opaque fetches).
#
# Build reproduces `scripts/patch.py` + `scripts/copy-additions.sh` from the
# Camoufox repo: copy `additions/` + `settings/` into the Firefox tree, override
# the version files, then apply every `patches/**/*.patch` in basename-sorted
# order (Camoufox's `list_patches()`), with the same `patch` flags upstream uses.
#
# NOTE: this compiles Firefox from source — hours of build, 8-16 GB RAM, ~15 GB
# disk. Targeted at x86_64-linux and built/cached by CI; do not expect to build
# it locally on darwin.
{
  lib,
  fetchurl,
  fetchFromGitHub,
  buildMozillaMach,
}:

let
  # Pinned by Camoufox in upstream.sh: version + release.
  ffVersion = "150.0.2";
  release = "beta.25";
  packageVersion = "${ffVersion}-${release}";

  # The Camoufox repo: patches/, additions/, settings/, assets/. v150.0.2-beta.25.
  camoufoxSrc = fetchFromGitHub {
    owner = "daijro";
    repo = "camoufox";
    rev = "0ac611c4ade309d44a0e6972f26e04684df76be3"; # tag v150.0.2-beta.25
    hash = "sha256-inY39JNSWm03Cv1+VcQFo4oXISens70Jy2qfw/HN+Cs=";
  };

  # Vanilla Firefox 150.0.2 release source (the base Camoufox patches against).
  firefoxSrc = fetchurl {
    url = "mirror://mozilla/firefox/releases/${ffVersion}/source/firefox-${ffVersion}.source.tar.xz";
    sha512 = "e22fc66f7faeb9bef4036d0a90af4c27dabc45a3dc59c7290536bfe46c7624d73388d29b36a8999e364065fa31a5fa167596632229b0af9bc1baf4135fa29a4d";
  };
in
(buildMozillaMach {
  pname = "camoufox";
  applicationName = "Camoufox";
  binaryName = "camoufox";
  version = ffVersion;
  inherit packageVersion;
  src = firefoxSrc;

  # base.mozconfig: unsigned addons, sideloading, camoufox branding/app-name.
  requireSigning = false;
  allowAddonSideload = true;
  branding = "browser/branding/camoufox";

  # Remaining base.mozconfig `ac_add_options` that buildMozillaMach does not
  # already set from the args above. (--enable-application, --with-app-name,
  # --with-branding, --allow-addon-sideload, MOZ_REQUIRE_SIGNING are handled by
  # the builder; --disable-crashreporter via the crashreporterSupport override.)
  extraConfigureFlags = [
    "--with-unsigned-addon-scopes=app,system"
    "--disable-default-browser-agent"
    "--disable-system-policies"
    "--disable-backgroundtasks"
    "--enable-bootstrap"
    "--disable-debug"
    "--disable-debug-symbols"
  ];

  # Replicates scripts/copy-additions.sh (linux-relevant steps) + scripts/patch.py
  # patch application. Runs after the builder's own postPatch.
  extraPostPatch = ''
    cfsrc=${camoufoxSrc}

    echo "camoufox: copying additions + settings into the Firefox tree"
    cp -v "$cfsrc/assets/search-config.json" services/settings/dumps/main/search-config.json

    # Camoufox config bundle, referenced by config.patch via the `lw/` dir.
    mkdir -p lw
    cp -v "$cfsrc/settings/camoufox.cfg" lw/
    cp -v "$cfsrc/settings/distribution/policies.json" lw/
    cp -v "$cfsrc/settings/defaults/pref/local-settings.js" lw/
    cp -v "$cfsrc/settings/chrome.css" lw/
    cp -v "$cfsrc/settings/properties.json" lw/
    touch lw/moz.build

    # All C++ additions (browser/, camoucfg/, juggler/) + camoufox branding dir.
    cp -r "$cfsrc"/additions/* .

    # Override the displayed version (copy-additions.sh tail).
    for f in browser/config/version.txt browser/config/version_display.txt; do
      echo "${packageVersion}" > "$f"
    done

    echo "camoufox: applying patches (basename-sorted, like list_patches())"
    patchlist=$(find "$cfsrc/patches" -name '*.patch' -printf '%f\t%p\n' | sort | cut -f2)
    for p in $patchlist; do
      echo "  -> patch -p1 $p"
      patch -p1 --forward -l --binary -i "$p"
    done
  '';

  meta = {
    description = "Anti-detect Firefox fork for stealth automation (built from source)";
    homepage = "https://github.com/daijro/camoufox";
    license = lib.licenses.mpl20;
    platforms = [ "x86_64-linux" ];
    maxSilent = 14400; # 4h, firefox builds are slow (matches nixpkgs firefox)
    mainProgram = "camoufox";
  };
}).override {
  crashreporterSupport = false;
}
