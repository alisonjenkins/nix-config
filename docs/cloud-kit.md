# Cloud kit

Claude cloud sessions start from a fresh container with only the session's
repositories cloned. Without help they have none of the personal skills in
`home/skills/`, none of the user mandates home-manager writes to
`~/.claude/CLAUDE.md`, and few of the tools the skills' scripts call. The cloud
kit brings all three, for every repository, through the cloud environment's
setup script.

## How it works

1. `packages.<linux>.cloud-kit` (`flake-modules/cloud-kit.nix`,
   `pkgs/cloud-kit/default.nix`) is one store path holding:
   - `skills/`: every `home/skills/` family plus the anthropics/skills subset
     from `home/programs/claude-code/anthropic-skills.nix`.
   - `CLAUDE.md`: `gitStrategy`, `mkModelRouting "cloud"` and `workStyle` from
     `home/programs/shared-mandates.nix`. The `cloud` rung sends cheap work to
     a haiku sub-agent, since the local, Copilot and Gemini delegates are not
     installed in a cloud container.
   - `agents/`: `haiku-worker`, `aws-iam-debugger`, `git-commit-generator`
     and `pr-creator`.
   - `tools/bin`: the tools the skills' scripts need (`toolsFor` in the flake
     module), built from the same overlay-applied nixpkgs as the hosts.
   - `bin/cloud-kit-bootstrap`: the installer.
2. On every push to `main` that can change the kit,
   `.github/workflows/cloud-kit.yaml` builds it for x86_64-linux, pushes the
   closure to `cache.nixcache.org` (niks3), checks every path in the closure
   is in that cache or cache.nixos.org, and uploads the store path as the
   `x86_64-linux` asset of the `cloud-kit` release. Nothing is uploaded when
   the path is unchanged.
3. The cloud environment's setup script downloads that asset, substitutes the
   path from the caches, and runs
   `bin/cloud-kit-bootstrap`. The bootstrap links the skills and agents into
   `~/.claude`, writes the mandates into a marked block of
   `~/.claude/CLAUDE.md` (whatever else is in that file stays), and links into
   `/usr/local/bin` only the tools the image lacks, plus `yq` (the image's
   `yq` is not mikefarah/yq). The image's git, gh and curl stay, because they
   carry the environment's proxy configuration.

## Why a release asset holds the path

The cloud egress proxy refuses GitHub tarball and API downloads for
repositories not attached to the session. Every input in `flake.lock` is a
`github:` input, which Nix fetches as a tarball, so a cloud session cannot
evaluate this flake. A store path is a hash of the kit's contents, so it
changes with every skill edit and a session cannot guess it; binary caches
have no named "latest" entry. Something readable has to say which path is
current. Release downloads pass the proxy, so a fixed `cloud-kit` release
holds that one line. A branch would work too but clutters the branch list,
and a file on `main` would mean a bot commit after every skill change.

## Cloud environment

The Default environment's network allowlist must include
`cache.nixcache.org` (added 2026-11-07). Its setup script:

```bash
#!/bin/bash
# Claude cloud kit: skills, mandates and tools. See nix-config docs/cloud-kit.md.
url="${CLOUD_KIT_URL:-https://github.com/alisonjenkins/nix-config/releases/download/cloud-kit}"
if kit="$(curl -fsSL --connect-timeout 10 --max-time 30 "$url/$(uname -m)-linux")" \
  && nix-store --realise "$kit" --add-root /nix/var/nix/gcroots/cloud-kit \
    --option extra-substituters https://cache.nixcache.org \
    --option extra-trusted-public-keys nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak= \
    > /dev/null; then
  "$kit/bin/cloud-kit-bootstrap" || echo "cloud-kit: bootstrap failed" >&2
else
  echo "cloud-kit: could not fetch the kit; starting without it" >&2
fi
```

It never fails the session start. New sessions pick up the latest published
kit; a resumed session keeps what it had. The image must have Nix (the
default cloud image ships Nix 2.34).

## Changing what it ships

- A skill: edit `home/skills/`. Never edit the `cloud-kit` release; the next
  publish replaces its asset.
- A tool a skill script needs: add it to `toolsFor` in
  `flake-modules/cloud-kit.nix`.
- A mandate: edit `home/programs/shared-mandates.nix`; laptops and the cloud
  share it.

## Not shipped yet

- aarch64-linux: the package evaluates, but the workflow builds and publishes
  x86_64-linux only.
- `consult-opus` and `consult-top`: generated inside the claude-code home
  module, not available to the flake module without moving them out.
- Skills from packages (caveman, claude-statusbar, spec-kit init) and the
  memory-recall short listing.
- The delegate CLIs (`copilot`, `agy`, `llama-server`), which need machine
  sign-ins or a GPU.
