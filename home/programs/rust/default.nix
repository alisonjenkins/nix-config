{ pkgs, ... }: {
  home.packages = if pkgs.stdenv.isDarwin then [
    # Minimal Rust setup for macOS to avoid rust-docs OOM issues
    pkgs.fenix.stable.minimalToolchain
    pkgs.bacon
  ] else [
      (pkgs.fenix.combine ([
      pkgs.fenix.stable.defaultToolchain
      pkgs.fenix.stable.rust-src
    ] ++ map (t: pkgs.fenix.targets.${t}.stable.rust-std) [
      "aarch64-apple-darwin"
      "aarch64-unknown-linux-gnu"
      "aarch64-unknown-linux-musl"
      "arm-unknown-linux-gnueabihf"
      "wasm32-unknown-emscripten"
      "wasm32-unknown-unknown"
      "x86_64-pc-windows-gnu"
      "x86_64-pc-windows-gnullvm"
      "x86_64-pc-windows-msvc"
      "x86_64-unknown-linux-gnu"
      "x86_64-unknown-linux-gnux32"
      "x86_64-unknown-linux-musl"
      "x86_64-unknown-linux-ohos"
    ]))
      pkgs.bacon
    ];
}
