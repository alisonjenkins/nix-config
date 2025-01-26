{ gpuType ? "", pkgs }: {
  home.packages = (if gpuType == "amd" then
    (with pkgs; [
      ollama-rocm
    ]) else if gpuType == "nvidia" then
    (with pkgs; [
      ollama-cuda
    ]) else
    (with pkgs; [
      ollama
    ]));
}
