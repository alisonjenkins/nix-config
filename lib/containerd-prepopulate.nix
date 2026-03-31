# Pre-populate a containerd image store at nix build time.
#
# Uses the containerd-prepopulate tool to import docker-archive tarballs into
# containerd's on-disk format (content store + boltdb metadata) using
# containerd's Go libraries directly — no daemon needed.
#
# The output directory can be placed at /var/lib/rancher/k3s/agent/containerd/
# in an AMI via systemd-repart contents, giving k3s instant access to images
# at boot without the tarball import step.
{ pkgs, lib, tarballs }:

let
  containerd-prepopulate = pkgs.callPackage (../pkgs/containerd-prepopulate) {};
in
pkgs.runCommand "containerd-prepopulated-store" {} ''
  mkdir -p $out
  ${containerd-prepopulate}/bin/containerd-prepopulate \
    -root $out \
    -namespace k8s.io \
    ${lib.concatMapStringsSep " \\\n    " (t: ''"${t}"'') tarballs}
''
