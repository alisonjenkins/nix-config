pkgs: {
  # Single MCP registration shared by Claude Code and Copilot CLI. REA needs
  # Ghidra 12.1.x and a full JDK 21+; nixos-unstable's ghidra-bin satisfies
  # `rea doctor --provider ghidra`.
  command = "${pkgs.rea}/bin/rea";
  args = [ "mcp" ];
  env = {
    GHIDRA_INSTALL_DIR = "${pkgs.unstable.ghidra-bin}/lib/ghidra";
    JAVA_HOME = "${pkgs.unstable.jdk21}/lib/openjdk";
  };
}
