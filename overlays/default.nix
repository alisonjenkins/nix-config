{ inputs
, ...
}:
let
  # Shared openldap override applied across every channel (top-level
  # nixpkgs + master/unstable/stable). Multiple openldap derivations
  # land in the closure (different versions across channels), so the
  # override has to ride along with each channel's `import nixpkgs`
  # — overriding only top-level `pkgs.openldap` leaves `pkgs.master`'s
  # own openldap (2.6.13) un-patched and the build still fails the
  # same flaky `test018-syncreplication-persist` mdb test.
  openldapOverlay = _final: prev:
    let
      # Patch applied to every openldap derivation. Consumers
      # (apr-util, libreoffice, kldap, lutris, gnupg, nfs-utils,
      # cyrus_sasl, ...) often call `openldap.override { withCyrus
      # = true; }` which re-runs the package function and bypasses
      # a plain `overrideAttrs`. We re-apply the patch on .override
      # so EVERY descendant derivation inherits it too.
      patch = drv: drv.overrideAttrs (oldAttrs: {
        doCheck = false;
        preCheck = (oldAttrs.preCheck or "") + ''
          rm -f tests/scripts/test017-syncreplication-refresh
          rm -f tests/scripts/test018-syncreplication-persist
          rm -f tests/scripts/test019-syncreplication-cascade
          rm -f tests/scripts/test020-proxycache
          rm -f tests/scripts/test058-syncrepl-asymmetric
          rm -f tests/scripts/test059-slave-config
          rm -f tests/scripts/test061-syncreplication-initiation
          rm -f tests/scripts/test065-syncreplication-distributed
          rm -f tests/scripts/test067-2master
          rm -f tests/scripts/test074-multiprovider
        '';
      });
      origOverride = prev.openldap.override;
      patched = patch prev.openldap;
    in {
      openldap = patched // {
        # Wrap .override so consumer-driven overrides still get the
        # test deletions baked back in. Important: must wrap the
        # RESULT of origOverride too, so chained .override.override
        # paths keep the patch.
        override = args: patch (origOverride args);
      };
    };
