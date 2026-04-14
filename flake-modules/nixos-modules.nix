{ ... }: {
  flake.nixosModules = {
    # Core modules
    audio-context-suspend = import ../modules/audio-context-suspend.nix;
    aws = import ../modules/aws;
    base = import ../modules/base;
    hetzner = import ../modules/hetzner;
    btfs-streaming = import ../modules/btfs-streaming;
    desktop = import ../modules/desktop;
    libvirtd = import ../modules/libvirtd;
    locale = import ../modules/locale;
    luksPCR15 = import ../modules/luksPCR15;
    niks3-cache-push = import ../modules/niks3-cache-push;
    nohang = import ../modules/nohang;
    ollama = import ../modules/ollama;
    plymouth = import ../modules/plymouth;
    podman = import ../modules/podman;
    power-management = import ../modules/power-management;
    rocm = import ../modules/rocm;
    servers = import ../modules/servers;
    tts = import ../modules/tts;
    uresourced = import ../modules/uresourced;
    vr = import ../modules/vr;

    # Network/VPN modules
    amnezia-vpn-gateway = import ../modules/amnezia-vpn-gateway;
    proxy-vpn-gateway = import ../modules/proxy-vpn-gateway;

    # Development modules
    development-web = import ../modules/development/web;

    # Desktop modules
    desktop-1password = import ../modules/desktop-1password;
    desktop-aws-tools = import ../modules/desktop-aws-tools;
    desktop-base = import ../modules/desktop-base;
    desktop-greetd = import ../modules/desktop-greetd;
    desktop-greetd-regreet = import ../modules/desktop-greetd-regreet;
    desktop-kde-connect = import ../modules/desktop-kde-connect;
    desktop-kubernetes = import ../modules/desktop-kubernetes;
    desktop-kwallet = import ../modules/desktop-kwallet;
    desktop-local-k8s = import ../modules/desktop-local-k8s;
    desktop-media = import ../modules/desktop-media;
    desktop-sddm = import ../modules/desktop-sddm;
    desktop-wm-plasma6 = import ../modules/desktop-wm-plasma6;
    desktop-wm-sway = import ../modules/desktop-wm-sway;

    # Hardware modules
    hardware-fingerprint = import ../modules/hardware-fingerprint;
    hardware-touchpad = import ../modules/hardware-touchpad;

    # Server modules
    k8s-master = import ../modules/k8s-master;
    storage-server = import ../modules/storage-server;
  };
}
