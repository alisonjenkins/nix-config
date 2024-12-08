{ ...
}: {
  services = {
    displayManager = {
      autoLogin.enable = false;
      sddm = {
        enable = true;
        theme = "breeze";
        wayland.enable = false;
      };
    };

    xserver.enable = true;
  };

  systemd.services = {
    sddm-avatar = {
      description = "Service to copy or update users Avatars at startup.";
      wantedBy = [ "multi-user.target" ];
      before = [ "sddm.service" ];
      script = ''
        set -eu
        for user in /home/*; do
            username=$(basename "$user")
            user_icon_path="/home/$username/.face.icon"
            accountservice_icon_path="/var/lib/AccountsService/icons/$username"
            if [ -f "$user_icon_path" ]; then
                if [ ! -f "$accountservice_icon_path" ]; then
                    cp "$user_icon_path" "$accountservice_icon_path"
                else
                    if [ "$user_icon_path" -nt "$accountservice_icon_path" ]; then
                        cp "$user_icon_path" "$accountservice_icon_path"
                    fi
                fi
            fi
        done
      '';
      serviceConfig = {
        Type = "simple";
        User = "root";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };
    sddm = { after = [ "sddm-avatar.service" ]; };
  };
}
