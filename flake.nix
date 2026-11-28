{
  description = "My flake";

  inputs = {
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    niri = {
      url = "github:YaLTeR/niri";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };
    # niri with virtual outputs and projections: upstream niri plus the
    # fork's commits, used when modules.desktop.niriVirtualOutputs is on.
    niri-virtual = {
      url = "github:alisonjenkins/niri/rebase-feat-virtual";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };
    # eks-creds = {
    #   url = "github:alisonjenkins/eks-creds";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    claude-monitor = {
      # TUI dashboard of live Claude Code session state in tmux; its
      # home-manager module registers the hooks that feed it.
      url = "github:alisonjenkins/claude-monitor";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };
    # Home Manager modules for the Valve Steam Frame (SteamOS, aarch64):
    # session/portal fixes, VR keyboard and SteamVR dashboard patches. Used
    # by the standalone homeConfigurations.steamos (flake-modules/hosts/home-only).
    steam-frame-nix = {
      url = "github:lhns/steam-frame-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    luks-controller-unlock = {
      url = "github:alisonjenkins/luks-controller-unlock";
      # Follow nixpkgs_unstable: upstream's flake.nix tracks nixos-unstable
      # for its rustPlatform.buildRustPackage devshell + libdrm/cryptsetup
      # buildInputs. Following our 25.11 stable channel risks pulling
      # older versions than upstream tested against.
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };
    nix-cachyos-kernel = {
      # Earlier belief that CachyOS 7 had a dm-crypt EINVAL regression was
      # wrong — the real cause was `luks.cryptoModules = mkForce [...]` in
      # modules/base/default.nix stripping xts.ko from the initrd. With
      # default cryptoModules (xts, cbc, aesni-intel auto-included from the
      # NixOS default list), LUKS opens fine. Kept as a rev pin (not
      # branch-following) so upstream Hydra/Garnix caches keep hitting —
      # following nixpkgs forces full LTO rebuild from source. Rev tracks
      # upstream's `release` branch, which upstream only advances once its
      # own Hydra CI has built and cached that revision.
      url = "github:xddxdd/nix-cachyos-kernel/c157f8ddd2c830e8dd5ef6cf11a288668fb96189";
    };
    niks3 = {
      # Pinned to v1.7.0 to match the server running in aws-k3s.
      # Bump in lockstep with the server deployment to avoid 404s on
      # client/server API drift. v1.6.1 (server) switched small NARs
      # (<=~10MB) to single-PUT presigned URLs; clients <1.6.1 reject
      # that response with "NAR files should use multipart upload".
      url = "github:Mic92/niks3/v1.7.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs_master.url = "github:nixos/nixpkgs";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-26.11";
    nixpkgs_old.url = "github:nixos/nixpkgs/nixos-24.11";
    # Holds the Ghidra and JDK that REA's decompiler runs on. nixpkgs_unstable
    # from 02c087f3 (2026-10-23) builds a Ghidra whose native decompile helper
    # segfaults at startup, which fails the rea-ghidra check and so every
    # nightly flake.lock PR. A rev in the URL keeps `nix flake update` from
    # moving it; re-pin once `nix build .#checks.x86_64-linux.rea-ghidra`
    # passes against a newer nixpkgs.
    nixpkgs_rea_pin.url = "github:nixos/nixpkgs/55bfb4d7437bd4e09ab7cba58a43bd68eb310044";
    nixpkgs_stable_darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs_unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixvirt = {
      url = "github:AshleyYakeley/NixVirt/v0.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      # TODO(26.11): switch to release-26.11 once stylix cuts it; master
      # targets 26.11 until then.
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ali-neovim = {
      url = "github:alisonjenkins/neovim-nix-flake";
      inputs = {
        # Build ali-neovim (and the nixvim packages it pulls) against the
        # release `nixpkgs` (26.11), not nixpkgs_unstable, and keep nixvim
        # on the matching release so nixvim's mismatched-version warning
        # stays quiet.
        nixpkgs.follows = "nixpkgs";
        nixpkgs-master.follows = "nixpkgs_master";
        nixpkgs-stable.follows = "nixpkgs_stable";
        # TODO(26.11): switch to nixos-26.11 once nixvim cuts it; main
        # targets 26.11 until then.
        nixvim.url = "github:nix-community/nixvim";
        nixvim.inputs.nixpkgs.follows = "nixpkgs";
      };
    };

    darwin = {
      # Must match nixpkgs release (26.11).
      # TODO(26.11): switch to nix-darwin-26.11 once it is cut; master
      # targets 26.11 until then.
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";

      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
      };
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    framework-inputmodule-rs-flake = {
      url = "github:alisonjenkins/framework-inputmodule-rs-flake";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    home-manager = {
      # Tracks the release matching our nixpkgs (26.11).
      # TODO(26.11): switch to release-26.11 once it is cut; master
      # targets 26.11 until then.
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/master";  # Updated from v0.4.2 for NixOS 25.11 compatibility
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lsfg-vk-flake = {
      url = "github:pabloaul/lsfg-vk-flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
      };
    };

    nur = {
      url = "github:nix-community/nur";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-26.11";
      # url = "path:/home/ali/git/nixpkgs";
    };

    # nix-gaming = {
    #   url = "github:fufexan/nix-gaming";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-apple-silicon = {
      # Asahi NixOS support module (kernel, m1n1+u-boot, firmware extraction).
      # Tracks unstable to stay in lockstep with the upstream linux-asahi
      # kernel cadence; pinning to 25.11 lags too far behind. Only consumed
      # by ali-mba-linux.
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    # nix-rosetta-builder = {
    #   url = "github:cpick/nix-rosetta-builder";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    steam-command-runner = {
      # gamescope shim in the Steam launch chain: applies per-game gamescope
      # arguments while keeping the Steam overlay and stop button working.
      # Follows nixpkgs_unstable because upstream's own flake tracks
      # nixpkgs-unstable for its naersk build.
      url = "github:alisonjenkins/steam-command-runner";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    tmux-sessionizer = {
      url = "github:alisonjenkins/tmux-sessionizer";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    # umu = {
    #   url = "git+https://github.com/Open-Wine-Components/umu-launcher/?dir=packaging\/nix&submodules=1";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    pipewire-screenaudio = {
      url = "github:IceDBorn/pipewire-screenaudio";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      # Follow nixpkgs_unstable: upstream's flake.nix tracks nixos-unstable,
      # and its package.nix takes ffmpeg_9. That attribute only exists on
      # unstable/master — the nixos-26.05 release branch tops out at ffmpeg_8
      # and will never gain a new major version — so following our main
      # nixpkgs breaks eval outright with "Function called without required
      # argument ffmpeg_9".
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    overseer = {
      url = "github:alisonjenkins/overseer";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, flake-parts, haumea, ... }:
    let
      lib = inputs.nixpkgs.lib;
      # Auto-discover all flake-parts modules from ./flake-modules/
      loaded = haumea.lib.load {
        src = ./flake-modules;
        loader = haumea.lib.loaders.path;
      };
      # Recursively flatten the nested attrset of paths into a list
      flatten = attrs:
        lib.foldlAttrs
          (acc: _: v:
            if builtins.isAttrs v then acc ++ flatten v
            else acc ++ [ v ])
          [ ]
          attrs;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = flatten loaded;
    };
}
