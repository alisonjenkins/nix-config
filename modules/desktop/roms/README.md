# ROM declarations

Organised as `<company>/<console>.nix`:

```
roms/
  nintendo/
    n64.nix
    gamecube.nix
  sega/
    megadrive.nix
  sony/
    ps2.nix
```

Every `.nix` file below this directory is auto-imported by
`modules/desktop/default.nix` as an ordinary NixOS module, and the module
system merges the `roms` attrsets together — so adding a console means adding
a file, with no edit anywhere else. The walk recurses, so nest further where a
console warrants it (say `nintendo/n64/first-party.nix`); the layout above is
convention, not a constraint. Markdown files like this one are skipped.

A console file looks like this:

```nix
# roms/nintendo/n64.nix
{
  modules.desktop.gaming.roms = {
    majoras-mask = {
      fileName = "mm.us.rev1.rom.z64";
      hash = "sha256-77E2WzrjYmBFFMD5oaLRH13IaIulvmYKN96/XjvkPys=";
      s3Uri = "s3://your-bucket/roms/n64/mm.us.rev1.rom.z64";
      sets = [ "n64" "recomp" ];
    };
  };
}
```

Handles are global, not per-file: two files declaring the same handle is a
merge conflict the module system rejects. Directory position carries no
meaning to the code — `sets` is what `fetch-rom --set` matches on, so declare
it even where it restates the path.

Nothing here is fetched at build time. `fetch-rom` downloads dumps on demand,
verifies each against `hash`, and adds it to the Nix store under
`fileName` — the two together determine the store path a consuming package's
`requireFile` looks for, so both must match that package exactly.

```bash
fetch-rom --list           # what is declared, and what is already present
fetch-rom --sets           # set names available
fetch-rom majoras-mask     # fetch one
fetch-rom --set n64        # fetch a whole set
fetch-rom --all            # fetch everything
```

Each declared dump also gets a GC root under `/nix/var/nix/gcroots`. Recomp
packages bake game data into their output rather than referencing the dump, so
nothing in the system closure keeps these alive; without those roots a
`nix-collect-garbage` would quietly delete them and the next rebuild that
touches such a package would fail.

New files must be `git add`ed before building. Untracked files are invisible to
a flake, so the auto-import will not see them.
