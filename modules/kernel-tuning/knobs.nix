# The knob table: plain data, never reads `config`. Adding a knob is adding an
# entry; the module generates its boolean option and the emitters read it.
# Entry fields: category (security|performance|gaming|hardware), params,
# sysctls, sysctlPriority (optional, default 100; mkDefault is 1000, set it
# where a host already overrides the value), blacklistedModules, minKernel (version string or null), cost
# (none|low|medium|high), breaks (one line), conflictsWith (knob names).
# Sources: Arch wiki "Security" and "Gaming" pages, kernel-parameters.txt,
# Documentation/admin-guide/sysctl.
{
  # Already the default on nixpkgs and CachyOS x86_64 kernels
  # (INIT_ON_ALLOC_DEFAULT_ON), so enabling it there changes nothing; kept so
  # the intent is explicit and a kernel that drops the default stays covered.
  initOnAlloc = {
    category = "security";
    params = [ "init_on_alloc=1" ];
    minKernel = "5.3";
    cost = "low";
    breaks = "a few percent slower on allocation-heavy workloads";
    conflictsWith = [ "mitigationsOff" ];
  };

  initOnFree = {
    category = "security";
    params = [ "init_on_free=1" ];
    minKernel = "5.3";
    cost = "medium";
    breaks = "costs more than initOnAlloc, notable on memory-bound workloads";
    conflictsWith = [ "mitigationsOff" ];
  };

  # Already the default on x86_64 kernels (RANDOMIZE_KSTACK_OFFSET_DEFAULT); kept
  # for the same reason as initOnAlloc. Not default on aarch64 before 7.1.
  kstackRandomize = {
    category = "security";
    params = [ "randomize_kstack_offset=on" ];
    minKernel = "5.13";
    cost = "low";
    breaks = "small per-syscall overhead";
  };

  noVsyscall = {
    category = "security";
    params = [ "vsyscall=none" ];
    minKernel = "3.1";
    cost = "none";
    breaks = "binaries using the legacy vsyscall page, such as very old glibc";
  };

  pageShuffle = {
    category = "security";
    params = [ "page_alloc.shuffle=1" ];
    minKernel = "5.2";
    cost = "low";
    breaks = "nothing known";
  };

  slabNomerge = {
    category = "security";
    params = [ "slab_nomerge" ];
    minKernel = "3.18";
    cost = "low";
    breaks = "slightly higher slab memory use";
  };

  debugfsOff = {
    category = "security";
    params = [ "debugfs=off" ];
    minKernel = "5.9";
    cost = "none";
    breaks = "tools reading /sys/kernel/debug, such as some perf and tracing front ends";
  };

  kexecDisable = {
    category = "security";
    sysctls."kernel.kexec_load_disabled" = 1;
    minKernel = "3.14";
    cost = "none";
    breaks = "kexec and kdump crash capture; the setting is one-way until reboot";
  };

  noSysrq = {
    category = "security";
    sysctls."kernel.sysrq" = 0;
    minKernel = "2.6.12"; # earliest tree checked, the sysctl is older
    cost = "none";
    breaks = "magic SysRq recovery keys";
  };

  iommuIsolation = {
    category = "security";
    params = [
      "iommu=force"
      "amd_iommu=force_isolation"
      "intel_iommu=on"
    ];
    minKernel = "3.3"; # amd_iommu=force_isolation, the newest of the three
    cost = "low";
    breaks = "devices that misbehave behind an IOMMU, and PCI passthrough layouts that rely on shared groups";
  };

  nosmt = {
    category = "security";
    params = [ "nosmt" ];
    minKernel = "4.19"; # the generic handler (kernel/cpu.c) first appears in 4.19; before that the docs list it for s390 only
    cost = "high";
    breaks = "disables simultaneous multithreading where the CPU has it; a large throughput loss on parallel workloads";
    conflictsWith = [ "mitigationsOff" ];
  };

  mitigationsOff = {
    category = "performance";
    params = [ "mitigations=off" ];
    minKernel = "5.2";
    cost = "none";
    breaks = "disables CPU vulnerability mitigations; unsafe with untrusted code";
    conflictsWith = [ "nosmt" "initOnAlloc" "initOnFree" ];
  };

  splitLockMitigateOff = {
    category = "gaming";
    sysctls."kernel.split_lock_mitigate" = 0;
    minKernel = "6.2";
    cost = "low";
    breaks = "a split-lock-heavy process no longer gets throttled and can stall other cores";
  };

  compactionProactivenessOff = {
    category = "gaming";
    sysctls."vm.compaction_proactiveness" = 0;
    minKernel = "5.9";
    cost = "low";
    breaks = "less proactive huge page availability under fragmentation";
  };

  maxMapCountHigh = {
    category = "gaming";
    sysctls."vm.max_map_count" = 2147483642;
    minKernel = "2.6.12"; # earliest tree checked, the sysctl is older
    cost = "none";
    breaks = "nothing known; memory-mapping-heavy processes can use more maps";
  };

  # Disable where zram is the swap device: zswap would sit in front of it as a
  # second compressed cache and keep pages out of zram. nixpkgs kernels leave
  # zswap off, CachyOS builds default it on (ZSWAP_DEFAULT_ON).
  zswapOff = {
    category = "performance";
    params = [ "zswap.enabled=0" ];
    minKernel = "3.11"; # mm/zswap.c is absent at v3.10 and declares the enabled parameter at v3.11
    cost = "none";
    breaks = "no compressed cache in front of a disk swap device";
    conflictsWith = [ "zswapOn" ];
  };

  # For hosts whose swap is a disk or LVM device and have no zram. The
  # compressor is left at the kernel default (zstd in nixpkgs).
  zswapOn = {
    category = "performance";
    params = [ "zswap.enabled=1" ];
    minKernel = "3.11"; # same note as zswapOff
    cost = "low";
    breaks = "the compressed cache holds RAM and spends CPU; it is not meant to sit in front of zram";
    conflictsWith = [ "zswapOff" ];
  };

  # The knobs below were the gaming sysctl block in modules/desktop. minKernel
  # is the first mainline release that has the setting; the fleet runs 6.18+.
  # vm.page-cluster is not here: modules/base sets it whenever zram is on.
  watermarkBoostOff = {
    category = "performance";
    sysctls."vm.watermark_boost_factor" = 0;
    minKernel = "5.0";
    cost = "low";
    breaks = "reclaim no longer boosts watermarks after fragmentation, so huge page availability can drop";
  };

  watermarkScaleBalanced = {
    category = "performance";
    sysctls."vm.watermark_scale_factor" = 50;
    minKernel = "4.6";
    cost = "low";
    breaks = "kswapd wakes earlier and keeps more memory free (kernel default is 10)";
  };

  # kernel.sched_child_runs_first is deliberately absent: CachyOS's scheduler
  # has no such sysctl, so setting it was a silent no-op.
  schedAutogroup = {
    category = "performance";
    sysctls."kernel.sched_autogroup_enabled" = 1;
    minKernel = "2.6.38";
    cost = "none";
    breaks = "nothing known; groups tasks per session for desktop responsiveness";
  };

  cfsBandwidthSliceShort = {
    category = "gaming";
    sysctls."kernel.sched_cfs_bandwidth_slice_us" = 500;
    minKernel = "3.2";
    cost = "low";
    breaks = "more frequent bandwidth slice refills for cgroups with CPU quotas";
  };

  # Avoids khugepaged latency spikes. Set on the command line to match the
  # existing behaviour; the runtime form is
  # /sys/kernel/mm/transparent_hugepage/enabled, to move when a sysfs emitter
  # exists.
  thpMadvise = {
    category = "performance";
    params = [ "transparent_hugepage=madvise" ];
    minKernel = "2.6.38";
    cost = "low";
    breaks = "programs that do not madvise lose transparent huge pages";
  };

  # The vm.* block below was set directly in modules/base. Base turns these on
  # for every host; the mkDefault-priority ones (sysctlPriority 1000) keep the
  # priority base used so a host's mkForce or mkOverride still wins.
  # With zram as swap, swapping cold anon pages is cheap and frees RAM for cache.
  swappinessZram = {
    category = "performance";
    sysctls."vm.swappiness" = 100;
    sysctlPriority = 1000;
    cost = "low";
    breaks = "anonymous pages are swapped out eagerly; wrong on a disk swap device";
    conflictsWith = [ "swappinessDisk" ];
  };

  swappinessDisk = {
    category = "performance";
    sysctls."vm.swappiness" = 10;
    sysctlPriority = 1000;
    cost = "low";
    breaks = "cold anonymous pages stay resident until memory pressure";
    conflictsWith = [ "swappinessZram" ];
  };

  # zram is random-access RAM: swap-in readahead only wastes work.
  pageClusterZero = {
    category = "performance";
    sysctls."vm.page-cluster" = 0;
    sysctlPriority = 1000;
    cost = "none";
    breaks = "no swap-in readahead, which hurts a rotational swap device";
  };

  dirtyRatioLow = {
    category = "performance";
    sysctls."vm.dirty_ratio" = 20;
    cost = "low";
    breaks = "writers block once 20% of memory is dirty";
  };

  dirtyBackgroundRatioLow = {
    category = "performance";
    sysctls."vm.dirty_background_ratio" = 5;
    cost = "low";
    breaks = "background writeback starts at 5% dirty memory (kernel default 10), so writes reach disk sooner";
  };

  vfsCachePressureLow = {
    category = "performance";
    sysctls."vm.vfs_cache_pressure" = 25;
    cost = "low";
    breaks = "dentry and inode caches are reclaimed less eagerly (kernel default 100), using more RAM";
  };

  # The remaining generic sysctls below were set directly in modules/base.
  hpetUserFreqHigh = {
    category = "performance";
    sysctls."dev.hpet.max-user-freq" = 1000;
    cost = "none";
    breaks = "nothing; raises the per-user HPET interrupt rate cap (kernel default 64)";
  };

  dentryNegative = {
    category = "performance";
    sysctls."fs.dentry-negative" = 1;
    cost = "low";
    breaks = "negative dentries are kept after file deletion, using a little more RAM";
  };

  # dualpi2 needs kernel 6.17 or newer and the sch_dualpi2 module (base loads
  # it with the CachyOS kernel); a host that wants another qdisc overrides it.
  qdiscDualpi2 = {
    category = "performance";
    sysctls."net.core.default_qdisc" = "dualpi2";
    sysctlPriority = 1000;
    cost = "low";
    breaks = "new interfaces use dualpi2, which is wrong on a kernel without it (base loads sch_dualpi2 only when modules.base.enableCachyOSKernel is true) and replaces fq_codel/cake unless the host overrides it";
  };

  netRxQueueLarge = {
    category = "performance";
    sysctls = {
      "net.core.netdev_budget" = 600;
      "net.core.netdev_budget_usecs" = 8000;
      "net.core.netdev_max_backlog" = 16384;
    };
    cost = "low";
    breaks = "each softirq poll round runs longer (kernel defaults 300 packets, 2000 us), adding latency jitter under load";
  };

  socketBacklogHigh = {
    category = "performance";
    sysctls."net.core.somaxconn" = 8192;
    cost = "none";
    breaks = "listen queues may hold up to 8192 pending connections (kernel default 4096), using more memory under a connection flood";
  };

  socketBuffersLarge = {
    category = "performance";
    sysctls = {
      "net.core.optmem_max" = 65536;
      "net.core.rmem_default" = 1048576;
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_default" = 1048576;
      "net.core.wmem_max" = 16777216;
    };
    cost = "low";
    breaks = "every socket gets 1 MiB default buffers (well above the kernel default), so many idle sockets use more RAM";
  };

  udpMinBuffers = {
    category = "performance";
    sysctls = {
      "net.ipv4.udp_rmem_min" = 8192;
      "net.ipv4.udp_wmem_min" = 8192;
    };
    cost = "none";
    breaks = "each UDP socket is guaranteed 8 KiB buffers (kernel default 4096), using more memory with very many UDP sockets";
  };
}
