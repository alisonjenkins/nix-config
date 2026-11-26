---
description: 'Adoption advice recommends tack when the repo has the pains it fixes and nothing reads flake.lock.'
max_turns: 6
allowed_tools: [Skill, Read]
---
My personal Nix flake has 9 inputs, and `nix flake metadata` shows five separate nixpkgs revisions because most inputs bring their own. I also keep a fork of one input only to carry a single two-line patch, and rebasing that fork is a chore. Nobody else consumes this flake. There is no CI or bot; I bump inputs by hand on my laptop, where tack is installed. Should I switch this repo to tack? Under 200 words.
