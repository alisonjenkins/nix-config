# Everything a Claude cloud session needs to work the way the laptops do: the
# personal skills (home/skills), the curated anthropics/skills subset, the
# user-level CLAUDE.md mandates, the agents, and the tools the skills' scripts
# call.
#
# Cloud sessions cannot evaluate this flake: their egress proxy refuses GitHub
# tarball fetches for repos not attached to the session, and every flake input
# is a github: tarball. So CI builds this kit, pushes its closure to
# cache.nixcache.org, and records the store path on the `cloud-kit` branch
# (see .github/workflows/cloud-kit.yaml). The session's setup script reads that
# path with git, substitutes it, and runs bin/cloud-kit-bootstrap.
{ lib
, runCommand
, writeText
, buildEnv
, makeWrapper
, bash
, coreutils
, findutils
, gawk
, anthropicSkills
, skills
, context
, agents
, tools
}:
let
  agentFiles = lib.mapAttrs (name: text: writeText "${name}.md" text) agents;
  toolsEnv = buildEnv {
    name = "cloud-kit-tools";
    paths = tools;
    pathsToLink = [ "/bin" ];
  };
in
runCommand "cloud-kit"
{
  nativeBuildInputs = [ makeWrapper ];
  passthru.tools = toolsEnv;
} ''
  mkdir -p $out/skills $out/agents $out/bin

  copy_skill() {
    if [ -e "$out/skills/$1" ]; then
      echo "cloud-kit: skill name '$1' is defined twice" >&2
      exit 1
    fi
    cp -rL "$2" "$out/skills/$1"
  }

  for d in ${anthropicSkills}/*; do
    copy_skill "$(basename "$d")" "$d"
  done
  ${lib.concatStrings (lib.mapAttrsToList (name: path: ''
    copy_skill ${lib.escapeShellArg name} ${path}
  '') skills)}

  cp ${writeText "CLAUDE.md" context} $out/CLAUDE.md
  ${lib.concatStrings (lib.mapAttrsToList (name: file: ''
    cp ${file} $out/agents/${name}.md
  '') agentFiles)}

  ln -s ${toolsEnv} $out/tools
  install -m755 ${./bootstrap.sh} $out/bin/.cloud-kit-bootstrap
  makeWrapper ${bash}/bin/bash $out/bin/cloud-kit-bootstrap \
    --add-flags $out/bin/.cloud-kit-bootstrap \
    --set CLOUD_KIT $out \
    --prefix PATH : ${lib.makeBinPath [ coreutils findutils gawk ]}
''
