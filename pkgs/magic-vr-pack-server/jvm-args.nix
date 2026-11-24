# Server JVM flags for Java 21, written to user_jvm_args.txt. Heap (-Xms/-Xmx)
# comes from $MINECRAFT_HEAP in entrypoint.sh, default 9g.
#
# Generational ZGC: sub-millisecond pauses independent of heap size, so a
# 20-player server on an 8-10 GiB heap never hitches on a full collection.
# No AlwaysPreTouch: touching the whole heap at start delays a scale-from-zero
# boot while players wait. RSS still grows to the full heap, so size the pod
# for it. Pod limit guide: heap + ~2.5 GiB (metaspace, code cache, direct
# buffers, ZGC metadata, thread stacks), so 9g heap -> 12 GiB limit.
#
# -XX:-UseBASE64Intrinsics: mitigation for CVE-2026-114938 ("Java2Shell"),
# required by the pack's security baseline alongside JDK >= 21.0.13.1.
''
  -XX:+UseZGC
  -XX:+ZGenerational
  -XX:+DisableExplicitGC
  -XX:+PerfDisableSharedMem
  -XX:+UseStringDeduplication
  -XX:-UseBASE64Intrinsics
  -XX:MaxMetaspaceSize=768m
  -XX:ReservedCodeCacheSize=256m
  -XX:MaxDirectMemorySize=1g
  -Xss1m
''
