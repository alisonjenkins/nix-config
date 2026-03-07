{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # unstable.kube-hunter
    unstable.cilium-cli
    unstable.cmctl
    unstable.fluxcd
    unstable.k9s
    unstable.kubectl
    unstable.kubernetes-helm
    unstable.pluto
    unstable.seabird
  ];
}












