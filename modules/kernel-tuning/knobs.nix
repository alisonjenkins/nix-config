# The knob table: plain data, never reads `config`. Adding a knob is adding an
# entry; the module generates its boolean option and the emitters read it.
# Entry fields: category (security|performance|gaming|hardware), params,
# sysctls, blacklistedModules, minKernel (version string or null), cost
# (none|low|medium|high), breaks (one line), conflictsWith (knob names).
# Sources: Arch wiki "Security" and "Gaming" pages, kernel-parameters.txt,
# Documentation/admin-guide/sysctl.
{
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
    minKernel = null; # UNVERIFIED min kernel
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
    minKernel = null; # UNVERIFIED min kernel
    cost = "low";
    breaks = "slightly higher slab memory use";
  };

  debugfsOff = {
    category = "security";
    params = [ "debugfs=off" ];
    minKernel = null; # UNVERIFIED min kernel
    cost = "none";
    breaks = "tools reading /sys/kernel/debug, such as some perf and tracing front ends";
  };

  kexecDisable = {
    category = "security";
    sysctls."kernel.kexec_load_disabled" = 1;
    minKernel = null; # UNVERIFIED min kernel
    cost = "none";
    breaks = "kexec and kdump crash capture; the setting is one-way until reboot";
  };

  noSysrq = {
    category = "security";
    sysctls."kernel.sysrq" = 0;
    minKernel = null; # UNVERIFIED min kernel
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
    minKernel = null; # UNVERIFIED min kernel
    cost = "low";
    breaks = "devices that misbehave behind an IOMMU, and PCI passthrough layouts that rely on shared groups";
  };

  nosmt = {
    category = "security";
    params = [ "nosmt" ];
    minKernel = null; # UNVERIFIED min kernel
    cost = "high";
    breaks = "halves the hardware threads; large loss on parallel workloads";
    conflictsWith = [ "mitigationsOff" ];
  };

  mitigationsOff = {
    category = "performance";
    params = [ "mitigations=off" ];
    minKernel = null; # UNVERIFIED min kernel
    cost = "none";
    breaks = "disables CPU vulnerability mitigations; unsafe with untrusted code";
    conflictsWith = [ "nosmt" "initOnAlloc" "initOnFree" ];
  };

  splitLockMitigateOff = {
    category = "gaming";
    sysctls."kernel.split_lock_mitigate" = 0;
    minKernel = null; # UNVERIFIED min kernel
    cost = "low";
    breaks = "a split-lock-heavy process no longer gets throttled and can stall other cores";
  };

  compactionProactivenessOff = {
    category = "gaming";
    sysctls."vm.compaction_proactiveness" = 0;
    minKernel = null; # UNVERIFIED min kernel
    cost = "low";
    breaks = "less proactive huge page availability under fragmentation";
  };

  maxMapCountHigh = {
    category = "gaming";
    sysctls."vm.max_map_count" = 2147483642;
    minKernel = null; # UNVERIFIED min kernel
    cost = "none";
    breaks = "nothing known; memory-mapping-heavy processes can use more maps";
  };
}