in
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: let
    # Pipewire 1.6.x (used by both nixpkgs's `pipewire` and Jovian's
    # `pipewire-jupiter` fork) doesn't build with the patches/flags
    # that nixos-25.11 still passes:
    #   1. patches list: 0060-libjack-path.patch Hunk #1 fails at
    #      weakjack.h:164 (file refactored upstream after the patch
    #      was written).
    #   2. mesonFlags: -Dsystemd=enabled aborts with
    #      `meson.build:1:0: ERROR: Unknown option: "systemd"`
    #      because the option was split into per-component
    #      sub-options (still passed: systemd-system-service etc.).
    #   3. mesonFlags: -Dbluez5-codec-ldac=enabled aborts with
    #      `spa/meson.build:90:8: ERROR: LDAC decoder library not
    #      found` because nixpkgs doesn't put ldacBT in buildInputs.
    #      Flip to disabled — LDAC is only needed for specific Sony
    #      headphones; SBC, AAC, aptX still work.
    # Apply to BOTH the upstream package and the Jovian fork. Jovian's
    # pipewire-jupiter is `pipewire'.overrideAttrs` of `prev.pipewire`,
    # but our overlay runs AFTER Jovian's so the inherited patches /
    # mesonFlags are the pre-fix versions and we have to retouch the
    # fork explicitly.
    pipewireFix = drv: drv.overrideAttrs (old: {
      patches = builtins.filter (p:
        let name = baseNameOf (toString p);
        in !(prev.lib.hasInfix "libjack-path" name))
        (old.patches or []);
      mesonFlags = let
        drop = f: f == "-Dsystemd=enabled";
        rewrite = f:
          if f == "-Dbluez5-codec-ldac=enabled"
          then "-Dbluez5-codec-ldac=disabled"
          else f;
        filtered = map rewrite (builtins.filter (f: !drop f) (old.mesonFlags or []));
      in
        # Pipewire 1.6.x added new auto-detected deps that nixpkgs
        # doesn't supply or flag. Pin them disabled:
        # * bluez5-codec-ldac-dec — separate decoder dep, ldacBT_dec
        #   not in buildInputs.
        # * onnxruntime — ML runtime for noise-suppression, heavy
        #   dep we don't need for the Steam Deck.
        filtered ++ [
          "-Dbluez5-codec-ldac-dec=disabled"
          "-Donnxruntime=disabled"
        ];
      # Pipewire 1.6.x's spa/meson.build:122 unconditionally requires
      # spandsp for an echo-cancel filter. nixpkgs doesn't add it to
      # pipewire's buildInputs in this rev, so configure aborts:
      #     ERROR: Dependency "spandsp" not found, tried pkgconfig
      buildInputs = (old.buildInputs or []) ++ [ prev.spandsp ];
    });
  in {

    # Restore xrdb alias removed from nixpkgs — home-manager's xresources module
    # still references pkgs.xrdb (via lib.getExe)
    xrdb = prev.xorg.xrdb;

    # WiVRn ships with xrizer first in OVR_COMPAT_SEARCH_PATH and overwrites
    # openvrpaths.vrpath to xrizer at server startup. xrizer's GL backend
    # requires an X11 display handle (GLX), which is null under Wayland —
    # OpenGL apps like Vivecraft (Minecraft Java) fail with "X display is
    # null" + "Texture submission error: Left/Right InvalidTexture". Drop
    # xrizer so WiVRn only finds OpenComposite for the OpenVR bridge.
    wivrn = prev.wivrn.override {
      ovrCompatSearchPaths = "${prev.opencomposite}/lib/opencomposite";
    };

    # Pin claude-code to nixpkgs-master — nixos-unstable often lags behind
    # and yanked versions (e.g. 2.1.88) cause build failures.
    inherit (final.master) claude-code;

    # Only apply pipewireFix to the Jovian fork (1.6.4-jupiter1.5).
    # Upstream nixpkgs pipewire is at 1.4.9 in nixos-25.11, where:
    #   * 0060-libjack-path.patch's weakjack.h hunk applies cleanly
    #     (file pre-refactor),
    #   * -Dsystemd=enabled is still recognised,
    #   * -Dbluez5-codec-ldac-dec doesn't exist as an option (the
    #     decoder was split out in 1.6.x), so applying our fixer
    #     there breaks configure with `Unknown option`.
    # Substituting upstream pipewire from cache.nixos.org also stays
    # cheap when we don't perturb its derivation hash.
    pipewire-jupiter = pipewireFix prev.pipewire-jupiter;

    # Disable direnv tests on Darwin: fish test-fish target gets SIGKILL'd
    # in the sandbox, and the zsh test target hangs at 0% CPU indefinitely.
    # direnv runs its shell tests in installCheckPhase, so doCheck alone
    # isn't enough — also disable installCheck.
    direnv = if prev.stdenv.hostPlatform.isDarwin
      then prev.direnv.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
        installCheckPhase = "true";
      })
      else prev.direnv;

    # zsh's test suite hangs on Darwin (TTY-related tests sit at 0% CPU
    # indefinitely in the Nix sandbox, blocking the rest of the build).
    zsh = if prev.stdenv.hostPlatform.isDarwin
      then prev.zsh.overrideAttrs (_: { doCheck = false; })
      else prev.zsh;

    # openldap flaky syncreplication tests: consumers like lutris call
    # `openldap.override { withCyrus = true; }` which re-runs the package
    # function and produces an uncached variant that runs the test suite.
    # The wrapped .override ensures the patch sticks across consumer
    # overrides.
    inherit (openldapOverlay null prev) openldap;

    # fastmcp's pytest suite takes 2+ hours and is uncached upstream
    # (cache.nixos.org has no narinfo for it), so disabling doCheck
    # costs no cache hits and unblocks anything depending on fastmcp
    # (mcp-nixos, claude-code-mcp.json, ...).
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (python-final: python-prev: {
        fastmcp = python-prev.fastmcp.overridePythonAttrs (old: {
          doCheck = false;
          dontCheck = true;
          installCheckPhase = "true";
          checkPhase = "true";
          nativeCheckInputs = [];
        });
      })
      # av's check phases SIGKILL on Darwin: Nix's fixup phase
      # install_name_tool's the .so extension modules and the ffmpeg
      # dylibs they dlopen, invalidating signatures. Re-signing only av's
      # own .so files isn't enough — the transitive ffmpeg load still
      # gets killed inside the sandbox during both pythonImportsCheck
      # and pytest checkPhase. The kill cascades up the chain: any
      # downstream package whose tests transitively `import av` (imageio,
      # scikit-image, plotly, igraph) hits the same SIGKILL during pytest
      # collection. Re-sign av defensively for runtime, and skip checks
      # for the whole chain since none can pass in the sandbox.
      # Pulled in via checkov → igraph → plotly → scikit-image → imageio → av.
      (python-final: python-prev:
        let
          skipChecks = pkg: pkg.overridePythonAttrs (_: {
            doCheck = false;
            dontCheck = true;
            pythonImportsCheck = [];
            dontUsePythonImportsCheck = true;
          });
        in prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
          av = (skipChecks python-prev.av).overridePythonAttrs (old: {
            postFixup = (old.postFixup or "") + ''
              find $out -name "*.so" -exec /usr/bin/codesign --force --sign - {} \;
            '';
          });
          imageio = skipChecks python-prev.imageio;
          scikit-image = skipChecks python-prev.scikit-image;
          plotly = skipChecks python-prev.plotly;
          igraph = skipChecks python-prev.igraph;
        })
    ];

    # Re-sign fish after build on Darwin.
    # Nix's fixup phase runs install_name_tool to rewrite library paths, which
    # invalidates the original code signature. Corporate AV tools then SIGKILL
    # any new fish process. Signing in postFixup (after all patching) produces a
    # valid ad-hoc signature over the final binary.
    fish = if prev.stdenv.hostPlatform.isDarwin
      then prev.fish.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          /usr/bin/codesign --force --sign - $out/bin/fish
        '';
      })
      else prev.fish;
  };

  # When applied, the stable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.stable'
  # stable-packages = final: _prev: {
  #   stable = import inputs.nixpkgs_stable {
  #     system = final.system;
  #     config.allowUnfree = true;
  #   };
  # };

  stable-packages = final: _prev: {
    stable = import inputs.nixpkgs_stable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      overlays = [ openldapOverlay ];
    };
  };

  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs_unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      overlays = [
        openldapOverlay
        (mfinal: mprev: {
          # Re-sign av's .so files on Darwin and skip checks for the
          # whole av-importing chain. install_name_tool invalidates
          # signatures during fixup, and the ffmpeg dylibs av dlopens are
          # also patched, so any pytest in this chain SIGKILLs at
          # collection time when it imports av. Re-signing av is kept as
          # a defensive measure for runtime use.
          pythonPackagesExtensions = mprev.pythonPackagesExtensions ++ [
            (python-final: python-prev:
              let
                skipChecks = pkg: pkg.overridePythonAttrs (_: {
                  doCheck = false;
                  dontCheck = true;
                  pythonImportsCheck = [];
                  dontUsePythonImportsCheck = true;
                });
              in mprev.lib.optionalAttrs mprev.stdenv.hostPlatform.isDarwin {
                av = (skipChecks python-prev.av).overridePythonAttrs (old: {
                  postFixup = (old.postFixup or "") + ''
                    find $out -name "*.so" -exec /usr/bin/codesign --force --sign - {} \;
                  '';
                });
                imageio = skipChecks python-prev.imageio;
                scikit-image = skipChecks python-prev.scikit-image;
                plotly = skipChecks python-prev.plotly;
                igraph = skipChecks python-prev.igraph;
              })
          ];
        })
      ];
    };
  };

  # When applied, the master nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.master'
  master-packages = final: _prev: {
    master = import inputs.nixpkgs_master {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      overlays = [
        openldapOverlay
        (mfinal: mprev: {
          # fastmcp pytest takes 2+ hours, uncached upstream — skip checks
          pythonPackagesExtensions = mprev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              fastmcp = python-prev.fastmcp.overridePythonAttrs (_: {
                doCheck = false;
                dontCheck = true;
                installCheckPhase = "true";
                checkPhase = "true";
                nativeCheckInputs = [];
              });
            })
          ];
        })
      ];
    };
  };

  lqx-pin-packages = final: _prev: {
    lqx_pin = import inputs.nixpkgs_lqx_pin {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      overlays = [ openldapOverlay ];
    };
  };

  # python-lsp-server 1.14.0 declares `jedi<0.20.0` in pyproject.toml, but
  # nixpkgs now ships jedi 0.20.0 → pythonRuntimeDepsCheckHook fails. pylsp
  # works fine at runtime with jedi 0.20 (no API breakage), the upper bound
  # is just an outdated pin. Relax it across all Python variants via
  # pythonPackagesExtensions so every python3X.pkgs gets the patched version.
  # Drop once nixpkgs bumps pylsp to >=1.14.1 (which relaxes the constraint).
  python-lsp-server-jedi-relax = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyfinal: pyprev: {
        python-lsp-server = pyprev.python-lsp-server.overridePythonAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace pyproject.toml \
              --replace-fail 'jedi>=0.17.2,<0.20.0' 'jedi>=0.17.2,<0.21.0'
          '';
        });
      })
    ];
  };

  _1password = final: _prev: {
    # Agilebits republished 1Password 8.12.21 binary tarball at the same URL
    # with new content on 2026-05-22, breaking nixpkgs's pinned hash. Override
    # src with the current hash until nixpkgs (and nixos-unstable channel)
    # picks up the new sources.json. Drop this overrideAttrs block once
    # `nix flake update nixpkgs_unstable` pulls a commit with the corrected
    # sha256 (post-2026-05-23).
    _1password-gui = final.unstable._1password-gui.overrideAttrs (_old: {
      src = final.fetchurl {
        url = "https://downloads.1password.com/linux/tar/stable/x86_64/1password-8.12.21.x64.tar.gz";
        hash = "sha256-JwiMi2iozP6jWSIUtgXla86aSAhuUob7snqtUbeXPpI=";
      };
    });
    _1password-cli = final.unstable._1password-cli;
  };

  bluray-playback = final: _prev: {
    libbluray = _prev.libbluray.override {
      withAACS = true;
      withBDplus = true;
      withJava = true;
    };
  };

  # Pull linux-firmware from kernel.org main HEAD (post-20260410) so we
  # get the May 7, 2026 AMD firmware batch — specifically GC 12.0.1
  # (gfx1201, our RX 9070 XT), PSP 14.0.3, SMU 14.0.3 kicker, SDMA 6.1.3,
  # VCN 5.0.0. Old GC 12.0.1 firmware ships without pipe-reset support
  # ("The CPFW hasn't support pipe reset yet" in dmesg when amdgpu tries
  # to recover a hung gfx ring), forcing the kernel into a MODE1 SoC
  # reset that wipes VRAM. The May 7 firmware bundle is the candidate
  # upstream fix.
  #
  # Also keeps the original reason for overriding from stable: stable's
  # linux-firmware fetchpatch strips binary blobs from the amdxdna NPU
  # firmware patch, producing 0-byte files.
  #
  # Revert to `final.unstable.linux-firmware` (or drop the overlay
  # entirely once nixpkgs catches up) when the next tagged release
  # (>20260410) lands containing the May 7 amdgpu updates.
  linux-firmware = final: _prev: {
    linux-firmware = final.unstable.linux-firmware.overrideAttrs (_old: {
      version = "20260514-unstable-5b2bc2e";
      src = final.fetchgit {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git";
        rev = "5b2bc2e7d14c56e14c59a3d6e7b5b0641dc45c88";
        hash = "sha256-96pu+G5o2X5RWkpFo7FTo4/j+1hpzm/DWG+4q0IsApU=";
      };
    });
  };

  tmux-sessionizer = final: _prev: {
    tmux-sessionizer = inputs.tmux-sessionizer.packages.${final.stdenv.hostPlatform.system}.default;
  };

  python3PackagesOverlay = final: prev: {
    python312Packages = prev.python312Packages // {
      s3transfer = inputs.nixpkgs_stable.legacyPackages.${final.stdenv.hostPlatform.system}.python312Packages.s3transfer;
    };
  };

  qtwebengine = final: prev: {
    libsForQt5 = prev.libsForQt5 // {
      qt5 = prev.libsForQt5.qt5 // {
        qtwebengine = inputs.nixpkgs_stable.legacyPackages.${final.stdenv.hostPlatform.system}.qtwebengine;
      };
    };
  };

  quirc = final: _prev: {
    quirc = _prev.quirc.overrideAttrs (oldAttrs: {
      postInstall = ''
        # don't install static library
        rm $out/lib/libquirc.a
      '';
    });
  };

  systemd = final: prev:
    let
      # Detect PR #40954 (birthDate field) at eval time to avoid unnecessary rebuilds.
      # Extract the version and hash from the nixpkgs systemd definition, then fetch
      # the source independently to check for birthDate without triggering recursion.
      nixpkgsSystemdDef = builtins.readFile (prev.path + "/pkgs/os-specific/linux/systemd/default.nix");
      versionMatch = builtins.match ''.*version = "([^"]+)".*'' nixpkgsSystemdDef;
      hashMatch = builtins.match ".*fetchFromGitHub [^}]*hash = \"([^\"]+)\".*" nixpkgsSystemdDef;
      systemdVersion = if versionMatch != null then builtins.elemAt versionMatch 0 else null;
      systemdHash = if hashMatch != null then builtins.elemAt hashMatch 0 else null;
      # Fetch the source using builtins only (no prev.* packages) to avoid recursion.
      # The SRI hash from fetchFromGitHub is compatible with builtins.fetchTarball.
      systemdSrc = if systemdVersion != null && systemdHash != null then
        builtins.fetchTarball {
          url = "https://github.com/systemd/systemd/archive/v${systemdVersion}.tar.gz";
          sha256 = systemdHash;
        }
      else null;
      srcHasBirthDate = systemdSrc != null
        && builtins.pathExists "${systemdSrc}/src/shared/user-record.c"
        && builtins.match ".*birthDate.*" (builtins.readFile "${systemdSrc}/src/shared/user-record.c") != null;
    in prev.lib.optionalAttrs srcHasBirthDate {
    systemd = prev.systemd.overrideAttrs (oldAttrs:
      let
        # Revert PR #40954: "userdb: add birthDate field to JSON user records"
        revertPatch1 = final.fetchpatch {
          url = "https://github.com/systemd/systemd/commit/7a858878a03966d2a65ef9e8f79b5caff352ac53.patch";
          hash = "sha256-JeJ+swYQx4WoYK/VBlRzu8xZH9R/9Py0qyp5RAXQJZQ=";
        };
        revertPatch2 = final.fetchpatch {
          url = "https://github.com/systemd/systemd/commit/770958e24a2ee59593aa6833a4a825db0a6abbbc.patch";
          hash = "sha256-GJjc4k7+r3A68lohnOjRRr800fIEpUdWXVjFpjmgXZA=";
        };
      in {
      prePatch = (oldAttrs.prePatch or "") + ''
        echo "Reverting PR #40954 (birthDate field)..."
        patch -R -p1 < ${revertPatch1}
        patch -R -p1 < ${revertPatch2}
      '';
    });
  };

  snapper = final: _prev: {
    snapper = _prev.snapper.overrideAttrs (oldAttrs: {
      buildInputs = oldAttrs.buildInputs ++ [ _prev.zlib ];
    });
  };

  zk = final: prev: {
    zk = prev.zk.overrideAttrs
      (oldAttrs: rec {
        version = "v0.14.2";
        vendorHash = "sha256-2PlaIw7NaW4pAVIituSVWhssSBKjowLOLuBV/wz829I=";

        src = prev.fetchFromGitHub {
          owner = "zk-org";
          repo = "zk";
          rev = version;
          hash = "sha256-h6qQcaAgxWeBzMjxGk7b8vrVu5NO/V6b/ZvZMWtZTpg=";
        };
      });
  };

  lsfg-vk = final: prev: {
    lsfg-vk-ui = final.stdenv.mkDerivation rec {
      pname = "lsfg-vk";
      version = "2.0-dev-unstable-2026-01-18";

      src = final.fetchFromGitHub {
        owner = "PancakeTAS";
        repo = "lsfg-vk";
        rev = "14904b9f3d78aea692bff0d330ce403ae0e74766";
        hash = "sha256-yF8GuclZ5WaFvQkXH6iJmUuj5cgFglh9Ttre/DrD5Yg=";
      };

      nativeBuildInputs = with final; [
        cmake
        pkg-config
        qt6.wrapQtAppsHook
      ];

      buildInputs = with final; [
        vulkan-headers
        vulkan-loader
        qt6.qtbase
        qt6.qtdeclarative
      ];

      cmakeFlags = [
        "-DLSFGVK_BUILD_UI=ON"
        "-DLSFGVK_BUILD_VK_LAYER=ON"
        "-DLSFGVK_BUILD_CLI=ON"
        "-DLSFGVK_INSTALL_XDG_FILES=ON"
      ];

      # Fix the Vulkan layer JSON to use absolute library path and add required functions
      postInstall = ''
        # Fix library path to absolute
        substituteInPlace $out/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json \
          --replace-fail '"library_path": "liblsfg-vk-layer.so"' '"library_path": "'$out'/lib/liblsfg-vk-layer.so"'

        # Add the functions section required by Vulkan loader
        substituteInPlace $out/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json \
          --replace-fail '"disable_environment": {' '"functions": { "vkNegotiateLoaderLayerInterfaceVersion": "vkNegotiateLoaderLayerInterfaceVersion" }, "disable_environment": {'

        # Create symlink with old filename for NixOS module compatibility
        ln -s VkLayer_LSFGVK_frame_generation.json $out/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json
      '';

      meta = with final.lib; {
        description = "Linux Shader Function Generator for Vulkan - Version 2.0";
        homepage = "https://github.com/PancakeTAS/lsfg-vk";
        license = licenses.unfree; # Update if you know the actual license
        platforms = platforms.linux;
      };
    };
  };

  qbittorrent = final: prev: {
    qbittorrent = (prev.callPackage (prev.path + "/pkgs/by-name/qb/qbittorrent/package.nix") {
      guiSupport = false;
      boost = final.boost186;
      libtorrent-rasterbar = prev.libtorrent-rasterbar-2_0_x;
    }).overrideAttrs (oldAttrs: {
      version = "5.1.4";
      name = "qbittorrent-nox-5.1.4";

      src = prev.fetchFromGitHub {
        owner = "qbittorrent";
        repo = "qBittorrent";
        rev = "release-5.1.4";
        sha256 = "1zja55b97cnij3vffmfa5p65dasybbm1gd3xjspw5yyypy5cl5zm";
      };

      patches = [];
    });

    # neotest (luarocks 5.18.0-1 packaged via ali-neovim flake's
    # vimUtils.buildNeovimPlugin) currently fails its checkPhase
    # despite all printed tests passing — busted exits 1 even when
    # Success/Failed/Errors all read 0. Skip tests until upstream
    # is fixed; functionality is unaffected.
    luajitPackages = prev.luajitPackages.overrideScope (_lfinal: lprev: {
      neotest = lprev.neotest.overrideAttrs (_: { doCheck = false; });
    });
  };
}
