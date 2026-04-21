{ lib, buildNpmPackage, fetchurl, runCommand, python3, pkg-config }:

let
  npmTarball = fetchurl {
    url = "https://registry.npmjs.org/cavemem/-/cavemem-0.1.3.tgz";
    hash = "sha256-Lg3jslcOak/WDBLhseZ64x5/IlKvzsAKsNYHgB+Vwd4=";
  };

  # Prepare source: npm tarball (pre-built dist) + our lock file + simplified package.json.
  # The published tarball has dist/ pre-built but lacks a package-lock.json.
  # We also strip workspace devDeps and optionalDeps so npm ci doesn't fail.
  src = runCommand "cavemem-src" { } ''
    tar xf ${npmTarball}
    cp ${./package.json} package/package.json
    cp ${./package-lock.json} package/package-lock.json
    cp -r package $out
  '';
in

buildNpmPackage {
  pname = "cavemem";
  version = "0.1.3";

  inherit src;

  npmDepsHash = "sha256-3oJBKbRK0MjB73xyW+RYMRGAYmK5VegJiG8Y0TRDtLQ=";

  # dist/ is pre-built in the npm tarball; skip the TypeScript build step
  dontNpmBuild = true;

  # better-sqlite3 compiles its own bundled sqlite3 — needs a C++ toolchain and Python
  nativeBuildInputs = [ python3 pkg-config ];

  meta = {
    description = "Cross-agent persistent memory for coding assistants (Claude Code, Cursor, Gemini)";
    homepage = "https://github.com/JuliusBrussee/cavemem";
    license = lib.licenses.mit;
    mainProgram = "cavemem";
    platforms = lib.platforms.unix;
  };
}
