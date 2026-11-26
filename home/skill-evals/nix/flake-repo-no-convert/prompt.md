---
description: 'A plain flake.lock repo bumps an input with nix flake update and is not steered to tack.'
max_turns: 6
allowed_tools: [Skill, Read]
---
My repo is a normal flake: `flake.nix` declares `inputs.home-manager`, and `flake.lock` locks about 30 nodes. There is no `.tack` directory. What command bumps only home-manager? Keep it under 60 words.
