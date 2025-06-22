{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    unstable.cilium-cli
    unstable.cmctl
    unstable.fluxcd
    unstable.k9s
    # unstable.kube-hunter
    unstable.kubectl
    unstable.kubernetes-helm
    unstable.pluto
    unstable.seabird
  ];
}












