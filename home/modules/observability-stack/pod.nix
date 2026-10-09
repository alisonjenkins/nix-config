# One pod, five containers on a shared network, played with `podman kube play`
# on every OS. Only the ports below are published, on cfg.listenAddress.
{ lib, cfg, yaml, dataDir, configs, grafana, ... }:
let
  inherit (cfg) ports;

  imageRef = name:
    let i = cfg.images.${name};
    in "${i.repo}:${i.tag}@${i.digest}";

  publish = port: {
    containerPort = port;
    hostPort = port;
    hostIP = cfg.listenAddress;
    protocol = "TCP";
  };

  configMount = {
    name = "config";
    mountPath = "/config";
    readOnly = true;
  };
  dataMount = name: path: {
    name = "${name}-data";
    mountPath = path;
  };

  # Rootless podman maps container root to the host user, so the bind-mounted
  # data directories stay owned by the user; the images default to other uids.
  container = { name, args ? [ ], env ? { }, published ? [ ], data ? null }: {
    inherit name args;
    image = imageRef name;
    imagePullPolicy = "IfNotPresent";
    securityContext.runAsUser = 0;
    env = lib.mapAttrsToList (n: v: { name = n; value = v; }) env;
    ports = map publish published;
    volumeMounts = [ configMount ] ++ lib.optional (data != null) (dataMount name data);
  };

  containers = [
    (container {
      name = "loki";
      args = [ "-config.file=/config/loki.yaml" ];
      published = [ ports.loki ];
      data = "/loki";
    })
    (container {
      name = "tempo";
      args = [ "-config.file=/config/tempo.yaml" ];
      published = [ ports.tempo ];
      data = "/var/tempo";
    })
    (container {
      name = "prometheus";
      args = configs.prometheusArgs;
      published = [ ports.prometheus ];
      data = "/prometheus";
    })
    (container {
      name = "grafana";
      env = grafana.env;
      published = [ ports.grafana ];
      data = "/var/lib/grafana";
    })
    (container {
      name = "collector";
      args = [ "--config=/config/collector.yaml" ];
      published = [ ports.otlpGrpc ports.otlpHttp ];
    })
  ];

  hostPath = path: {
    inherit path;
    type = "DirectoryOrCreate";
  };

  pod = {
    apiVersion = "v1";
    kind = "Pod";
    metadata = {
      name = "observability";
      labels.app = "observability-stack";
    };
    spec = {
      restartPolicy = "Always";
      inherit containers;
      volumes =
        [ { name = "config"; hostPath = { path = "${dataDir}/config"; type = "Directory"; }; } ]
        ++ map (n: { name = "${n}-data"; hostPath = hostPath "${dataDir}/${n}"; })
          [ "loki" "tempo" "prometheus" "grafana" ];
    };
  };
in
pod // {
  yamlFile = yaml.generate "observability-pod.yaml" pod;
}
