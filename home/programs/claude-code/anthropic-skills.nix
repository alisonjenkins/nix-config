# Curated subset of anthropics/skills, as a linkFarm of named skill directories.
# Shared by the claude-code home module and the cloud-kit flake package, so the
# laptop and cloud sessions load the same set.
#
# Curated rather than the whole repo: every skill's name+description loads into
# every agent/subagent, so the unused ones (algorithmic-art, brand-guidelines,
# canvas-design, theme-factory) are dropped to trim the subagent baseline.
{ fetchFromGitHub, linkFarm }:
let
  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "1ed29a03dc852d30fa6ef2ca53a67dc2c2c2c563";
    hash = "sha256-9FGubcwHcGBJcKl02aJ+YsTMiwDOdgU/FHALjARG51c=";
  };
  names = [
    # Document / office
    "docx" "pdf" "pptx" "xlsx"
    # Dev / web
    "frontend-design" "web-artifacts-builder" "webapp-testing" "mcp-builder"
    # Authoring / meta
    "doc-coauthoring" "internal-comms" "skill-creator"
    # Misc kept
    "slack-gif-creator"
  ];
in
# Each entry is a single skill *directory*, so it has to keep its own name:
# symlinkJoin merges directory contents, which would flatten every skill into
# the root (one winning SKILL.md, colliding scripts/ and reference/ dirs).
# linkFarm names each one, and consumers then merge those named dirs.
linkFarm "anthropic-skills" (
  map (n: {
    name = n;
    path = "${src}/skills/${n}";
  }) names
)
