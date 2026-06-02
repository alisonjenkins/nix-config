{ config, lib, pkgs, ... }:
let
  cfg = config.modules.ollama;
  # nixpkgs removed `services.ollama.acceleration`; the accel backend is now
  # selected by package. Map our enum onto the matching ollama variant.
  accelerationPackages = {
    rocm = pkgs.ollama-rocm;
    cuda = pkgs.ollama-cuda;
    vulkan = pkgs.ollama-vulkan;
    cpu = pkgs.ollama;
  };
in
{
  options.modules.ollama = {
    enable = lib.mkEnableOption "ollama service";
    acceleration = lib.mkOption {
      type = lib.types.str;
      default = "rocm";
      description = "GPU acceleration type for Ollama";
    };
    rocmOverrideGfx = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Override the GPU model rocm detects, by setting HSA_OVERRIDE_GFX_VERSION.
        e.g. "11.5.1" for gfx1151 (AMD Ryzen AI Max "Strix Halo" iGPU).
      '';
    };
    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Models to pull via `ollama pull` once ollama.service has started
        (creates ollama-model-loader.service). Requires startAtBoot = true to
        run unattended, since the loader pulls in (and thus starts) ollama.service.
      '';
    };
    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start ollama at boot. When false, ollama is start-on-demand only
        (wantedBy is cleared). Must be true for loadModels to pull unattended.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      ollama = {
        enable = true;
        package = accelerationPackages.${cfg.acceleration} or pkgs.ollama;
        rocmOverrideGfx = cfg.rocmOverrideGfx;
        loadModels = cfg.loadModels;
        user = "ollama";
        group = "ollama";
      };
    };

    # Don't start ollama at boot unless asked — start manually or via other
    # services when needed.
    systemd.services.ollama.wantedBy = lib.mkIf (!cfg.startAtBoot) (lib.mkForce [ ]);

    environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
      lib.mkIf config.modules.base.enableImpermanence [
        {
          directory = "/var/lib/private/ollama";
          user = "ollama";
          group = "ollama";
          mode = "0700";
        }
      ];
  };
}
