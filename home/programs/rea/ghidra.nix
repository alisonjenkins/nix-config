pkgs: {
  # REA accepts Ghidra 12.1.x and a full JDK 21+. Shared with the rea-ghidra
  # check in flake-modules/packages.nix so the test exercises what ships.
  # Both come from the pinned nixpkgs_rea_pin (see flake.nix), not unstable.
  installDir = "${pkgs.rea-toolchain.ghidra-bin}/lib/ghidra";
  javaHome = "${pkgs.rea-toolchain.jdk21}/lib/openjdk";
}
