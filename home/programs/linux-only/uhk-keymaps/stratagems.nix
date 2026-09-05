{
  # (layer, key, stratagem name, I/J/K/L direction code) -- one entry per
  # Helldivers 2 stratagem, plus Reinforce. Codes confirmed against the
  # game's official wiki; key placement worked out live against the real
  # keyboard (see git log for the back-and-forth on ergonomics).
  stratagems = [
    # Fn: Orbitals + ship calls + Reinforce
    { layer = "fn"; key = "A"; name = "Orbital Precision Strike"; code = "LLI"; }
    { layer = "fn"; key = "G"; name = "Orbital Gatling Barrage"; code = "LKJII"; }
    { layer = "fn"; key = "B"; name = "Orbital Airburst Strike"; code = "LLL"; }
    { layer = "fn"; key = "X"; name = "Orbital Gas Strike"; code = "LLKL"; }
    { layer = "fn"; key = "E"; name = "Orbital EMS Strike"; code = "LLJK"; }
    { layer = "fn"; key = "S"; name = "Orbital Smoke Strike"; code = "LLKI"; }
    { layer = "fn"; key = "1"; name = "Orbital 120mm HE Barrage"; code = "LLKJLK"; }
    { layer = "fn"; key = "W"; name = "Orbital Walking Barrage"; code = "LKLKLK"; }
    { layer = "fn"; key = "3"; name = "Orbital 380mm HE Barrage"; code = "LKIIJKK"; }
    { layer = "fn"; key = "F"; name = "Orbital Napalm Barrage"; code = "LLKJLI"; }
    { layer = "fn"; key = "R"; name = "Orbital Laser"; code = "LKILK"; }
    { layer = "fn"; key = "Z"; name = "Orbital Railcannon Strike"; code = "LIKKL"; }
    { layer = "fn"; key = "D"; name = "Orbital Illumination Flare"; code = "LLJJ"; }
    { layer = "fn"; key = "C"; name = "Resupply"; code = "KKIL"; }
    { layer = "fn"; key = "Q"; name = "SOS Beacon"; code = "IKLI"; }
    { layer = "fn"; key = "V"; name = "Call In Super Destroyer"; code = "IIKKJLJL"; }
    { layer = "fn"; key = "T"; name = "Reinforce"; code = "IKLJI"; }
    # Fn2: Eagles + Sentries
    { layer = "fn2"; key = "R"; name = "Eagle Strafing Run"; code = "ILL"; }
    { layer = "fn2"; key = "A"; name = "Eagle Airstrike"; code = "ILKL"; }
    { layer = "fn2"; key = "S"; name = "Eagle Smoke Strike"; code = "ILIK"; }
    { layer = "fn2"; key = "F"; name = "Eagle Napalm Airstrike"; code = "ILKI"; }
    { layer = "fn2"; key = "1"; name = "Eagle 110mm Rocket Pods"; code = "ILIJ"; }
    { layer = "fn2"; key = "C"; name = "Eagle Cluster Bomb"; code = "ILKKL"; }
    { layer = "fn2"; key = "5"; name = "Eagle 500kg Bomb"; code = "ILKKK"; }
    { layer = "fn2"; key = "E"; name = "Eagle Rearm"; code = "IIJIL"; }
    { layer = "fn2"; key = "2"; name = "Eagle Gas Airstrike"; code = "ILJL"; }
    { layer = "fn2"; key = "G"; name = "MG Sentry"; code = "KILLI"; }
    { layer = "fn2"; key = "T"; name = "Gatling Sentry"; code = "KILJ"; }
    { layer = "fn2"; key = "Q"; name = "Autocannon Sentry"; code = "KILIJI"; }
    { layer = "fn2"; key = "B"; name = "Mortar Sentry"; code = "KILLK"; }
    { layer = "fn2"; key = "W"; name = "Rocket Sentry"; code = "KILLJ"; }
    { layer = "fn2"; key = "Z"; name = "Tesla Tower"; code = "KILIJL"; }
    { layer = "fn2"; key = "D"; name = "EMS Mortar Sentry"; code = "KILKL"; }
    { layer = "fn2"; key = "V"; name = "Laser Sentry"; code = "KILKIL"; }
    { layer = "fn2"; key = "3"; name = "Flame Sentry"; code = "KILKII"; }
    { layer = "fn2"; key = "X"; name = "Gas Mortar Sentry"; code = "KILKJ"; }
    { layer = "fn2"; key = "4"; name = "APW-1 Anti-Materiel Rifle"; code = "KJLIK"; }
    # Fn3: Support weapons, anti-armor/explosive
    { layer = "fn3"; key = "E"; name = "EAT-17 Expendable Anti-Tank"; code = "KKJIL"; }
    { layer = "fn3"; key = "R"; name = "GR-8 Recoilless Rifle"; code = "KJLLJ"; }
    { layer = "fn3"; key = "A"; name = "AC-8 Autocannon"; code = "KJKIIL"; }
    { layer = "fn3"; key = "S"; name = "FAF-14 Spear"; code = "KKIKK"; }
    { layer = "fn3"; key = "Q"; name = "LAS-99 Quasar Cannon"; code = "KKIJL"; }
    { layer = "fn3"; key = "B"; name = "RL-77 Airburst Rocket Launcher"; code = "KIIJL"; }
    { layer = "fn3"; key = "C"; name = "MLS-4X Commando"; code = "KJIKL"; }
    { layer = "fn3"; key = "G"; name = "S-11 Speargun"; code = "KLKJIL"; }
    { layer = "fn3"; key = "D"; name = "GL-52 De-Escalator"; code = "KLIJL"; }
    { layer = "fn3"; key = "F"; name = "EAT-700 Expendable Napalm"; code = "KKJIJ"; }
    { layer = "fn3"; key = "V"; name = "EAT-411 Leveller"; code = "KKJIK"; }
    { layer = "fn3"; key = "4"; name = "40-K Meltagun"; code = "KJIJJK"; }
    { layer = "fn3"; key = "T"; name = "B/MD C4 Pack"; code = "KLIILI"; }
    { layer = "fn3"; key = "2"; name = "GL-28 Belt-Fed Grenade Launcher"; code = "KJIJII"; }
    { layer = "fn3"; key = "Z"; name = "RS-422 Railgun"; code = "KLKIJL"; }
    { layer = "fn3"; key = "1"; name = "GL-21 Grenade Launcher"; code = "KJIJK"; }
    # Fn4: Support weapons, small arms/utility
    { layer = "fn4"; key = "G"; name = "MG-43 Machine Gun"; code = "KJKIL"; }
    { layer = "fn4"; key = "S"; name = "M-105 Stalwart"; code = "KJKIIJ"; }
    { layer = "fn4"; key = "F"; name = "FLAM-40 Flamethrower"; code = "KJIKI"; }
    { layer = "fn4"; key = "Z"; name = "LAS-98 Laser Cannon"; code = "KJKIJ"; }
    { layer = "fn4"; key = "C"; name = "ARC-3 Arc Thrower"; code = "KLKIJJ"; }
    { layer = "fn4"; key = "W"; name = "MG-206 Heavy Machine Gun"; code = "KJIKK"; }
    { layer = "fn4"; key = "B"; name = "CQC-20 Breaching Hammer"; code = "KJLJI"; }
    { layer = "fn4"; key = "E"; name = "PLAS-45 Epoch"; code = "KJIJL"; }
    { layer = "fn4"; key = "4"; name = "MGX-42 Bullet Storm"; code = "KJKLIJ"; }
    { layer = "fn4"; key = "D"; name = "CQC-9 Defoliation Tool"; code = "KJLLK"; }
    { layer = "fn4"; key = "T"; name = "TX-41 Sterilizer"; code = "KJIKJ"; }
    { layer = "fn4"; key = "1"; name = "MS-11 Solo Silo"; code = "KILKK"; }
    { layer = "fn4"; key = "V"; name = "B/FLAM-80 Cremator"; code = "KKLKII"; }
    { layer = "fn4"; key = "Q"; name = "M-1000 Maxigun"; code = "KJLKII"; }
    { layer = "fn4"; key = "R"; name = "CQC-1 One True Flag"; code = "KJLLI"; }
    # Fn5: Backpacks + Emplacements
    { layer = "fn5"; key = "S"; name = "B-1 Supply Pack"; code = "KJKIIK"; }
    { layer = "fn5"; key = "W"; name = "LIFT-850 Jump Pack"; code = "KIIKI"; }
    { layer = "fn5"; key = "B"; name = "SH-20 Ballistic Shield Backpack"; code = "KJKKIJ"; }
    { layer = "fn5"; key = "G"; name = ''"Guard Dog"''; code = "KIJILK"; }
    { layer = "fn5"; key = "R"; name = ''"Guard Dog" Rover''; code = "KIJILL"; }
    { layer = "fn5"; key = "D"; name = "Shield Generator Pack"; code = "KIJLJL"; }
    { layer = "fn5"; key = "V"; name = "Directional Shield"; code = "KIJLII"; }
    { layer = "fn5"; key = "F"; name = "Hot Dog"; code = "KIJIJJ"; }
    { layer = "fn5"; key = "E"; name = "Portable Hellbomb"; code = "KLIII"; }
    { layer = "fn5"; key = "C"; name = "K-9"; code = "KIJILJ"; }
    { layer = "fn5"; key = "Q"; name = "Hover Pack"; code = "KIIKJL"; }
    { layer = "fn5"; key = "T"; name = "Dog Breath"; code = "KIJILI"; }
    { layer = "fn5"; key = "X"; name = "Warp Pack"; code = "KJLKJL"; }
    { layer = "fn5"; key = "A"; name = "Anti-Personnel Minefield"; code = "KJIL"; }
    { layer = "fn5"; key = "4"; name = "Incendiary Mines"; code = "KJJK"; }
    { layer = "fn5"; key = "1"; name = "Anti-Tank Mines"; code = "KJII"; }
    { layer = "fn5"; key = "Z"; name = "Gas Mines"; code = "KJJL"; }
    { layer = "fn5"; key = "2"; name = "Shield Generator Relay"; code = "KIJLJK"; }
    { layer = "fn5"; key = "5"; name = "E/MG-101 HMG Emplacement"; code = "KIJLLJ"; }
    { layer = "fn5"; key = "3"; name = "E/GL-21 Grenadier Battlement"; code = "KLKJL"; }
    { layer = "fn5"; key = "6"; name = "E/AT-12 Anti-Tank Emplacement"; code = "KIJLLL"; }
  ];

  # The thumb cluster only has 4 keys, all already spoken for (Fn, Mod,
  # Space, Fn2) -- there's no physical key left to hold for Fn3/Fn4/Fn5.
  # UHK layers nest: a key ON the Fn layer can itself hold-switch into
  # another layer. The second key comes from the leftmost column (outside
  # the WASD block) so index/middle/ring stay on WASD while reaching it.
  layerAccess = [
    { layer = "fn"; index = 13; target = "fn3"; } # key left of A (Ctrl on base, unused on Fn)
    { layer = "fn"; index = 7; target = "fn4"; } # Tab
    { layer = "fn"; index = 26; target = "fn5"; } # key left of Z (2nd Ctrl on base, unused on Fn)
  ];
}
