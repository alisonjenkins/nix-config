---
description: 'With nixpkgs pinned in both tack and flake.lock, the reply finds which one is used before bumping.'
max_turns: 6
allowed_tools: [Skill, Read]
---
This repo has `.tack/pins.toml` with a `nixpkgs` pin, and `flake.nix` also declares `inputs.nixpkgs`, which `flake.lock` locks. Bump nixpkgs for me. Under 120 words.
