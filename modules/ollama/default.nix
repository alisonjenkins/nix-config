{
  services = {
    ollama = {
      enable = true;
      acceleration = "rocm";
      user = "ollama";
      group = "ollama";
    };
  };
}
