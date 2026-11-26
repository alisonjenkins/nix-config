---
type: llm
---
The reply says patching a pin (`tack patch add`) needs tack 2.x and that the installed nixpkgs build lacks it, so the user must get a newer tack (for example from upstream) or use another route such as a fork pin. It does not tell the user to hand-edit `pins.lock.json`, and it does not present `tack patch add` as something that will work with the installed CLI.
