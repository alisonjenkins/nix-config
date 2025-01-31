{
  services = {
    ollama = {
      enable = true;
      acceleration = "rocm";
      rocmOverrideGfx = "11.0.2";
      user = "ollama";
      group = "ollama";
    };
  };
}
