{ llama-cpp, fetchFromGitHub }:

# Upstream llama.cpp ahead of nixpkgs: neither nixpkgs unstable (9190) nor the
# v0.6.0 release knows the `gemma-embedding2` architecture, so
# llama-models.embeddinggemma-2-q8-0 fails to load there. Drop this once
# nixpkgs ships a llama.cpp that does.
llama-cpp.overrideAttrs (_: {
  version = "0.6.0-b7dafa0";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "b7dafa01e5f375c3010fb24b61a67329f957426a";
    hash = "sha256-BSzilolrnjIFGdI8HD0B8AH6GJ5joY294BKBXa7Nj/o=";
  };

  # The web UI's npm lockfile belongs to this source, not to whichever
  # nixpkgs revision supplies the base package; bump it with `rev`.
  npmDepsHash = "sha256-a17M+L3nLdRnN6WMB6imPFmwqG2g8uv+gwN0XTAUrf8=";

  # nixpkgs' patches target the 0.6.0 sources and are already in this commit;
  # applying them again aborts the build as "reversed or previously applied".
  patches = [ ];
})
