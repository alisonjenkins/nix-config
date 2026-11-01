{
  # (layer, key, stratagem name, U/D/L/R direction code) -- one entry per
  # Helldivers 2 stratagem, plus Reinforce. Codes confirmed against the
  # game's official wiki; key placement worked out live against the real
  # keyboard (see git log for the back-and-forth on ergonomics).
  stratagems = [
    # Fn: Orbitals + ship calls + Reinforce
    { layer = "fn"; key = "A"; name = "Orbital Precision Strike"; code = "RRU"; }
    { layer = "fn"; key = "G"; name = "Orbital Gatling Barrage"; code = "RDLUU"; }
    { layer = "fn"; key = "B"; name = "Orbital Airburst Strike"; code = "RRR"; }
    { layer = "fn"; key = "X"; name = "Orbital Gas Strike"; code = "RRDR"; }
    { layer = "fn"; key = "E"; name = "Orbital EMS Strike"; code = "RRLD"; }
    { layer = "fn"; key = "S"; name = "Orbital Smoke Strike"; code = "RRDU"; }
    { layer = "fn"; key = "1"; name = "Orbital 120mm HE Barrage"; code = "RRDLRD"; }
    { layer = "fn"; key = "W"; name = "Orbital Walking Barrage"; code = "RDRDRD"; }
    { layer = "fn"; key = "3"; name = "Orbital 380mm HE Barrage"; code = "RDUULDD"; }
    { layer = "fn"; key = "2"; name = "M-102 Fast Recon Vehicle"; code = "LDRDRDU"; }
    { layer = "fn"; key = "F"; name = "Orbital Napalm Barrage"; code = "RRDLRU"; }
    { layer = "fn"; key = "R"; name = "Orbital Laser"; code = "RDURD"; }
    { layer = "fn"; key = "Z"; name = "Orbital Railcannon Strike"; code = "RUDDR"; }
    { layer = "fn"; key = "D"; name = "Orbital Illumination Flare"; code = "RRLL"; }
    { layer = "fn"; key = "C"; name = "Resupply"; code = "DDUR"; }
    { layer = "fn"; key = "Q"; name = "SOS Beacon"; code = "UDRU"; }
    { layer = "fn"; key = "V"; name = "Call In Super Destroyer"; code = "UUDDLRLR"; }
    { layer = "fn"; key = "T"; name = "Reinforce"; code = "UDRLU"; }
    { layer = "fn"; key = "4"; name = "Orbital Confetti"; code = "RDDUUDDUU"; }
    # Fn2: Eagles + Sentries
    { layer = "fn2"; key = "R"; name = "Eagle Strafing Run"; code = "URR"; }
    { layer = "fn2"; key = "A"; name = "Eagle Airstrike"; code = "URDR"; }
    { layer = "fn2"; key = "S"; name = "Eagle Smoke Strike"; code = "URUD"; }
    { layer = "fn2"; key = "F"; name = "Eagle Napalm Airstrike"; code = "URDU"; }
    { layer = "fn2"; key = "1"; name = "Eagle 110mm Rocket Pods"; code = "URUL"; }
    { layer = "fn2"; key = "C"; name = "Eagle Cluster Bomb"; code = "URDDR"; }
    { layer = "fn2"; key = "5"; name = "Eagle 500kg Bomb"; code = "URDDD"; }
    { layer = "fn2"; key = "E"; name = "Eagle Rearm"; code = "UULUR"; }
    { layer = "fn2"; key = "2"; name = "Eagle Gas Airstrike"; code = "URLR"; }
    { layer = "fn2"; key = "G"; name = "MG Sentry"; code = "DURRU"; }
    { layer = "fn2"; key = "T"; name = "Gatling Sentry"; code = "DURL"; }
    { layer = "fn2"; key = "Q"; name = "Autocannon Sentry"; code = "DURULU"; }
    { layer = "fn2"; key = "B"; name = "Mortar Sentry"; code = "DURRD"; }
    { layer = "fn2"; key = "W"; name = "Rocket Sentry"; code = "DURRL"; }
    { layer = "fn2"; key = "Z"; name = "Tesla Tower"; code = "DURULR"; }
    { layer = "fn2"; key = "D"; name = "EMS Mortar Sentry"; code = "DURDR"; }
    { layer = "fn2"; key = "V"; name = "Laser Sentry"; code = "DURDUR"; }
    { layer = "fn2"; key = "3"; name = "Flame Sentry"; code = "DURDUU"; }
    { layer = "fn2"; key = "X"; name = "Gas Mortar Sentry"; code = "DURDL"; }
    { layer = "fn2"; key = "4"; name = "APW-1 Anti-Materiel Rifle"; code = "DLRUD"; }
    { layer = "fn2"; key = "6"; name = "Eagle Fly By"; code = "UDDUUDDUU"; }
    # Fn3: Support weapons, anti-armor/explosive
    { layer = "fn3"; key = "E"; name = "EAT-17 Expendable Anti-Tank"; code = "DDLUR"; }
    { layer = "fn3"; key = "R"; name = "GR-8 Recoilless Rifle"; code = "DLRRL"; }
    { layer = "fn3"; key = "A"; name = "AC-8 Autocannon"; code = "DLDUUR"; }
    { layer = "fn3"; key = "S"; name = "FAF-14 Spear"; code = "DDUDD"; }
    { layer = "fn3"; key = "Q"; name = "LAS-99 Quasar Cannon"; code = "DDULR"; }
    { layer = "fn3"; key = "B"; name = "RL-77 Airburst Rocket Launcher"; code = "DUULR"; }
    { layer = "fn3"; key = "C"; name = "MLS-4X Commando"; code = "DLUDR"; }
    { layer = "fn3"; key = "G"; name = "S-11 Speargun"; code = "DRDLUR"; }
    { layer = "fn3"; key = "D"; name = "GL-52 De-Escalator"; code = "DRULR"; }
    { layer = "fn3"; key = "F"; name = "EAT-700 Expendable Napalm"; code = "DDLUL"; }
    { layer = "fn3"; key = "V"; name = "EAT-411 Leveller"; code = "DDLUD"; }
    { layer = "fn3"; key = "4"; name = "40-K Meltagun"; code = "DLULLD"; }
    { layer = "fn3"; key = "T"; name = "B/MD C4 Pack"; code = "DRUURU"; }
    { layer = "fn3"; key = "2"; name = "GL-28 Belt-Fed Grenade Launcher"; code = "DLULUU"; }
    { layer = "fn3"; key = "Z"; name = "RS-422 Railgun"; code = "DRDULR"; }
    { layer = "fn3"; key = "1"; name = "GL-21 Grenade Launcher"; code = "DLULD"; }
    { layer = "fn3"; key = "W"; name = "AMW-20 Apex"; code = "DLLUDL"; }
    # Fn4: Support weapons, small arms/utility
    { layer = "fn4"; key = "G"; name = "MG-43 Machine Gun"; code = "DLDUR"; }
    { layer = "fn4"; key = "S"; name = "M-105 Stalwart"; code = "DLDUUL"; }
    { layer = "fn4"; key = "F"; name = "FLAM-40 Flamethrower"; code = "DLUDU"; }
    { layer = "fn4"; key = "Z"; name = "LAS-98 Laser Cannon"; code = "DLDUL"; }
    { layer = "fn4"; key = "C"; name = "ARC-3 Arc Thrower"; code = "DRDULL"; }
    { layer = "fn4"; key = "W"; name = "MG-206 Heavy Machine Gun"; code = "DLUDD"; }
    { layer = "fn4"; key = "B"; name = "CQC-20 Breaching Hammer"; code = "DLRLU"; }
    { layer = "fn4"; key = "E"; name = "PLAS-45 Epoch"; code = "DLULR"; }
    { layer = "fn4"; key = "4"; name = "MGX-42 Bullet Storm"; code = "DLDRUL"; }
    { layer = "fn4"; key = "D"; name = "CQC-9 Defoliation Tool"; code = "DLRRD"; }
    { layer = "fn4"; key = "T"; name = "TX-41 Sterilizer"; code = "DLUDL"; }
    { layer = "fn4"; key = "1"; name = "MS-11 Solo Silo"; code = "DURDD"; }
    { layer = "fn4"; key = "V"; name = "B/FLAM-80 Cremator"; code = "DDRDUU"; }
    { layer = "fn4"; key = "Q"; name = "M-1000 Maxigun"; code = "DLRDUU"; }
    { layer = "fn4"; key = "R"; name = "CQC-1 One True Flag"; code = "DLRRU"; }
    { layer = "fn4"; key = "X"; name = "LAS-44 Nova"; code = "DLRDD"; }
    # Fn5: Backpacks + Emplacements
    { layer = "fn5"; key = "S"; name = "B-1 Supply Pack"; code = "DLDUUD"; }
    { layer = "fn5"; key = "W"; name = "LIFT-850 Jump Pack"; code = "DUUDU"; }
    { layer = "fn5"; key = "B"; name = "SH-20 Ballistic Shield Backpack"; code = "DLDDUL"; }
    { layer = "fn5"; key = "G"; name = ''"Guard Dog"''; code = "DULURD"; }
    { layer = "fn5"; key = "R"; name = ''"Guard Dog" Rover''; code = "DULURR"; }
    { layer = "fn5"; key = "D"; name = "Shield Generator Pack"; code = "DULRLR"; }
    { layer = "fn5"; key = "V"; name = "Directional Shield"; code = "DULRUU"; }
    { layer = "fn5"; key = "F"; name = "Hot Dog"; code = "DULULL"; }
    { layer = "fn5"; key = "E"; name = "Portable Hellbomb"; code = "DRUUU"; }
    { layer = "fn5"; key = "C"; name = "K-9"; code = "DULURL"; }
    { layer = "fn5"; key = "Q"; name = "Hover Pack"; code = "DUUDLR"; }
    { layer = "fn5"; key = "T"; name = "Dog Breath"; code = "DULURU"; }
    { layer = "fn5"; key = "X"; name = "Warp Pack"; code = "DLRDLR"; }
    { layer = "fn5"; key = "A"; name = "Anti-Personnel Minefield"; code = "DLUR"; }
    { layer = "fn5"; key = "4"; name = "Incendiary Mines"; code = "DLLD"; }
    { layer = "fn5"; key = "1"; name = "Anti-Tank Mines"; code = "DLUU"; }
    { layer = "fn5"; key = "Z"; name = "Gas Mines"; code = "DLLR"; }
    { layer = "fn5"; key = "2"; name = "Shield Generator Relay"; code = "DULRLD"; }
    { layer = "fn5"; key = "5"; name = "E/MG-101 HMG Emplacement"; code = "DULRRL"; }
    { layer = "fn5"; key = "3"; name = "E/GL-21 Grenadier Battlement"; code = "DRDLR"; }
    { layer = "fn5"; key = "6"; name = "E/AT-12 Anti-Tank Emplacement"; code = "DULRRR"; }
  ];

  # First attempt chorded Fn3/4/5 through the Fn layer (hold Fn, then hold a
  # second key) -- clumsy under game pressure. Remapped on the real device to
  # single dedicated hold-keys straight off base, confirmed against a live
  # export: base module 1 index 0 (grave/backtick), 13 (left Ctrl) and 20
  # (ISO key left of Z) hold directly into Fn3/Fn4/Fn5, same as Fn/Mod/Fn2's
  # own base-layer hold keys.
  layerAccess = [
    { layer = "base"; index = 0; target = "fn3"; } # grave/backtick
    { layer = "base"; index = 13; target = "fn4"; } # key left of A (Ctrl on base)
    { layer = "base"; index = 20; target = "fn5"; } # ISO key left of Z (2nd Ctrl on base)
  ];
}
