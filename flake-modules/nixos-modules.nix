{ ... }: {
  flake.nixosModules = {
    # Core modules
    audio-context-suspend = import ../modules/audio-context-suspend.nix;
    base = import ../modules/base;
    desktop = import ../modules/desktop;
    libvirtd = import ../modules/libvirtd;
    locale = import ../modules/locale;
    luksPCR15 = import ../modules/luksPCR15;
    ollama = import ../modules/ollama;
    rocm = import ../modules/rocm;
    servers = import ../modules/servers;
    vr = import ../modules/vr;

    # Network/VPN modules
    amnezia-vpn-gateway = import ../modules/amnezia-vpn-gateway;
    proxy-vpn-gateway = import ../modules/proxy-vpn-gateway;

    # Development modules
    development-web = import ../modules/development/web;

    # App profiles
    app-desktop = import ../app-profiles/desktop;
    app-desktop-1password = import ../app-profiles/desktop/1password;
    app-desktop-aws = import ../app-profiles/desktop/aws;
    app-desktop-kwallet = import ../app-profiles/desktop/kwallet;
    app-desktop-local-k8s = import ../app-profiles/desktop/local-k8s;
    app-desktop-kubernetes = import ../app-profiles/desktop/kubernetes;
    app-desktop-media = import ../app-profiles/desktop/media;
    app-desktop-podman = import ../app-profiles/desktop/containerisation/podman;
    app-desktop-greetd = import ../app-profiles/desktop/display-managers/greetd;
    app-desktop-greetd-regreet = import ../app-profiles/desktop/display-managers/greetd-regreet;
    app-desktop-sddm = import ../app-profiles/desktop/display-managers/sddm;
    app-desktop-wm-hyprland = import ../app-profiles/desktop/wms/hyprland;
    app-desktop-wm-plasma6 = import ../app-profiles/desktop/wms/plasma6;
    app-desktop-wm-river = import ../app-profiles/desktop/wms/river;
    app-desktop-wm-sway = import ../app-profiles/desktop/wms/sway;
    app-hardware-fingerprint-reader = import ../app-profiles/hardware/fingerprint-reader;
    app-hardware-touchpad = import ../app-profiles/hardware/touchpad;
    app-hardware-vr = import ../app-profiles/hardware/vr;
    app-k8s-master = import ../app-profiles/k8s-master;
    app-kvm-server = import ../app-profiles/kvm-server;
    app-storage-server = import ../app-profiles/storage-server;
  };
}
