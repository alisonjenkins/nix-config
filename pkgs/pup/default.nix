{
  lib,
  stdenv,
  fetchurl,
}:

let
  pname = "pup";
  version = "0.64.1";

  sources = {
    "x86_64-linux" = {
      suffix = "Linux_x86_64.tar.gz";
      hash = "sha256-PMkyzCLv5JHQ7etZJZrNfNqTC3qmYB3cIG8rT+z/AVg=";
    };
    "aarch64-linux" = {
      suffix = "Linux_arm64.tar.gz";
      hash = "sha256-XCzrz8YQissP/GqV+mWGC0hGMsEQdwa8laMnYMMkXC4=";
    };
    "x86_64-darwin" = {
      suffix = "Darwin_x86_64.tar.gz";
      hash = "sha256-VB0RvU6aEYYPrh6kGef/XED9/wHb37rUlEuz4xxsMQE=";
    };
    "aarch64-darwin" = {
      suffix = "Darwin_arm64.tar.gz";
      hash = "sha256-haoFH6DA33c5QImu3Sfa6DxS7xvtHYFN8Yw1O5hFMj4=";
    };
  };

  src = sources.${stdenv.hostPlatform.system}
    or (throw "pup: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/DataDog/pup/releases/download/v${version}/pup_${version}_${src.suffix}";
    inherit (src) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 pup $out/bin/pup
    runHook postInstall
  '';

  meta = {
    description = "Datadog API CLI for AI agents (49 command groups, 300+ subcommands)";
    homepage = "https://github.com/DataDog/pup";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames sources;
    mainProgram = "pup";
  };
}
