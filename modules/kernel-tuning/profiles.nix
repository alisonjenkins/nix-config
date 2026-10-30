# Named sets of knob names. A profile only ever switches knobs on, so profiles
# compose by union. Never add `lockdown` here: laptops hibernate.
let
  hardenedWorkstation = [
    "kstackRandomize"
    "initOnAlloc"
    "noVsyscall"
    "pageShuffle"
    "slabNomerge"
    "debugfsOff"
    "kexecDisable"
  ];
in
{
  hardened-workstation = hardenedWorkstation;
  hardened-server = hardenedWorkstation;
  gaming = [
    "splitLockMitigateOff"
    "compactionProactivenessOff"
    "maxMapCountHigh"
  ];
}
