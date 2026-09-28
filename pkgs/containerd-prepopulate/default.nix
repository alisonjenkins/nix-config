{ buildGoModule, go_1_26 }:

# containerd/v2 v2.3.1 raised the go.mod directive to `go 1.26.3`, newer than
# nixpkgs' default buildGoModule toolchain (1.25.9). Override the builder's go
# so the module directive is satisfied.
(buildGoModule.override { go = go_1_26; }) {
  pname = "containerd-prepopulate";
  version = "0.1.0";
  src = ./.;
  # Goes stale on every Renovate go.mod/go.sum bump; Go has no hash-free
  # lockfile fetcher. To refresh: set it to "", run
  # `nix build .#packages.<system>.containerd-prepopulate` for the machine
  # you are on, and paste the "got:" hash back here. The hash is the same on
  # every system.
  vendorHash = "sha256-k/af0QBhmFMeTzOFkGCQa86qDjh4oeBLWc5uCFzt8Tg=";
}
