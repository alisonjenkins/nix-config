pkgs: {
  # REA accepts Ghidra 12.1.x and a full JDK 21+. Shared with the rea-ghidra
  # check in flake-modules/packages.nix so the test exercises what ships.
  installDir = "${pkgs.unstable.ghidra-bin}/lib/ghidra";
  javaHome = "${pkgs.unstable.jdk21}/lib/openjdk";
}
