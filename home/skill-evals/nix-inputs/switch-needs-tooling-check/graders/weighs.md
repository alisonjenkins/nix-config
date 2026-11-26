---
type: llm
---
The reply does not give an unconditional yes. It says the nightly update job, the update-policy script and flake-checker all read flake.lock and would break or need rework if the repo moved to tack. It names at least one concrete benefit tack would bring (such as deduplicating nixpkgs across inputs, patching an input without a fork, or freezing pins) and ties the recommendation to whether the user has that pain.
