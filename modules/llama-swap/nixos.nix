# NixOS llama-swap: one OpenAI-compatible endpoint that queues requests and
# spawns a llama-server per model on demand. Wraps nixpkgs services.llama-swap;
# darwin.nix is the macOS equivalent under modules.llamaSwap.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.llama-swap;

  # llama-swap reads apiKeys entries through its ${env.VAR} macro, so the key
  # reaches the process via the environment and never enters the Nix store.
  keyEnvVar = "LLAMA_SWAP_API_KEY";

  # systemd hands the key file over as $CREDENTIALS_DIRECTORY/api-key (readable
  # under DynamicUser regardless of the file's owner). `-validate` runs in the
  # build sandbox with no credential, so it gets a placeholder; any other
  # invocation without the credential fails instead of starting unauthenticated.
  wrappedPackage = pkgs.writeShellApplication {
    name = "llama-swap";
    text = ''
      if [ "''${1:-}" = "-validate" ]; then
        export ${keyEnvVar}=validate-only
      else
        ${keyEnvVar}=$(<"$CREDENTIALS_DIRECTORY/api-key")
        export ${keyEnvVar}
      fi
      exec ${lib.getExe cfg.package} "$@"
    '';
  };

  loopbackAddresses = [ "127.0.0.1" "localhost" "::1" ];
  exposed = !(builtins.elem cfg.listenAddress loopbackAddresses) || cfg.firewallInterfaces != [ ];

  llamaServer = lib.getExe' cfg.llamaCppPackage "llama-server";

  # ${PORT} is llama-swap's macro, expanded when it spawns the child.
  mkCmd = m: lib.concatStringsSep " " (
    [
      llamaServer
      "--model" "${m.modelFile}"
      "--host" "127.0.0.1"
      "--port" "\${PORT}"
      "--gpu-layers" "999"
      "--jinja"
      "--ctx-size" (toString m.contextSize)
    ]
    ++ map lib.escapeShellArg m.extraArgs
  );

  membersOf = group: lib.attrNames (lib.filterAttrs (_: m: m.group == group) cfg.models);

  modelType = lib.types.submodule {
    options = {
      modelFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the GGUF model file llama-server loads.";
      };
      contextSize = lib.mkOption {
        type = lib.types.int;
        description = "Context window (`--ctx-size`) for this model.";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra llama-server arguments, one list element per argument.";
      };
      aliases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Alternative model ids clients may request.";
      };
      group = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Name of an entry in `modules.llama-swap.groups`. Models outside any
          group share llama-swap's default swap-exclusive slot.
        '';
      };
    };
  };

  groupType = lib.types.submodule {
    options = {
      swap = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether loading one member unloads the other members.";
      };
      exclusive = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether loading a member unloads models outside the group.";
      };
    };
  };
in
{
  options.modules.llama-swap = {
    enable = lib.mkEnableOption "llama-swap OpenAI-compatible model-swapping proxy";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-swap;
      defaultText = lib.literalExpression "pkgs.llama-swap";
      description = "The llama-swap package to run.";
    };

    llamaCppPackage = lib.mkOption {
      type = lib.types.package;
      # Master's llama.cpp, Vulkan: past the b9644 tool-call whitespace fix
      # (unstable was b9190), same build ali-desktop benchmarked.
      default = pkgs.master.llama-cpp.override { vulkanSupport = true; };
      defaultText = lib.literalExpression "pkgs.master.llama-cpp.override { vulkanSupport = true; }";
      description = "The llama.cpp package providing `llama-server`.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port llama-swap listens on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address llama-swap listens on. A non-loopback address requires
        `apiKeyFile`.
      '';
    };

    ttl = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Seconds a model stays loaded after its last request. null keeps it loaded.";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelType;
      default = { };
      description = "Models llama-swap can serve, keyed by the id clients request.";
    };

    groups = lib.mkOption {
      type = lib.types.attrsOf groupType;
      default = { };
      description = "Model groups; members are the models whose `group` names the group.";
    };

    firewallInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "tailscale0" ];
      description = ''
        Interfaces on which the port is opened. Never opened globally. A
        non-empty list requires `apiKeyFile`.
      '';
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/llama-swap-api-key";
      description = ''
        Runtime file holding the API key (for example a sops secret path),
        loaded through systemd LoadCredential so it never enters the Nix
        store. Requests to the inference endpoints without
        `Authorization: Bearer <key>` get 401. The web UI and log endpoints
        are not covered by llama-swap's key check, so keep the port on
        trusted interfaces.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = exposed -> cfg.apiKeyFile != null;
        message = "modules.llama-swap: listenAddress other than loopback, or firewallInterfaces, requires apiKeyFile.";
      }
      {
        assertion = lib.all (m: m.group == null || cfg.groups ? ${m.group}) (lib.attrValues cfg.models);
        message = "modules.llama-swap: a model's group is not declared in modules.llama-swap.groups.";
      }
    ];

    services.llama-swap = {
      enable = true;
      inherit (cfg) port listenAddress;
      package = if cfg.apiKeyFile != null then wrappedPackage else cfg.package;
      settings = {
        models = lib.mapAttrs (_: m:
          { cmd = mkCmd m; }
          // lib.optionalAttrs (m.aliases != [ ]) { inherit (m) aliases; }
          // lib.optionalAttrs (cfg.ttl != null) { inherit (cfg) ttl; }
        ) cfg.models;
        groups = lib.mapAttrs (name: g: g // { members = membersOf name; }) cfg.groups;
      } // lib.optionalAttrs (cfg.apiKeyFile != null) {
        apiKeys = [ "\${env.${keyEnvVar}}" ];
      };
    };

    systemd.services.llama-swap.serviceConfig = lib.mkIf (cfg.apiKeyFile != null) {
      LoadCredential = "api-key:${toString cfg.apiKeyFile}";
    };

    networking.firewall.interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
      allowedTCPPorts = [ cfg.port ];
    });
  };
}
