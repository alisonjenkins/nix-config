{
  description = "My flake";

  inputs = {
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    # niri.url = "github:YaLTeR/niri";
    eks-creds = {
      url = "github:alisonjenkins/eks-creds";
      inputs.nixpkgs.follows = "nixpkgs";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri-flake = {
      url = "github:sodiboo/niri-flake/27e012b4cd49e9ac438573ec7a6db3e5835828c3";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs_stable";
      };
    };
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs_lqx_pin.url = "github:nixos/nixpkgs/82000a14b7ec4009a25cbf8d3d49bcb4a6a85e41";
    nixpkgs_master.url = "github:nixos/nixpkgs";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs_old.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs_stable_darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs_unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixvirt = {
      url = "github:AshleyYakeley/NixVirt/v0.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ali-neovim = {
      url = "github:alisonjenkins/neovim-nix-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
        nixpkgs-master.follows = "nixpkgs_master";
        nixpkgs-stable.follows = "nixpkgs_stable";
      };
    };

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.11";
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
      url = "github:nix-community/home-manager/release-25.11";
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

    nixcord = {
      url = "github:kaylorben/nixcord/a8802dc23e112f98196a7daa68f0e246c7a0ea64";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
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
      url = "github:nixos/nixpkgs/nixos-25.11";
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

    rust-overlay = {
      url = "github:oxalica/rust-overlay";

      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
      };
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tmux-sessionizer = {
      url = "github:alisonjenkins/tmux-sessionizer/b9965259166c588479c01328e34f0fbc98fa03a2";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rust-overlay.follows = "rust-overlay";
      };
    };

    # umu = {
    #   url = "git+https://github.com/Open-Wine-Components/umu-launcher/?dir=packaging\/nix&submodules=1";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
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
