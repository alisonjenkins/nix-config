{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
in
{
  # NixOS VM tests for Hetzner Karpenter node images.
  # Run with: nix build .#checks.x86_64-linux.hetzner-karpenter-node
  perSystem = { system, pkgs, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
      checks.hetzner-karpenter-node = pkgs.testers.runNixOSTest {
        name = "hetzner-karpenter-node";

        nodes.machine = { config, pkgs, lib, ... }: {
          imports = [
            (import ../lib/hetzner-node-services.nix {
              inherit pkgs lib;
              ciliumBootstrapManifest = ../flake-modules/hetzner-cilium-bootstrap.yaml;
              healScript = ../lib/hetzner-node-heal.sh;
            })
          ];

          # We can't import the full hetzner module (cloud-init datasource
          # requires Hetzner metadata) or hetzner-repart-image.nix. Instead
          # we import the shared lib/hetzner-node-services.nix so the VM test
          # exercises the REAL unit scripts [B30,V27].

          networking = {
            hostName = "hetzner-karpenter-node-amd64";
            firewall.enable = lib.mkForce false;
          };

          boot.kernel.sysctl = {
            "net.ipv4.ip_unprivileged_port_start" = 0;
            "net.core.rmem_max" = 5000000;
            "net.core.wmem_max" = 5000000;
          };

          environment.systemPackages = with pkgs; [
            btrfs-progs
            cryptsetup
            curl
            jq
            k3s
            nftables
            tailscale
            xfsprogs
            yq-go
          ];

          services.tailscale.enable = true;

          # Post-quantum SSH KEX [V12] — mirrors hetznerKarpenterNodeConfig.
          services.openssh.enable = true;
          services.openssh.settings.KexAlgorithms = [
            "mlkem768x25519-sha256"
            "sntrup761x25519-sha512@openssh.com"
            "curve25519-sha256"
            "curve25519-sha256@libssh.org"
          ];

          # Pre-pulled container images (same logic as hetznerKarpenterNodeConfig)
          systemd.tmpfiles.rules =
            let
              prepullImages = builtins.fromJSON (builtins.readFile ./hetzner-prepull-images.json);
              arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
              archImages = builtins.filter (img: img.arch == arch) prepullImages;
              pullImage = img: pkgs.dockerTools.pullImage {
                imageName = img.imageName;
                imageDigest = img.imageDigest;
                sha256 = img.hash;
                finalImageName = img.imageName;
                finalImageTag = img.imageTag;
              };
            in
              [ "d /var/lib/rancher/k3s/agent/images 0755 root root -" ]
              ++ map (img:
                let tar = pullImage img;
                    safeName = builtins.replaceStrings ["/" ":" "@"] ["_" "_" "_"] "${img.imageName}:${img.imageTag}";
                in "L /var/lib/rancher/k3s/agent/images/${safeName}.tar - - - - ${tar}"
              ) archImages;

          # In prod cloud-init writes /etc/karpenter-node.conf; the test has no
          # cloud-init, so seed it (ROLE=agent) as a writable regular file. Without
          # it the real k3s-state-volume unit blocks ~120s on its conf-wait, which
          # delays tailscaled (ordered after it) and fails the "tailscaled running"
          # subtest. A later subtest overwrites this file (regular, writable).
          system.activationScripts.seedKarpenterNodeConf.text = ''
            [ -e /etc/karpenter-node.conf ] || echo 'export ROLE=agent' > /etc/karpenter-node.conf
          '';

          system.stateVersion = "25.11";

          virtualisation = {
            memorySize = 2048;
            cores = 2;
          };
        };

        testScript = ''
          machine.start()
          machine.wait_for_unit("multi-user.target")

          # --- Core binaries ---

          with subtest("k3s binary is present and executable"):
              machine.succeed("k3s --version")

          with subtest("tailscale is present and executable"):
              machine.succeed("tailscale version")

          with subtest("yq is present (for parsing Hetzner metadata YAML)"):
              machine.succeed("yq --version")

          with subtest("curl is present"):
              machine.succeed("curl --version")

          with subtest("jq is present"):
              machine.succeed("jq --version")

          with subtest("no AWS-specific binaries present"):
              machine.fail("which aws 2>/dev/null")
              machine.fail("which amazon-ssm-agent 2>/dev/null")

          # --- Service configuration ---

          with subtest("firewall is disabled (Cilium eBPF is the firewall)"):
              machine.fail("iptables -L nixos-fw 2>/dev/null")

          with subtest("kernel sysctls are set"):
              machine.succeed("sysctl net.ipv4.ip_unprivileged_port_start | grep -q '= 0'")
              machine.succeed("sysctl net.core.rmem_max | grep -q '= 5000000'")
              machine.succeed("sysctl net.core.wmem_max | grep -q '= 5000000'")

          with subtest("tailscaled service is running"):
              machine.succeed("systemctl is-active tailscaled.service")

          # --- Tailscale bootstrap service ---

          with subtest("tailscale-bootstrap service exists with correct dependencies"):
              machine.succeed("systemctl cat tailscale-bootstrap.service")
              unit = machine.succeed("systemctl show tailscale-bootstrap.service --property=After")
              assert "tailscaled.service" in unit, f"Missing tailscaled.service dependency: {unit}"
              assert "cloud-init.service" in unit, f"Missing cloud-init.service dependency: {unit}"

          with subtest("tailscale-bootstrap runs before k3s-agent-bootstrap"):
              unit = machine.succeed("systemctl show k3s-agent-bootstrap.service --property=After")
              assert "tailscale-bootstrap.service" in unit, \
                  f"k3s-agent-bootstrap should run after tailscale-bootstrap: {unit}"

          with subtest("tailscale-bootstrap skips gracefully without auth key"):
              machine.succeed(
                  "cat > /etc/karpenter-node.conf << 'CONF'\n"
                  "export CLUSTER_NAME='test-cluster'\n"
                  "export SERVER_ENDPOINT='100.64.0.1'\n"
                  "export K3S_TOKEN='test-token'\n"
                  "CONF"
              )
              machine.succeed("systemctl restart tailscale-bootstrap.service")
              logs = machine.succeed("journalctl -u tailscale-bootstrap.service --no-pager -n 20")
              assert "No TAILSCALE_AUTH_KEY" in logs, \
                  f"Should skip without auth key. Logs:\n{logs}"

          # --- k3s agent bootstrap service ---

          with subtest("k3s-agent-bootstrap service exists with correct dependencies"):
              machine.succeed("systemctl cat k3s-agent-bootstrap.service")
              unit = machine.succeed("systemctl show k3s-agent-bootstrap.service --property=After")
              assert "cloud-init.service" in unit, f"Missing cloud-init.service dependency: {unit}"
              assert "network-online.target" in unit, f"Missing network-online.target dependency: {unit}"
              assert "tailscale-bootstrap.service" in unit, f"Missing tailscale-bootstrap dependency: {unit}"

          with subtest("bootstrap service uses Hetzner metadata (not AWS IMDS)"):
              import re
              unit_file = machine.succeed("cat /etc/systemd/system/k3s-agent-bootstrap.service")
              match = re.search(r'ExecStart=(/nix/store/\S+)', unit_file)
              assert match is not None, f"Could not find ExecStart path: {unit_file}"
              script = machine.succeed(f"cat {match.group(1)}")
              # Must use Hetzner metadata endpoint
              assert "169.254.169.254/hetzner/v1/metadata" in script, \
                  "Should use Hetzner metadata endpoint"
              # Must NOT use AWS IMDS
              assert "X-aws-ec2-metadata-token" not in script, \
                  "Should not use AWS IMDSv2"
              assert "aws ssm" not in script, \
                  "Should not use AWS SSM"

          with subtest("agent bootstrap uses cloud-provider=external (CCM owns providerID)"):
              unit_file2 = machine.succeed("cat /etc/systemd/system/k3s-agent-bootstrap.service")
              match2 = re.search(r'ExecStart=(/nix/store/\S+)', unit_file2)
              assert match2 is not None, f"Could not find ExecStart path: {unit_file2}"
              script = machine.succeed(f"cat {match2.group(1)}")
              # Legacy hetzner:/// self-set provider-id was dropped — hcloud CCM
              # sets providerID=hcloud://<id>; the agent runs cloud-provider=external
              # [B17].
              assert "cloud-provider=external" in script, \
                  "agent must run --kubelet-arg=cloud-provider=external (CCM owns providerID)"
              assert "provider-id=hetzner:///" not in script, \
                  "legacy hetzner:/// provider-id must NOT be self-set [B17]"
              assert "karpenter.sh/registered=true" in script, \
                  "Missing karpenter registration label"
              assert "topology.kubernetes.io/region" in script, \
                  "Missing topology region label"

          with subtest("bootstrap attempts to run (fails on missing metadata, expected)"):
              machine.succeed("systemctl restart k3s-agent-bootstrap.service || true")
              import time
              time.sleep(5)
              logs = machine.succeed("journalctl -u k3s-agent-bootstrap.service --no-pager -n 50")
              assert "Started K3s Agent Bootstrap" in logs, \
                  f"Service did not start. Logs:\n{logs}"

          # --- Cilium kernel requirements ---

          with subtest("kernel version is 6.12+ for netkit/tcx support"):
              version = machine.succeed("uname -r").strip()
              major, minor = [int(x) for x in version.split(".")[:2]]
              assert (major, minor) >= (6, 12), \
                  f"Kernel {version} too old, need >= 6.12 for netkit/tcx"

          with subtest("Cilium eBPF core: BPF subsystem is available"):
              machine.succeed("test -d /sys/fs/bpf")
              machine.succeed("ls /sys/fs/cgroup/")

          with subtest("Cilium eBPF core: BPF JIT is enabled at runtime"):
              jit = machine.succeed("cat /proc/sys/net/core/bpf_jit_enable").strip()
              assert jit in ("1", "2"), f"BPF JIT not enabled: {jit}"

          with subtest("Cilium: required kernel modules are loadable"):
              for mod in ["cls_bpf", "sch_fq", "sch_ingress", "xt_bpf"]:
                  machine.succeed(f"modprobe {mod}")

          with subtest("Cilium BBR: tcp_bbr module is available"):
              machine.succeed("modprobe tcp_bbr")
              machine.succeed("sysctl -w net.ipv4.tcp_congestion_control=bbr")
              result = machine.succeed("sysctl net.ipv4.tcp_congestion_control").strip()
              assert "bbr" in result, f"BBR not active: {result}"

          with subtest("Cilium: vxlan/geneve tunnel modules available"):
              machine.succeed("modprobe vxlan")
              machine.succeed("modprobe geneve")

          with subtest("Cilium: netfilter conntrack available"):
              machine.succeed("modprobe nf_conntrack")
              machine.succeed("test -d /proc/sys/net/netfilter")

          with subtest("Cilium netkit: tun device support"):
              machine.succeed("modprobe tun")
              machine.succeed("test -c /dev/net/tun")

          # --- Hetzner Cloud infrastructure ---

          with subtest("Hetzner: virtio kernel modules available"):
              for mod in ["virtio_net", "virtio_blk", "virtio_pci", "virtio_console"]:
                  machine.succeed(f"modprobe {mod}")

          with subtest("Hetzner: filesystem support for volumes"):
              machine.succeed("modprobe ext4")
              machine.succeed("modprobe xfs")
              machine.succeed("modprobe btrfs")
              machine.succeed("which mkfs.ext4")
              machine.succeed("which mkfs.xfs")
              machine.succeed("which mkfs.btrfs")

          # --- Container runtime ---

          with subtest("containerd: overlayfs available"):
              machine.succeed("modprobe overlay")
              machine.succeed(
                  "mkdir -p /tmp/overlay/{lower,upper,work,merged} && "
                  "mount -t overlay overlay -o lowerdir=/tmp/overlay/lower,"
                  "upperdir=/tmp/overlay/upper,workdir=/tmp/overlay/work "
                  "/tmp/overlay/merged && "
                  "umount /tmp/overlay/merged"
              )

          with subtest("containerd: veth support for container networking"):
              machine.succeed("modprobe veth")
              machine.succeed(
                  "ip link add veth-test type veth peer name veth-peer && "
                  "ip link del veth-test"
              )

          with subtest("containerd: bridge module available"):
              machine.succeed("modprobe bridge")

          with subtest("k3s: cgroup v2 is mounted"):
              machine.succeed("test -f /sys/fs/cgroup/cgroup.controllers")
              controllers = machine.succeed("cat /sys/fs/cgroup/cgroup.controllers")
              for ctrl in ["cpu", "memory", "pids"]:
                  assert ctrl in controllers, \
                      f"cgroup controller '{ctrl}' missing: {controllers}"

          with subtest("k3s: nftables available"):
              machine.succeed("which nft")
              machine.succeed("nft --version")
              machine.succeed("modprobe nf_tables")

          # --- WireGuard (for Tailscale and Cilium encryption) ---

          with subtest("WireGuard: kernel module available"):
              machine.succeed("modprobe wireguard")

          with subtest("WireGuard: interface can be created"):
              machine.succeed(
                  "ip link add wg-test type wireguard && "
                  "ip link del wg-test"
              )

          # --- Container image pre-pull ---

          with subtest("k3s pre-pulled images directory exists with image tars"):
              machine.succeed("test -d /var/lib/rancher/k3s/agent/images")
              count = machine.succeed("ls -1 /var/lib/rancher/k3s/agent/images/*.tar | wc -l").strip()
              assert int(count) > 0, f"No pre-pulled image tars found, expected at least 1, got {count}"
              machine.log(f"Found {count} pre-pulled image tar(s)")

          with subtest("k3s pre-pulled image tars are valid symlinks to nix store"):
              tars = machine.succeed("ls -1 /var/lib/rancher/k3s/agent/images/*.tar").strip().split("\n")
              for tar in tars:
                  target = machine.succeed(f"readlink -f {tar}").strip()
                  assert target.startswith("/nix/store/"), \
                      f"{tar} does not point to nix store: {target}"
                  machine.succeed(f"test -s {tar}")

          with subtest("Hetzner-specific images are pre-pulled"):
              tars_listing = machine.succeed("ls -1 /var/lib/rancher/k3s/agent/images/").strip()
              assert "hcloud-csi-driver" in tars_listing, \
                  f"Hetzner CSI driver not pre-pulled: {tars_listing}"
              assert "hcloud-cloud-controller-manager" in tars_listing, \
                  f"Hetzner CCM not pre-pulled: {tars_listing}"

          with subtest("k3s: agent subcommand is available"):
              result = machine.succeed("k3s agent --help 2>&1 || true")
              assert "agent" in result.lower(), f"k3s agent mode not available: {result}"

          with subtest("zram module available"):
              machine.succeed("modprobe zram")

          # --- role dispatch (one image, agent|server) ---

          with subtest("cryptsetup present (LUKS state volume)"):
              machine.succeed("cryptsetup --version")

          with subtest("agent bootstrap is role-guarded (skips when not agent)"):
              agent_unit = machine.succeed("cat /etc/systemd/system/k3s-agent-bootstrap.service")
              m = re.search(r'ExecStart=(/nix/store/\S+)', agent_unit)
              assert m, f"no ExecStart: {agent_unit}"
              script = machine.succeed(f"cat {m.group(1)}")
              assert 'ROLE:-agent' in script and 'skipping k3s-agent-bootstrap' in script, \
                  "agent bootstrap missing ROLE guard"

          # --- control-plane (role=server) ---

          with subtest("k3s-state-volume service exists, server-guarded, post-boot SSH unlock"):
              unit = machine.succeed("cat /etc/systemd/system/k3s-state-volume.service")
              m = re.search(r'ExecStart=(/nix/store/\S+)', unit)
              assert m, f"no ExecStart: {unit}"
              script = machine.succeed(f"cat {m.group(1)}")
              assert 'scsi-0HC_Volume_' in script, "must auto-discover the Hetzner volume"
              assert 'cryptsetup' in script and 'luksOpen' in script, "must LUKS-open the volume"
              assert 'systemd-ask-password' in script, "unlock must be post-boot SSH ask-password [V21]"
              assert '/var/lib/rancher/k3s' in script, "must mount the k3s state dir"
              assert 'ROLE:-agent' in script and 'not server' in script, "must be role-guarded"
              # Unlock must RETRY on a wrong passphrase, not fail the unit [B34] —
              # a failed k3s-state-volume cancels k3s-server-bootstrap (Requires=)
              # and wedges the CP boot. Loop re-prompts until the volume opens.
              assert 'until [ -e /dev/mapper/k3s-state' in script, \
                  "unlock must loop/retry on wrong passphrase, not fail the unit [B34]"
              # Node identity (/etc/rancher/node, the node password) must bind onto
              # the LUKS volume so it persists across a replace (matches the stored
              # hash → clean re-registration) AND stays encrypted [B31].
              assert '/etc/rancher/node' in script and 'etc-rancher-node' in script, \
                  "must bind /etc/rancher/node onto the LUKS volume [B31]"

          with subtest("k3s-server-bootstrap waits for the state volume"):
              after = machine.succeed("systemctl show k3s-server-bootstrap.service --property=Requires")
              assert "k3s-state-volume.service" in after, f"must require state volume: {after}"

          with subtest("k3s-server-bootstrap uses SQLite single-master flags (no etcd)"):
              unit = machine.succeed("cat /etc/systemd/system/k3s-server-bootstrap.service")
              m = re.search(r'ExecStart=(/nix/store/\S+)', unit)
              assert m, f"no ExecStart: {unit}"
              script = machine.succeed(f"cat {m.group(1)}")
              # strip comment lines so negative assertions don't match a comment that
              # merely mentions a flag (e.g. "# NO --cluster-init").
              code = "\n".join(l for l in script.splitlines() if not l.lstrip().startswith("#"))
              assert "k3s server" in code or "/k3s server" in code, "must run k3s server"
              assert "--cluster-init" not in code, "single master is SQLite — must NOT use etcd [V21]"
              assert "--secrets-encryption" in script, "missing --secrets-encryption [V5]"
              assert "--flannel-backend=none" in script, "Cilium CNI — flannel must be off [V4]"
              assert "--disable-kube-proxy" in script, "kube-proxy replacement [V4]"
              assert "--disable-network-policy" in script, "k3s netpol controller off [V4]"
              assert "--tls-san" in script, "must set tls-san (floating IP) [V3]"
              # API audit logging [B32-HARDEN]: log to the LUKS volume, policy file present.
              assert "audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log" in script, \
                  "kube-apiserver audit log must go to the LUKS volume [B32-HARDEN]"
              assert "audit-policy-file=/etc/rancher/k3s/audit-policy.yaml" in script, \
                  "kube-apiserver must reference the audit policy [B32-HARDEN]"

          with subtest("kube-apiserver audit policy present, secrets at Metadata not RequestResponse [B32-HARDEN]"):
              pol = machine.succeed("cat /etc/rancher/k3s/audit-policy.yaml")
              assert "kind: Policy" in pol, "audit policy must be a valid Policy doc"
              assert 'resources: ["secrets", "configmaps"]' in pol, "must audit secret access"
              # The whole policy is Metadata-only by design: RequestResponse anywhere
              # would log request/response BODIES (incl. secret values) to disk, so it
              # must never appear in this policy [PR#162].
              assert "RequestResponse" not in pol, \
                  "audit policy must never use RequestResponse (logs bodies incl. secrets) [PR#162]"

          with subtest("boot oneshots have TimeoutStartSec + Restart (no wedge on slow/flaky boot) [B27/B34]"):
              # Assert the EXACT configured timeout, not just "not the default" — a
              # regression to any too-small value must fail. systemd renders µs as a
              # human string: 300s -> "5min", 180s -> "3min".
              expected = {"tailscale-bootstrap": "5min", "floating-ip-bind": "3min"}
              for svc, want in expected.items():
                  props = machine.succeed(
                      f"systemctl show {svc}.service -p TimeoutStartUSec -p Restart"
                  )
                  assert f"TimeoutStartUSec={want}" in props, \
                      f"{svc} TimeoutStartSec must be {want}: {props}"
                  assert "Restart=on-failure" in props, f"{svc} must Restart=on-failure: {props}"

          with subtest("k3s-node-heal wrapper fails loudly on missing conf (set -e) [B34]"):
              unit = machine.succeed("cat /etc/systemd/system/k3s-node-heal.service")
              m = re.search(r'ExecStart=.*?(/nix/store/\S+heal\S*)', unit) or re.search(r'ExecStart=(/nix/store/\S+)', unit)
              assert m, f"no heal ExecStart: {unit}"
              wrapper = machine.succeed(f"cat {m.group(1)}")
              assert "set -euo pipefail" in wrapper, "heal wrapper must set -e (loud failure) [B34]"

          with subtest("post-quantum SSH KEX offered [V12]"):
              kex = machine.succeed("sshd -T 2>/dev/null | grep -i '^kexalgorithms'")
              assert "mlkem768x25519-sha256" in kex, f"PQC KEX missing: {kex}"
        '';
      };
    };
}
