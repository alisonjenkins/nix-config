---
description: 'A tack repo bumps nixpkgs with tack, not nix flake update.'
max_turns: 4
allowed_tools: [Skill]
---
My repo has `.tack/pins.toml` with a `nixpkgs` pin. `flake.nix` has no `inputs` and its outputs do `(import ./.tack) { }`. `flake.lock` holds only the root node. Give me the one command to bump nixpkgs to the latest commit, and nothing else.
