# Aikar's flags + non-heap caps tuned for a 4 GiB k8s pod limit on Java 21.
#
#   2.5 GB heap + Metaspace 512m + CodeCache 192m + CompressedClassSpace 96m
#   + DirectMemory 512m + ~40 MB thread stacks (-Xss512k × ~80 threads)
#   + ~200 MB native ≈ 4.0 GB ceiling.
#
# Compared to CSC: Metaspace bumped 384m→512m (260+ mods vs ~150 in CSC),
# DirectMemory bumped 256m→512m (Sable physics keeps native FFI buffers
# resident for the moving sub-levels). If MSPT >50ms in soak test, bump pod
# limit + MINECRAFT_HEAP first; non-heap caps already have headroom.
''
  -XX:+UseG1GC
  -XX:+ParallelRefProcEnabled
  -XX:MaxGCPauseMillis=200
  -XX:+UnlockExperimentalVMOptions
  -XX:+DisableExplicitGC
  -XX:G1HeapWastePercent=5
  -XX:G1MixedGCCountTarget=4
  -XX:G1MixedGCLiveThresholdPercent=90
  -XX:G1RSetUpdatingPauseTimePercent=5
  -XX:SurvivorRatio=32
  -XX:+PerfDisableSharedMem
  -XX:MaxTenuringThreshold=1
  -XX:G1HeapRegionSize=8M
  -XX:G1NewSizePercent=30
  -XX:G1MaxNewSizePercent=40
  -XX:G1ReservePercent=20
  -XX:InitiatingHeapOccupancyPercent=15
  -Dusing.aikars.flags=https://mcflags.emc.gs
  -Daikars.new.flags=true
  -XX:MaxMetaspaceSize=512m
  -XX:ReservedCodeCacheSize=192m
  -XX:CompressedClassSpaceSize=96m
  -XX:MaxDirectMemorySize=512m
  -Xss512k
  -XX:CICompilerCount=2
''
