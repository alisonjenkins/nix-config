{ config, lib, pkgs, ... }:
let
  cfg = config.modules.llama-cpp;

  instanceModule = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "this llama-server instance";
      package = lib.mkOption {
        type = lib.types.package;
        default = cfg.package;
        defaultText = lib.literalExpression "modules.llama-cpp.package";
        description = "llama-cpp package for this instance";
      };
      model = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to GGUF model file. Instance won't start until set.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = cfg.host;
        defaultText = lib.literalExpression "modules.llama-cpp.host";
        description = "Listen address";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "Listen port";
      };
      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra CLI flags passed to llama-server";
      };
    };
  };

  enabledInstances = lib.filterAttrs (_: i: i.enable && i.model != null) cfg.instances;
  allPorts = lib.mapAttrsToList (_: i: i.port) enabledInstances;
in
{
  options.modules.llama-cpp = {
    enable = lib.mkEnableOption "llama.cpp server(s)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      description = "Default llama-cpp package for all instances";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Default listen address for all instances";
    };
    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        IPs/CIDRs allowed to connect to any instance. Applied to all
        instance ports. Empty = localhost only.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables passed to all llama-server instances";
      example = lib.literalExpression ''
        {
          HSA_OVERRIDE_GFX_VERSION = "11.5.1";
        }
      '';
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf instanceModule;
      default = { };
      description = "Named llama-server instances, each on a separate port";
      example = lib.literalExpression ''
        {
          orchestrator = {
            enable = true;
            model = "/models/heavy.gguf";
            port = 8080;
            extraFlags = [ "--gpu-layers" "999" "--ctx-size" "32768" ];
          };
          agent = {
            enable = true;
            model = "/models/fast.gguf";
            port = 8081;
            extraFlags = [ "--gpu-layers" "999" "--ctx-size" "16384" ];
          };
        }
      '';
    };

    # Single-instance shorthand (backward compat)
    model = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Model path (single-instance shorthand). Sets instances.default.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port (single-instance shorthand)";
    };
    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags (single-instance shorthand)";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Map single-instance shorthand to instances.default
    (lib.mkIf (cfg.model != null) {
      modules.llama-cpp.instances.default = {
        enable = true;
        model = cfg.model;
        port = cfg.port;
        extraFlags = cfg.extraFlags;
      };
    })

    # Create a systemd service per enabled instance
    {
      systemd.services = lib.mapAttrs' (name: inst:
        lib.nameValuePair "llama-cpp-${name}" {
          description = "llama-server (${name})";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          inherit (cfg) environment;
          serviceConfig = {
            Type = "idle";
            KillSignal = "SIGINT";
            ExecStart = lib.concatStringsSep " " ([
              "${inst.package}/bin/llama-server"
              "--log-disable"
              "--host" inst.host
              "--port" (toString inst.port)
              "-m" (toString inst.model)
            ] ++ inst.extraFlags);
            Restart = "on-failure";
            RestartSec = 300;
            PrivateDevices = false;
            DynamicUser = true;
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
            NoNewPrivileges = true;
            PrivateMounts = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            MemoryDenyWriteExecute = true;
            LockPersonality = true;
            RemoveIPC = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" "~@privileged" ];
            SystemCallErrorNumber = "EPERM";
            ProtectProc = "invisible";
            ProtectHostname = true;
            ProcSubset = "pid";
          };
        }
      ) enabledInstances;

      networking.firewall.extraCommands = lib.mkIf (enabledInstances != { } && cfg.allowedIPs != [ ]) (
        lib.concatMapStringsSep "\n" (ip:
          lib.concatMapStringsSep "\n" (port:
            "iptables -A nixos-fw -p tcp --dport ${toString port} -s ${ip} -j nixos-fw-accept"
          ) allPorts
        ) cfg.allowedIPs
      );

      environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
        lib.mkIf config.modules.base.enableImpermanence [
          {
            directory = "/var/lib/private/llama-cpp";
            mode = "0700";
          }
        ];
    }
  ]);
}
