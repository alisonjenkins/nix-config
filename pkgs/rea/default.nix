{ lib, buildNpmPackage, importNpmLock, fetchurl, runCommand }:

let
  version = "6.4.0";

  npmTarball = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${version}.tgz";
    hash = "sha512-Vj1zWfSlna5bphGoaoI/TcVBuYvze9u+OyPC3Shz8YkBqaCTqB4COnnRoX7XDwMpwI24ZlFEel2yEj0k8LTWEQ==";
  };

  # The published tarball has dist/ pre-built but no lockfile; swap in a
  # trimmed package.json (runtime deps only) and our lock so npm ci works.
  src = runCommand "rea-src" { } ''
    tar xf ${npmTarball}
    cp ${./package.json} package/package.json
    cp ${./package-lock.json} package/package-lock.json
    cp -r package $out
  '';
in

buildNpmPackage {
  pname = "rea";
  inherit version src;

  # Per-dependency integrity hashes from the lockfile, so Renovate lockfile
  # bumps need no manual npmDepsHash edit (same as pkgs/cavemem).
  npmDeps = importNpmLock {
    package = lib.importJSON ./package.json;
    packageLock = lib.importJSON ./package-lock.json;
  };
  npmConfigHook = importNpmLock.npmConfigHook;

  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];

  # Skills ship inside the package; expose them where programs.rea and the
  # claude-code module can link them.
  postInstall = ''
    mkdir -p $out/share/rea
    ln -s $out/lib/node_modules/rea-agents/skills $out/share/rea/skills
  '';

  meta = {
    description = "Reverse engineer anything: MCP server and CLI for binaries, apps and runtime behaviour";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = lib.platforms.unix;
  };
}
