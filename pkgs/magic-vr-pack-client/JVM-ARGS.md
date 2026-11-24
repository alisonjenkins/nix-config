# JVM arguments

Launcher pack formats carry no JVM arguments.
Set them once in your launcher after import.

## Security: Java 21.0.13.1 or newer is required

Use **Java 21.0.13.1 or newer**.
Older Java 21 builds are affected by CVE-2026-114938 ("Java2Shell").

Also add this flag, as defence in depth:

```
-XX:-UseBASE64Intrinsics
```

Check your version with `java -version`.
In Prism, the Java tab shows the version of each detected JDK.

## Memory

- Minimum: 8 GiB (8192 MiB) heap.
- Recommended: 10 GiB (10240 MiB) heap.
- Prism sets 10240 MiB itself on a fresh import, capped at 90% of your RAM.
- On a 16 GiB machine, use 8 GiB and close other apps.
- Set memory in the launcher, not with `-Xmx` in the arguments below.

## Arguments

Paste this line into your launcher:

```
-XX:+UseZGC -XX:+ZGenerational -XX:-UseBASE64Intrinsics
```

- ZGC keeps GC pauses short. Distant Horizons and VR both stutter on G1.
- On Java 24, `-XX:+ZGenerational` only prints a deprecation warning.
- On Java 25 and newer, drop `-XX:+ZGenerational`.

## Prism Launcher

1. Right-click the instance, then choose `Edit`.
2. Open `Settings`, then `Java`.
3. Pick a Java 21.0.13.1+ install under `Java installation`.
4. Tick `Java arguments` and paste the line above.
5. Under `Memory`, check `Maximum memory allocation` is 10240 MiB (8192 at least).

## CurseForge launcher

1. Open Settings, then `Minecraft`.
2. Set `Maximum RAM` to 10240 (8192 at least).
3. Under `Java settings`, set a Java 21.0.13.1+ install.
4. Paste the line above into `Additional Arguments`.

## Check it worked

Load a world and press `F3`.
The right-hand column should show `ZGC`.
