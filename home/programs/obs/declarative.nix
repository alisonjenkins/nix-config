{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.obs-studio.declarative;
  obsDir = "${config.xdg.configHome}/obs-studio";
  jsonFormat = pkgs.formats.json { };

  iniValue = v:
    if builtins.isBool v then lib.boolToString v else toString v;

  iniType = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
    lib.types.bool
    lib.types.int
    lib.types.float
    lib.types.str
  ]));

  iniOption = file: lib.mkOption {
    type = iniType;
    default = { };
    example = { BasicWindow.SysTrayEnabled = true; };
    description = ''
      Section/key pairs patched into ${file} on activation. Keys not
      listed here are left as OBS wrote them.
    '';
  };

  jsonOption = file: lib.mkOption {
    inherit (jsonFormat) type;
    default = { };
    description = ''
      Deep-merged into ${file} on activation; keys not listed here are
      left as OBS wrote them.
    '';
  };

  secretFileOption = what: lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/run/user/1000/secrets/obs-${what}";
    description = ''
      Runtime path (e.g. a sops-nix secret) whose contents become the
      ${what}. Read at activation so the value never enters the store.
    '';
  };

  patchIni = target: sections:
    lib.optionalString (sections != { }) ''
      obsPatchIni ${lib.escapeShellArg target} ${lib.escapeShellArgs (lib.concatLists (
        lib.mapAttrsToList (section: keys:
          lib.concatLists (lib.mapAttrsToList (key: value: [ section key (iniValue value) ]) keys)
        ) sections
      ))}
    '';

  # $1 target, $2 declared JSON, $3 jq path for the secret, $4 secret file.
  patchJson = { target, settings, secretPath ? null, secretFile ? null }:
    lib.optionalString (settings != { } || secretFile != null) ''
      obsPatchJson ${lib.escapeShellArgs [
        target
        (jsonFormat.generate "obs-${baseNameOf target}" settings)
        (if secretPath == null then "" else secretPath)
        (if secretFile == null then "" else secretFile)
      ]}
    '';

  profileModule = { name, ... }: {
    options = {
      basic = iniOption "basic/profiles/<name>/basic.ini";
      streamEncoder = jsonOption "basic/profiles/<name>/streamEncoder.json";
      service = jsonOption "basic/profiles/<name>/service.json";
      streamKeyFile = secretFileOption "stream key (service.json settings.key)";
    };
    config.basic.General.Name = lib.mkDefault name;
  };

  profileCmds = lib.concatStrings (lib.mapAttrsToList (name: p:
    let dir = "${obsDir}/basic/profiles/${name}"; in
    patchIni "${dir}/basic.ini" p.basic
    + patchJson { target = "${dir}/streamEncoder.json"; settings = p.streamEncoder; }
    + patchJson {
      target = "${dir}/service.json";
      settings = p.service;
      secretPath = ".settings.key";
      secretFile = p.streamKeyFile;
    }
  ) cfg.profiles);

  sourceModule = {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        example = "pipewire-camera-source";
        description = "OBS source id, e.g. an input kind such as pipewire-camera-source.";
      };
      settings = lib.mkOption {
        inherit (jsonFormat) type;
        default = { };
        description = "Replaces the source's settings object wholesale.";
      };
    };
  };

  sceneSourceModule = {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "Desktop audio";
        description = "Source name, unique within the collection.";
      };
      id = lib.mkOption {
        type = lib.types.str;
        example = "pipewire-screen-capture-source";
        description = "OBS source id, e.g. an input kind.";
      };
      settings = lib.mkOption {
        inherit (jsonFormat) type;
        default = { };
        description = ''
          Merged over the settings OBS already wrote, so state OBS keeps
          there (a screen capture's portal RestoreToken) survives a switch.
        '';
      };
      audio = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the source produces audio, so it gets mixer tracks.";
      };
    };
  };

  audioSlotModule = {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "Game Audio";
        description = "Name shown in the OBS mixer.";
      };
      id = lib.mkOption {
        type = lib.types.str;
        example = "pipewire-audio-capture-application";
        description = "OBS source id the slot is switched to.";
      };
      settings = lib.mkOption {
        inherit (jsonFormat) type;
        default = { };
        description = "Replaces the slot's settings object wholesale.";
      };
    };
  };

  sceneCmds = lib.concatStrings (lib.mapAttrsToList (collection: c:
    lib.concatStrings (lib.mapAttrsToList (name: s:
      "obsPatchSource ${lib.escapeShellArgs [
        "${obsDir}/basic/scenes/${collection}.json"
        name
        s.id
        (jsonFormat.generate "obs-scene-source-settings.json" s.settings)
      ]}\n"
    ) c.sources)
    + lib.concatStrings (lib.mapAttrsToList (slot: s:
      "obsPatchAudioSlot ${lib.escapeShellArgs [
        "${obsDir}/basic/scenes/${collection}.json"
        slot
        s.name
        s.id
        (jsonFormat.generate "obs-audio-slot-settings.json" s.settings)
      ]}\n"
    ) c.audioSlots)
    + lib.concatStrings (lib.mapAttrsToList (scene: sources:
      "obsEnsureScene ${lib.escapeShellArgs [
        "${obsDir}/basic/scenes/${collection}.json"
        scene
        (jsonFormat.generate "obs-scene-sources.json" (map
          (s: { inherit (s) name id settings audio; })
          sources))
      ]}\n"
    ) c.scenes)
  ) cfg.sceneCollections);
