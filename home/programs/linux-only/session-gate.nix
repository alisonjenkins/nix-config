{ config, lib, ... }:
let
  # Negative match rather than the obvious ConditionEnvironment=XDG_CURRENT_DESKTOP=niri.
  #
  # Plasma exports XDG_CURRENT_DESKTOP=KDE into the systemd user manager from
  # startplasma, before graphical-session.target is reached, so the negative
  # test is reliable there. niri imports the variable from a spawn-at-startup
  # `systemctl --user import-environment`, which races graphical-session.target
  # — a positive test could therefore evaluate before the import and silently
  # skip the whole shell. With the negation the race fails safe: an unset (or
  # not-yet-imported) variable still starts the niri stack.
  gate.Unit.ConditionEnvironment = "!XDG_CURRENT_DESKTOP=KDE";
in
{
  # These units belong to the niri shell stack but are installed into the
  # generic graphical-session.target, so systemd starts them inside *any*
  # graphical session. On hosts that offer both niri and Plasma that means
  # noctalia painting a second shell over plasmashell, and swayidle locking
  # the session (and shelling out to `niri msg`, which has no socket to talk
  # to) while powerdevil/kscreenlocker are already handling idle.
  #
  # Each is keyed on its own enable so no half-defined unit is emitted on a
  # host that has one of them switched off.
  systemd.user.services = lib.mkMerge [
    (lib.mkIf config.programs.noctalia.enable { noctalia = gate; })

    # home-manager's swayidle module already pins
    # ConditionEnvironment=WAYLAND_DISPLAY, and the option is a single string,
    # so the two conditions cannot both be expressed — mkForce replaces it.
    # Nothing is lost in practice: both sessions on the dual hosts are Wayland,
    # and graphical-session.target is only ever reached from one of them.
    (lib.mkIf config.services.swayidle.enable {
      swayidle.Unit.ConditionEnvironment = lib.mkForce gate.Unit.ConditionEnvironment;
    })
  ];
}
