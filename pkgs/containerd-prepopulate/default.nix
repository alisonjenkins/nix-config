{ buildGoModule, go_1_26 }:

# containerd/v2 v2.3.1 raised the go.mod directive to `go 1.26.3`, newer than
# nixpkgs' default buildGoModule toolchain (1.25.9). Override the builder's go
# so the module directive is satisfied.
(buildGoModule.override { go = go_1_26; }) {
  pname = "containerd-prepopulate";
  version = "0.1.0";
  src = ./.;
  vendorHash = "sha256-Crh6iKsZ+qc35JleOb5eANQljzMnKfKvQA10H/2U0uM=";
}