in
{
  options.programs.obs-studio.declarative = {
    global = iniOption "global.ini";
    user = iniOption "user.ini";

    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule profileModule);
      default = { };
      description = ''
        Profiles keyed by their directory under basic/profiles. A profile
        that does not exist yet is created with General.Name set to the key.
      '';
    };

    sceneCollections = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.sources = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule sourceModule);
          default = { };
          description = "Scene sources keyed by name; each one's id and settings are patched in.";
        };
        options.scenes = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule sceneSourceModule));
          default = { };
          description = ''
            Scenes keyed by name, each a list of sources in stacking order.
            A scene or source missing from the collection is created and the
            sources are put in the scene; nothing is ever removed. The
            collection file must already exist and hold a scene, a scene item
            and a source, which new ones are copied from.
          '';
        };
        options.audioSlots = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule audioSlotModule);
          default = { };
          description = ''
            Global audio slots keyed by their collection-file key, e.g.
            DesktopAudioDevice1 or AuxAudioDevice1; each one is switched to
            the declared source kind. A slot absent from the file is skipped.
          '';
        };
      });
      default = { };
      description = ''
        Scene collections keyed by their file name under basic/scenes. A
        source is matched by name; sources not listed are left as OBS wrote
        them. A collection file that does not exist yet is not created.
      '';
    };

    websocket = {
      settings = jsonOption "plugin_config/obs-websocket/config.json";
      passwordFile = secretFileOption "obs-websocket server password";
    };
  };

  # OBS rewrites all of these files with runtime state (window geometry,
  # LastVersion, dock layout), so a read-only store symlink would break its
  # saves. Declared keys are patched in place instead; removing a key from
  # these options stops managing it but does not delete it from the file.
  config = lib.mkIf config.programs.obs-studio.enable {
    # Declared settings land in the world-readable store; secrets must come
    # from the *File options instead.
    assertions =
      lib.concatLists (lib.mapAttrsToList (name: p: [
        {
          assertion = !(p.service ? settings && p.service.settings ? key);
          message = "programs.obs-studio.declarative.profiles.${name}.service.settings.key would put the stream key in the Nix store; use streamKeyFile.";
        }
        {
          assertion = !(p.service ? settings && p.service.settings ? password);
          message = "programs.obs-studio.declarative.profiles.${name}.service.settings.password would put the RTMP auth password in the Nix store; set it in OBS instead.";
        }
      ]) cfg.profiles)
      ++ [{
        assertion = !(cfg.websocket.settings ? server_password);
        message = "programs.obs-studio.declarative.websocket.settings.server_password would put the password in the Nix store; use websocket.passwordFile.";
      }];

    home.activation.obsDeclarativeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      OBS_CRUDINI=${lib.getExe pkgs.crudini}
      OBS_JQ=${lib.getExe pkgs.jq}
      source ${./patch-config.sh}

      if ${pkgs.procps}/bin/pgrep -x '(obs|\.obs-wrapped)' >/dev/null; then
        warnEcho "obs: OBS is running and rewrites its config on exit; restart it after this switch or the patch below is lost"
      fi

      ${patchIni "${obsDir}/global.ini" cfg.global}
      ${patchIni "${obsDir}/user.ini" cfg.user}
      ${profileCmds}
      ${sceneCmds}
      ${patchJson {
        target = "${obsDir}/plugin_config/obs-websocket/config.json";
        inherit (cfg.websocket) settings;
        secretPath = ".server_password";
        secretFile = cfg.websocket.passwordFile;
      }}
    '';
  };
}
