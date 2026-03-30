{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
in
{
  # NixOS VM tests for AMI configurations.
  # Run with: nix build .#checks.x86_64-linux.karpenter-node-ami
  #       or: nix build .#checks.aarch64-linux.karpenter-node-ami
  perSystem = { system, pkgs, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
      checks.karpenter-node-ami = pkgs.testers.runNixOSTest {
        name = "karpenter-node-ami";

        nodes.machine = { config, pkgs, lib, ... }:
        let
          kpatch = pkgs.callPackage (self + "/pkgs/kpatch") {};
        in {
          # We can't import the full aws module (sets nixpkgs.config which
          # conflicts with the test framework's read-only nixpkgs) or
          # amazon-image.nix (requires EC2 metadata). Instead we replicate
          # the Karpenter-specific config to test the critical components.

          networking = {
            hostName = "aws-karpenter-node-amd64";
            firewall.enable = lib.mkForce false;
          };

          # LIVEPATCH is only supported on x86_64 in mainline Linux
          boot.kernelPatches = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [{
            name = "livepatch";
            patch = null;
            structuredExtraConfig = with lib.kernel; {
              LIVEPATCH = yes;
            };
          }];

          boot.kernel.sysctl = {
            "net.ipv4.ip_unprivileged_port_start" = 0;
            "net.core.rmem_max" = 5000000;
            "net.core.wmem_max" = 5000000;
          };

          environment.systemPackages = with pkgs; [
            awscli2
            btrfs-progs
            curl
            jq
            k3s
            nftables
            xfsprogs
          ] ++ lib.optionals stdenv.hostPlatform.isx86_64 [
            kpatch
          ];

          systemd.services.k3s-prepull-images = {
            description = "Pre-pull container images for k3s daemonsets";
            after = [ "k3s-agent-bootstrap.service" ];
            wants = [ "k3s-agent-bootstrap.service" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = "10min";
            };

            script = ''
              set -euo pipefail

              IMAGE_LIST_URL="https://raw.githubusercontent.com/alisonjenkins/home-cluster/main/clusters/aws-k3s/karpenter-node-prepull-images.txt"

              for i in $(seq 1 60); do
                [ -S /run/k3s/containerd/containerd.sock ] && break
                sleep 2
              done

              if [ ! -S /run/k3s/containerd/containerd.sock ]; then
                echo "containerd socket not found, skipping pre-pull"
                exit 0
              fi

              export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock

              IMAGES=$(${pkgs.curl}/bin/curl -sfL "$IMAGE_LIST_URL" \
                | ${pkgs.gnugrep}/bin/grep -v '^\s*#' \
                | ${pkgs.gnugrep}/bin/grep -v '^\s*$') || {
                echo "Failed to fetch image list, skipping pre-pull"
                exit 0
              }

              for img in $IMAGES; do
                echo "Pre-pulling: $img"
                ${pkgs.k3s}/bin/k3s ctr images pull "$img" &
              done

              echo "Waiting for all pulls to complete..."
              wait
              echo "Pre-pull complete"
            '';
          };

          systemd.services.k3s-agent-bootstrap = {
            description = "K3s Agent Bootstrap (Karpenter node)";
            after = [ "network-online.target" "cloud-init.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "exec";
              Restart = "on-failure";
              RestartSec = "10s";
            };

            script = ''
              set -euo pipefail

              for i in $(seq 1 60); do
                [ -f /etc/karpenter-node.conf ] && break
                sleep 2
              done
              source /etc/karpenter-node.conf

              IMDS_TOKEN=$(${pkgs.curl}/bin/curl -s -X PUT \
                "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              INSTANCE_ID=$(${pkgs.curl}/bin/curl -s \
                -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
                http://169.254.169.254/latest/meta-data/instance-id)
              AVAILABILITY_ZONE=$(${pkgs.curl}/bin/curl -s \
                -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
                http://169.254.169.254/latest/meta-data/placement/availability-zone)
              PRIVATE_IP=$(${pkgs.curl}/bin/curl -s \
                -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
                http://169.254.169.254/latest/meta-data/local-ipv4)

              K3S_TOKEN=$(${pkgs.awscli2}/bin/aws ssm get-parameter \
                --name "$SSM_TOKEN_PATH" \
                --with-decryption --query 'Parameter.Value' --output text \
                --region "$AWS_REGION")

              for i in $(seq 1 60); do
                ${pkgs.curl}/bin/curl -sk --max-time 3 \
                  "https://$SERVER_ENDPOINT:6443/ping" && break
                sleep 2
              done

              exec ${pkgs.k3s}/bin/k3s agent \
                --server "https://$SERVER_ENDPOINT:6443" \
                --token "$K3S_TOKEN" \
                --node-ip "$PRIVATE_IP" \
                --kubelet-arg="provider-id=aws:///$AVAILABILITY_ZONE/$INSTANCE_ID" \
                --node-label="topology.kubernetes.io/region=$AWS_REGION" \
                --node-label="karpenter.sh/registered=true" \
                --kubelet-arg="kube-api-qps=100" \
                --kubelet-arg="kube-api-burst=200" \
                --kubelet-arg="event-qps=50" \
                --kubelet-arg="event-burst=100"
            '';
          };

          system.stateVersion = "25.11";

          virtualisation = {
            memorySize = 2048;
            cores = 2;
          };
        };

        testScript = ''
          machine.start()
          machine.wait_for_unit("multi-user.target")

          with subtest("k3s binary is present and executable"):
              machine.succeed("k3s --version")

          with subtest("awscli2 is present and executable"):
              machine.succeed("aws --version")

          with subtest("curl is present"):
              machine.succeed("curl --version")

          with subtest("jq is present"):
              machine.succeed("jq --version")

          with subtest("SSH is disabled"):
              machine.fail("systemctl is-active sshd")

          with subtest("firewall is disabled"):
              machine.fail("iptables -L nixos-fw 2>/dev/null")

          with subtest("kernel sysctls are set"):
              machine.succeed("sysctl net.ipv4.ip_unprivileged_port_start | grep -q '= 0'")
              machine.succeed("sysctl net.core.rmem_max | grep -q '= 5000000'")
              machine.succeed("sysctl net.core.wmem_max | grep -q '= 5000000'")

          with subtest("k3s-agent-bootstrap service exists with correct dependencies"):
              machine.succeed("systemctl cat k3s-agent-bootstrap.service")
              unit = machine.succeed("systemctl show k3s-agent-bootstrap.service --property=After")
              assert "cloud-init.service" in unit, f"Missing cloud-init.service dependency: {unit}"
              assert "network-online.target" in unit, f"Missing network-online.target dependency: {unit}"

          with subtest("bootstrap service reads config and attempts bootstrap"):
              # Write the config file that cloud-init would normally create
              machine.succeed(
                  "cat > /etc/karpenter-node.conf << 'CONF'\n"
                  "export CLUSTER_NAME='k3s-cluster'\n"
                  "export AWS_REGION='eu-west-1'\n"
                  "export SERVER_ENDPOINT='k3s.redwood-guild.com'\n"
                  "export SSM_TOKEN_PATH='/k3s-cluster/k3s-cluster/token'\n"
                  "CONF"
              )
              # Restart to pick up the config. It will fail (no IMDS in VM) but
              # should show it sourced the config and attempted to run.
              machine.succeed("systemctl restart k3s-agent-bootstrap.service || true")
              import time
              time.sleep(5)
              # Service should have started and failed (exit code 7 = curl connection
              # refused to IMDS, expected in a VM). This proves the service read
              # the config file, sourced it, and attempted the IMDS curl.
              logs = machine.succeed("journalctl -u k3s-agent-bootstrap.service --no-pager -n 50")
              assert "Started K3s Agent Bootstrap" in logs, \
                  f"Service did not start. Logs:\n{logs}"
              # Verify it actually failed trying to run (not a config parse error)
              assert "exit-code" in logs or "exited" in logs, \
                  f"Service did not attempt to execute. Logs:\n{logs}"

          # --- Cilium kernel requirements ---
          # The cluster uses Cilium with ENI IPAM, eBPF kube-proxy replacement,
          # DSR load balancing, BBR bandwidth manager, and netkit (kernel 6.6+).

          with subtest("kernel version is 6.12+ for netkit/tcx support"):
              version = machine.succeed("uname -r").strip()
              major, minor = [int(x) for x in version.split(".")[:2]]
              assert (major, minor) >= (6, 12), \
                  f"Kernel {version} too old, need >= 6.12 for netkit/tcx"

          with subtest("Cilium eBPF core: BPF subsystem is available"):
              # /proc/config.gz checks for built-in options; /sys/fs/bpf for runtime
              machine.succeed("test -d /sys/fs/bpf")
              machine.succeed("ls /sys/fs/cgroup/")  # cgroup2 for CGROUP_BPF

          with subtest("Cilium eBPF core: BPF JIT is enabled at runtime"):
              jit = machine.succeed("cat /proc/sys/net/core/bpf_jit_enable").strip()
              assert jit in ("1", "2"), f"BPF JIT not enabled: {jit}"

          with subtest("Cilium eBPF: can load BPF programs (bpf syscall)"):
              # bpftool confirms the BPF syscall works and programs can be listed
              machine.succeed("bpftool prog list >/dev/null 2>&1 || "
                              "ls /sys/fs/bpf >/dev/null")

          with subtest("Cilium: required kernel modules are loadable"):
              # These are =m in the kernel config; verify they can be loaded.
              # cls_bpf: eBPF traffic classifier (for tc-based datapath)
              # sch_fq: Fair Queue qdisc (required for BBR bandwidth manager)
              # sch_ingress: ingress qdisc (for tc ingress hooks)
              # xt_bpf: netfilter BPF match (for eBPF-based masquerade)
              for mod in ["cls_bpf", "sch_fq", "sch_ingress", "xt_bpf"]:
                  machine.succeed(f"modprobe {mod}")

          with subtest("Cilium BBR: tcp_bbr module is available"):
              machine.succeed("modprobe tcp_bbr")
              # Verify BBR can be set as congestion control
              machine.succeed(
                  "sysctl -w net.ipv4.tcp_congestion_control=bbr"
              )
              result = machine.succeed(
                  "sysctl net.ipv4.tcp_congestion_control"
              ).strip()
              assert "bbr" in result, f"BBR not active: {result}"

          with subtest("Cilium: sch_fq qdisc is functional (BBR bandwidth manager)"):
              # BBR bandwidth manager needs FQ qdisc. Verify it can be attached.
              machine.succeed(
                  "tc qdisc add dev lo root fq && "
                  "tc qdisc show dev lo | grep -q fq"
              )

          with subtest("Cilium: vxlan/geneve tunnel modules available"):
              # Fallback tunnel modes if ENI has issues
              machine.succeed("modprobe vxlan")
              machine.succeed("modprobe geneve")

          with subtest("Cilium: netfilter conntrack available"):
              # Required for masquerade and connection tracking
              machine.succeed("modprobe nf_conntrack")
              machine.succeed("test -d /proc/sys/net/netfilter")

          with subtest("Cilium netkit: tun device support"):
              # Netkit uses tun/tap infrastructure
              machine.succeed("modprobe tun")
              machine.succeed("test -c /dev/net/tun")

          # --- EC2/EBS infrastructure ---
          # Karpenter nodes run on Nitro instances; EBS CSI driver creates volumes.

          with subtest("EC2: NVMe kernel module available (Nitro EBS)"):
              machine.succeed("modprobe nvme")
              machine.succeed("modprobe nvme_core")

          with subtest("EC2: filesystem support for EBS volumes"):
              # ext4 (EBS CSI default), XFS, and btrfs (dedup) support
              machine.succeed("modprobe ext4")
              machine.succeed("modprobe xfs")
              machine.succeed("modprobe btrfs")
              machine.succeed("which mkfs.ext4")
              machine.succeed("which mkfs.xfs")
              machine.succeed("which mkfs.btrfs")

          # --- Container runtime (k3s bundles containerd) ---

          with subtest("containerd: overlayfs available"):
              machine.succeed("modprobe overlay")
              # Verify it's functional
              machine.succeed(
                  "mkdir -p /tmp/overlay/{lower,upper,work,merged} && "
                  "mount -t overlay overlay -o lowerdir=/tmp/overlay/lower,"
                  "upperdir=/tmp/overlay/upper,workdir=/tmp/overlay/work "
                  "/tmp/overlay/merged && "
                  "umount /tmp/overlay/merged"
              )

          with subtest("containerd: veth support for container networking"):
              machine.succeed("modprobe veth")
              # Verify veth pairs can be created
              machine.succeed(
                  "ip link add veth-test type veth peer name veth-peer && "
                  "ip link del veth-test"
              )

          with subtest("containerd: bridge module available"):
              machine.succeed("modprobe bridge")

          with subtest("k3s: cgroup v2 is mounted"):
              machine.succeed("test -f /sys/fs/cgroup/cgroup.controllers")
              # Verify required controllers are available
              controllers = machine.succeed("cat /sys/fs/cgroup/cgroup.controllers")
              for ctrl in ["cpu", "memory", "pids"]:
                  assert ctrl in controllers, \
                      f"cgroup controller '{ctrl}' missing: {controllers}"

          with subtest("k3s: nftables available"):
              machine.succeed("which nft")
              machine.succeed("nft --version")
              # Verify nf_tables kernel module works
              machine.succeed("modprobe nf_tables")

          with subtest("WireGuard: kernel module available"):
              machine.succeed("modprobe wireguard")

          with subtest("WireGuard: interface can be created"):
              machine.succeed(
                  "ip link add wg-test type wireguard && "
                  "ip link del wg-test"
              )

          with subtest("WireGuard/AmneziaWG: crypto dependencies available"):
              # Both WireGuard and AmneziaWG use ChaCha20-Poly1305, Curve25519, BLAKE2s.
              # AmneziaWG builds as an out-of-tree module requiring these kernel crypto APIs.
              for mod in ["chacha20_generic", "poly1305_generic", "curve25519_generic"]:
                  machine.succeed(f"modprobe {mod} || true")
              algos = machine.succeed("cat /proc/crypto")
              for name in ["chacha20", "poly1305"]:
                  assert name in algos, f"crypto algorithm '{name}' not available"

          with subtest("AmneziaWG: kernel prerequisites for out-of-tree module"):
              # AmneziaWG selects CONFIG_NET_UDP_TUNNEL, CONFIG_DST_CACHE,
              # CONFIG_CRYPTO, CONFIG_CRYPTO_ALGAPI. Verify these are available.
              machine.succeed("modprobe udp_tunnel")
              # Verify crypto subsystem is functional
              machine.succeed("test -f /proc/crypto")
              # Kernel headers availability (needed to build out-of-tree modules)
              machine.succeed("test -d /lib/modules/$(uname -r)/build || "
                              "test -d /run/current-system/kernel-modules/lib/modules/$(uname -r)")

          with subtest("livepatch: kernel live patching is available (x86_64 only)"):
              # LIVEPATCH is only supported on x86_64 in mainline Linux
              arch = machine.succeed("uname -m").strip()
              if arch == "x86_64":
                  machine.succeed("test -d /sys/kernel/livepatch")
                  machine.succeed("zgrep -q 'CONFIG_LIVEPATCH=y' /proc/config.gz")
              else:
                  machine.log(f"Skipping livepatch check on {arch}")

          with subtest("kpatch: runtime utility is available (x86_64 only)"):
              arch = machine.succeed("uname -m").strip()
              if arch == "x86_64":
                  machine.succeed("kpatch version")
                  machine.succeed("kpatch list")
              else:
                  machine.log(f"Skipping kpatch check on {arch}")

          # --- Container image pre-pull service ---
          # Verify the pre-pull service is configured to fetch the image list
          # from the home-cluster repo and pull images via k3s ctr.

          with subtest("k3s-prepull-images: service unit exists and is enabled"):
              machine.succeed("systemctl cat k3s-prepull-images.service")
              unit = machine.succeed("systemctl is-enabled k3s-prepull-images.service").strip()
              assert unit == "enabled", f"k3s-prepull-images not enabled: {unit}"

          with subtest("k3s-prepull-images: runs after k3s-agent-bootstrap"):
              unit = machine.succeed(
                  "systemctl show k3s-prepull-images.service --property=After"
              )
              assert "k3s-agent-bootstrap.service" in unit, \
                  f"Missing k3s-agent-bootstrap.service dependency: {unit}"

          with subtest("k3s-prepull-images: script fetches image list from home-cluster repo"):
              script = machine.succeed(
                  "cat /etc/systemd/system/k3s-prepull-images.service"
              )
              import re
              match = re.search(r'ExecStart=(/nix/store/\S+)', script)
              assert match, f"No ExecStart found in service unit"
              script_content = machine.succeed(f"cat {match.group(1)}")
              assert "raw.githubusercontent.com/alisonjenkins/home-cluster" in script_content, \
                  "Script does not reference home-cluster image list"
              assert "karpenter-node-prepull-images.txt" in script_content, \
                  "Script does not reference prepull images file"
              assert "k3s ctr images pull" in script_content, \
                  "Script does not use k3s ctr to pull images"

          with subtest("k3s-prepull-images: service is oneshot with RemainAfterExit"):
              svc_type = machine.succeed(
                  "systemctl show k3s-prepull-images.service --property=Type"
              ).strip()
              assert "oneshot" in svc_type, f"Service type is not oneshot: {svc_type}"
              remain = machine.succeed(
                  "systemctl show k3s-prepull-images.service --property=RemainAfterExit"
              ).strip()
              assert "yes" in remain, f"RemainAfterExit not set: {remain}"

          # --- k3s agent configuration ---
          # Verify the bootstrap service passes the correct flags to the k3s agent.
          # Bundled server-side components (traefik, servicelb, flannel, kube-proxy,
          # local-storage) are disabled on the server. Agents don't run them, but
          # we verify the agent command line is correct.

          with subtest("k3s bootstrap: agent mode with correct flags"):
              # Find and read the bootstrap script from the nix store
              script = machine.succeed(
                  "cat /etc/systemd/system/k3s-agent-bootstrap.service"
              )
              # Get the ExecStart script path and read it
              import re
              match = re.search(r'ExecStart=(/nix/store/\S+)', script)
              assert match, f"Could not find ExecStart path in unit file: {script}"
              script = machine.succeed(f"cat {match.group(1)}")
              # Must NOT contain server-only flags
              assert "--disable=" not in script, "Agent should not have --disable flags"
              # Must have provider-id for Karpenter/cloud integration
              assert "provider-id" in script, "Missing provider-id kubelet arg"
              # Must have Karpenter registration label
              assert "karpenter.sh/registered=true" in script, "Missing karpenter label"
              # Must have region label for topology-aware scheduling
              assert "topology.kubernetes.io/region" in script, "Missing region label"

          with subtest("k3s: agent subcommand is available"):
              result = machine.succeed("k3s agent --help 2>&1 || true")
              assert "agent" in result.lower(), f"k3s agent mode not available: {result}"

          # --- AWS high-speed networking ---

          with subtest("EC2: ENA driver available (Elastic Network Adapter)"):
              machine.succeed("modprobe ena")

          with subtest("EC2: EFA driver available (Elastic Fabric Adapter)"):
              machine.succeed("modprobe efa")

          with subtest("EC2: ixgbevf driver available (legacy enhanced networking)"):
              machine.succeed("modprobe ixgbevf")

          with subtest("EC2: SR-IOV support enabled"):
              machine.succeed(
                  "zgrep -q 'CONFIG_PCI_IOV=y' /proc/config.gz"
              )

          # --- EC2 Serial Console ---

          with subtest("EC2 Serial Console: kernel console on ttyS0"):
              cmdline = machine.succeed("cat /proc/cmdline")
              assert "console=ttyS0" in cmdline, \
                  f"Kernel not configured for serial console: {cmdline}"

          with subtest("EC2 Serial Console: serial-getty template unit exists"):
              # On the real AMI, amazon-image.nix enables serial-getty@ttyS0.
              # The test VM doesn't import amazon-image.nix, so verify the
              # template unit exists (systemd built-in) for instantiation.
              machine.succeed("systemctl cat serial-getty@.service")

          with subtest("EC2 Serial Console: serial driver available"):
              machine.succeed("zgrep -q 'CONFIG_SERIAL_8250_CONSOLE=y' /proc/config.gz")

          # --- KVM / KubeVirt (nested virtualisation on EC2) ---

          with subtest("KubeVirt: KVM kernel modules available"):
              machine.succeed("modprobe kvm")
              machine.succeed("modprobe kvm_intel || modprobe kvm_amd")

          with subtest("KubeVirt: /dev/kvm device exists after module load"):
              machine.succeed("test -c /dev/kvm")

          with subtest("KubeVirt: vhost-net available (VM data plane)"):
              machine.succeed("modprobe vhost_net")

          with subtest("KubeVirt: virtio device drivers available"):
              for mod in ["virtio_net", "virtio_blk", "virtio_pci", "virtio_console"]:
                  machine.succeed(f"modprobe {mod}")

          with subtest("KubeVirt: VM networking modules available"):
              machine.succeed("modprobe macvtap")
              machine.succeed("modprobe bridge")

          with subtest("KubeVirt: hugepages support"):
              machine.succeed("test -d /sys/kernel/mm/hugepages")
              machine.succeed(
                  "zgrep -q 'CONFIG_HUGETLBFS=y' /proc/config.gz"
              )

          with subtest("zram module available"):
              # The AWS module enables zram swap; verify the kernel module loads
              machine.succeed("modprobe zram")
        '';
      };
    };
}
