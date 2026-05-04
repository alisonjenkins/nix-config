# Recommended JVM Arguments

The pack ships no JVM args — launcher manifest formats (CurseForge `manifest.json`,
Modrinth `.mrpack`) don't carry them, so per-launcher configuration is required
once after import.

## Why

Distant Horizons broadcasts a chat warning when it detects G1GC at runtime:

```
Distant Horizons: G1 Garbage collector detected.
This can cause FPS stuttering.
It's recommended to use a concurrent garbage collector
like ZGC (Java 21+) or Shenandoah (Java 8 through 17)
for a smoother experience.
```

DH's async LOD-build pressure is an outlier vs. vanilla Minecraft — long G1
mixed-cycles stall the render thread. ZGC's sub-millisecond pauses fit
better. Aikar's flags (server-tuned G1) are *not* a good fit on the client
side.

## Heap

8 GiB heap recommended for the full pack (256 mods + 350-mod LOD render distance).
Set `-Xmx8G -Xms2G`. Lower heap = more GC pressure regardless of collector.

## Args by Java version

NeoForge 1.21.1 mandates Java 21+ (loader rejects ≤20). Pick the row that
matches the JDK your launcher uses:

| Java | Args |
|------|------|
| 21–23 | `-XX:+UseZGC -XX:+ZGenerational -Xmx8G -Xms2G` |
| 24    | `-XX:+UseZGC -XX:+ZGenerational -Xmx8G -Xms2G` (ZGenerational becomes a deprecation warning; still functional) |
| 25+   | `-XX:+UseZGC -Xmx8G -Xms2G` (generational is default; flag was removed) |

`-XX:+UnlockExperimentalVMOptions` is only needed before Java 21; on 21+ ZGC
is fully supported.

## Per-launcher steps

### Prism Launcher

1. Right-click instance → `Edit`.
2. `Settings` → `Java`.
3. Tick `Java arguments` (override global), paste the row from above.
4. Apply. Restart instance.

### CurseForge Launcher

1. Settings (gear icon) → `Minecraft`.
2. Set `Minecraft Maximum RAM` to 8192.
3. `Java settings` → `Additional Arguments`: paste the GC flags only
   (CurseForge handles `-Xmx`/`-Xms` from the RAM slider).

### MultiMC

Same as Prism (shared lineage).

### Vanilla launcher

Not supported — no NeoForge integration without manual install.

## Verifying

After restart, world load. Press `F3`. The bottom-right info column shows
the active GC. You want a line like:

```
GC: ZGC | Concurrent
```

If it still says `G1` the launcher didn't pick up the override — check
`Override` is ticked (Prism) or args have no leading whitespace (CurseForge).
