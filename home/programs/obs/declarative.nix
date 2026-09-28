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
    home.activation.obsDeclarativeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      obsPatchIni() {
        local target="$1"; shift
        run mkdir -p "$(dirname "$target")"
        [ -e "$target" ] || run touch "$target"
        while [ "$#" -gt 0 ]; do
          run ${lib.getExe pkgs.crudini} --ini-options=nospace --set "$target" "$1" "$2" "$3"
          shift 3
        done
      }

      obsPatchJson() {
        local target="$1" declared="$2" secretPath="$3" secretFile="$4" tmp
        run mkdir -p "$(dirname "$target")"
        tmp=$(mktemp)
        if [ -n "$secretFile" ] && [ ! -r "$secretFile" ]; then
          warnEcho "obs: $secretFile unreadable, leaving the secret in $target unchanged"
          secretFile=""
        fi
        if ${lib.getExe pkgs.jq} -s \
            --arg secretPath "$secretPath" \
            --rawfile secret "''${secretFile:-/dev/null}" \
            --argjson hasSecret "$([ -n "$secretFile" ] && echo true || echo false)" '
          (.[0] // {}) * .[1]
          | if $hasSecret
            then setpath($secretPath | ltrimstr(".") | split("."); $secret | rtrimstr("\n"))
            else . end
        ' <(cat "$target" 2>/dev/null || echo '{}') "$declared" > "$tmp"; then
          run install -m 0600 "$tmp" "$target"
        else
          warnEcho "obs: $target is not valid JSON, left unpatched"
        fi
        rm -f "$tmp"
      }

      if ${pkgs.procps}/bin/pgrep -x '(obs|\.obs-wrapped)' >/dev/null; then
        warnEcho "obs: OBS is running and rewrites its config on exit; restart it after this switch or the patch below is lost"
      fi

      ${patchIni "${obsDir}/global.ini" cfg.global}
      ${patchIni "${obsDir}/user.ini" cfg.user}
      ${profileCmds}
      ${patchJson {
        target = "${obsDir}/plugin_config/obs-websocket/config.json";
        inherit (cfg.websocket) settings;
        secretPath = ".server_password";
        secretFile = cfg.websocket.passwordFile;
      }}
    '';
  };
}
