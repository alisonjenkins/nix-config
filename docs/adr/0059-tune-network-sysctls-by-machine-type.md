# 0059. Tune network sysctls by machine type, from sourced claims only

- Status: Proposed
- Date: 2026-10-30

## Context

`modules/base` sets one network sysctl block on every host: `net.core.*`
buffers and queues, `rp_filter`, `tcp_*`, and `default_qdisc = dualpi2` at
`mkDefault`. It was written with a desktop in mind. The fleet has six other
kinds of machine, and the same block lands on all of them:

| Machine type | Hosts | Facts read from this repository |
|---|---|---|
| Gaming desktop, laptop, handheld | `ali-desktop`, `ali-framework-laptop`, `ali-work-laptop`, `ali-steam-deck` | CachyOS kernel on the first three; the Deck runs the Jovian kernel. `modules/desktop` forces `default_qdisc = cake` and installs a NetworkManager dispatcher that runs `tc qdisc replace ... root cake`. |
| Storage and download | `home-storage-server-1`, `download-server-1` | Stock `linuxPackages_latest`. A virtual link between them has `mtu = 9000` in both hosts' `storage-jumbo` NetworkManager profile (evaluated, see the manifest). The NFS 4.2 mount options `nconnect=8,rsize=1048576,wsize=1048576` are read from the `systemd.mounts` entry in `flake-modules/hosts/download-server-1/default.nix` (a string, not evaluated). The same file's comments say the host has 3.8 GB of RAM (another comment there says 7.7 GB); this is a repo fact, not measured here. `home-storage-server-1` sets `services.nfs.server.nproc = 32` (evaluated). `download-server-1` is also a `wg-quick` client (`networking.wg-quick.interfaces.primary-vpn`). |
| Kubernetes | `home-k8s-master-1`, `home-k8s-server-1` | Read for the master only: k3s with `--flannel-backend=none`; Cilium with `kubeProxyReplacement` set, **and** kube-proxy not disabled (`# "--disable-kube-proxy"` is commented out in the `extraFlags` of `flake-modules/hosts/home-k8s-master-1/default.nix`, read from the file, not evaluated; k3s runs kube-proxy unless that flag is given, V3); `accept_local` and `route_localnet` set. `home-k8s-server-1` sets no network sysctls; its CNI was not read. |
| KVM hypervisor | `home-kvm-hypervisor-1` | Guests attach through Linux bridges (`br0`, `br-storage`) with virtio and vhost, multiqueue. Host sets only the forwarding sysctls and `vm.*`. |
| VPN gateway | `home-vpn-gateway-1` | LAN NATed out of `awg0` (AmneziaWG). The `awg-quick` client config is **not** in the repository (`/persistence/etc/amnezia-wg/client.conf`), so MTU, `Table` and `FwMark` are unknown from the code. The module sets no MTU, MSS clamp or conntrack values. |

Earlier research on how to tune each type mixed documented behaviour with
inference, and some of the inferences were wrong. The owner asked that every
claim we rely on be backed by a document we can quote. This record is that
ledger: what a primary source states, what it contradicts, and what no source
states. A change is only proposed here where a source supports it.

Method: each claim was checked against kernel documentation or source at tag
v6.18 (the fleet runs 6.18 or newer), upstream project source, or vendor
documentation, fetched 2026-10-30. A quote is verbatim and under 25 words. A
claim a source does not state is listed as unsourced, never as confirmed.

## Evidence

Kernel documentation paths below are under
`https://raw.githubusercontent.com/torvalds/linux/v6.18/Documentation/`
unless a full URL is given. `ip-sysctl` is `networking/ip-sysctl.rst`; `net.rst`
is `admin-guide/sysctl/net.rst`; `nf-sysctl` is
`networking/nf_conntrack-sysctl.rst`. Kernel source was read at v6.18 from
`https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/<path>?h=v6.18`.

### Reverse-path filter

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| R1 | The larger of `all` and the interface value applies | "The max value from conf/{all,interface}/rp_filter is used when doing source validation on the {interface}." | ip-sysctl |
| R2 | Loose mode is the documented choice for asymmetric routing | "If using asymmetric routing or other complicated routing, then loose mode is recommended." | ip-sysctl |
| R3 | `src_valid_mark` lets strict mode work with fwmark routing | "The fwmark of the packet is included in reverse path route lookup." | ip-sysctl |
| R4 | `wg-quick` sets `src_valid_mark` for full tunnels; `amneziawg-tools` does the same, unconditionally | `cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1` (linux.bash line 241, inside add_default) | `https://raw.githubusercontent.com/WireGuard/wireguard-tools/master/src/wg-quick/linux.bash`; `https://raw.githubusercontent.com/amnezia-vpn/amneziawg-tools/master/src/wg-quick/linux.bash` |
| R5 | Cilium sets `all.rp_filter` to 0 itself, on every datapath load, because of R1 | "The kernel uses max(conf.all, conf.{dev}) as its value, so we need to set .all. to 0 as well." and `{Name: []string{"net", "ipv4", "conf", "all", "rp_filter"}, Val: "0", IgnoreErr: false}` | `https://github.com/cilium/cilium/blob/v1.20.4/tools/sysctlfix/main.go`; `.../v1.20.4/pkg/datapath/loader/base.go:301` |
| R6 | Calico (BPF mode) says the same about `all` | "Any non-zero value on `all` trumps the per-interface setting." | `felix/design/bpf-host-networking.md:126` in `github.com/projectcalico/calico` @70e33da |
| R7 | Only the kernel code links `accept_local` to `rp_filter`: in the `fib_validate_source` path an interface with `accept_local` takes the early accept. The `ip-sysctl` entries for the two settings do not mention each other, and `route_localnet` does not appear in `fib_frontend.c`, so its link to `rp_filter` is unproven | `if (IN_DEV_ACCEPT_LOCAL(idev))` | `net/ipv4/fib_frontend.c` L438 @v6.18 |

### Queueing discipline

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| Q1 | The kernel default is `pfifo_fast`; virtual devices ignore the setting | "Virtual devices (like e.g. lo or veth) ignore this setting and instead default to noqueue." | net.rst L174-177 |
| Q2 | `veth` and WireGuard are `noqueue` in code | `dev->priv_flags \|= IFF_NO_QUEUE;` | `drivers/net/veth.c:1735`, `drivers/net/wireguard/device.c:291` |
| Q3 | Multiqueue NICs get `mq` as root, with the default as leaf | `qdisc_create_dflt(txq, &mq_qdisc_ops, TC_H_ROOT, NULL)` | `net/sched/sch_generic.c`, `attach_default_qdiscs()` |
| Q4 | DualPI2 landed in 6.17 (the kernelnewbies 6.17 release page lists it) | "Add DualPI Improved with a Square (DualPI2)" | `https://kernelnewbies.org/Linux_6.17`; `net/sched/sch_dualpi2.c` |
| Q5 | DualPI2's stated benefit is for L4S traffic; classic traffic is "not harmed" | "DUALPI2 is designed to provide low loss and low latency to L4S traffic, without harming classic traffic." | `https://man7.org/linux/man-pages/man8/tc-dualpi2.8.html` |
| Q6 | Neither DCTCP nor BBRv3 meets the L4S sender requirements | "Although DCTCP and BBRv3 can use shallow-threshold ECN marks, they do not meet the 'Prague L4S Requirements'" | `net/sched/sch_dualpi2.c` header |
| Q7 | TCP Prague is not in mainline 6.18 (absence: `net/ipv4` has `tcp_bbr.c` and `tcp_dctcp.c`, no `tcp_prague*`; none at v7.0 either) | n/a | `net/ipv4` tree listing at v6.18 and v7.0 |
| Q8 | `cake` without `bandwidth` shapes nothing; `nat`, `wash`, `besteffort`, `autorate-ingress` do what their man entries say | "unlimited (default)  No limit on the bandwidth." | `https://man7.org/linux/man-pages/man8/tc-cake.8.html` |
| Q9 | Regular `cake` is single-queue under the qdisc lock; `cake_mq` is not in 6.18 (0 hits in `sch_cake.c`, present at v7.0) | "subject to the global qdisc lock, which means that it does not scale across multiple CPUs" | tc-cake(8); `net/sched/sch_cake.c` @v6.18 and @v7.0 |
| Q10 | mac80211 keeps its own per-station queues | "Intermediate queues (struct ieee80211_txq) are kept per-sta per-tid"; "The queuing discipline layer was removed entirely" | `include/net/mac80211.h` @v6.18; `https://lwn.net/Articles/705884/` |
| Q11 | mac80211 documents an intermediate queueing layer between the stack and the driver, with fairness between stations. This shows per-station queues exist; it does not show that a root qdisc adds little | "mac80211 uses an intermediate queueing implementation"; "to provide some fairness between different stations/interfaces." | `include/net/mac80211.h` @v6.18 |
| Q12 | `cake` has an ACK filter: a code comment (not a documented option; the tc-cake man page read has only the synopsis) says it scans the queue for pure ACKs of the same flow | "loop through the rest of the queue looking for pure ACKs with the same 5-tuple as the triggering one." | `net/sched/sch_cake.c` @v6.18 |

### Congestion control

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| C1 | BBR needed `fq` up to 4.12; since 4.13 the TCP stack paces itself | v4.12: "NOTE: BBR *must* be used with the fq qdisc". v4.13 and v6.18: "otherwise TCP stack falls back to an internal pacing" | `net/ipv4/tcp_bbr.c` @v4.12, @v4.13, @v6.18; commit 218af599fa63 "tcp: internal implementation for pacing" |
| C2 | The v6.18 Kconfig help for BBR is stale and still says fq is required | "It requires the fq ("Fair Queue") pacing packet scheduler." | `net/ipv4/Kconfig` @v6.18, `config TCP_CONG_BBR` |
| C3 | BBR v1 does not react directly to loss | "The core algorithm does not react directly to packet losses or delays" | `net/ipv4/tcp_bbr.c` @v6.18, L12-13 |
| C4 | BBRv3 uses loss and ECN; its ECN logic applies only when ECN was negotiated in the handshake and the route is marked as a shallow-threshold ECN environment (the `ecn_low` per-route feature) | "as well as (if they occur) packet loss and/or shallow-threshold ECN signals"; "the per-route settings indicated this is a shallow-threshold ECN environment" | `https://raw.githubusercontent.com/google/bbr/v3/net/ipv4/tcp_bbr.c` (header and `bbr_can_use_ecn`) |
| C5 | The CachyOS kernel on the desktops defaults to cubic and fq_codel | `CONFIG_DEFAULT_TCP_CONG="cubic"`, `CONFIG_DEFAULT_NET_SCH="fq_codel"` | `/proc/config.gz` of the running 7.3.0-cachyos-lto kernel; `https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos/config`. The only network line in CachyOS-Settings' `70-cachyos-settings.conf` is `net.core.netdev_max_backlog = 4096`: `https://raw.githubusercontent.com/CachyOS/CachyOS-Settings/master/usr/lib/sysctl.d/70-cachyos-settings.conf` |
| C6 | CachyOS BBRv3 layout changed: in the 6.17 patch it replaces `tcp_bbr.c` and registers as `bbr`; in 7.x it is a separate module registering as `bbr3` (`CONFIG_TCP_CONG_BBR3=m`) | `.name = "bbr",` (6.17 patch); `.name = "bbr3",` (tcp_bbr3.c, branch 7.1/bbr3) | `https://raw.githubusercontent.com/CachyOS/kernel-patches/master/6.17/0002-bbr3.patch`; `CachyOS/linux` branch `7.1/bbr3`. On the running 7.3 kernel `modinfo tcp_bbr3` reports `version: 3`; `tcp_bbr` has no version field. |
| C7 | CachyOS makes BBRv3 the default only with an opt-in build flag, and that flag sets the congestion-control name to `bbr` | `: "${_tcp_bbr3:=no}"`; `--set-str DEFAULT_TCP_CONG bbr` | `https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos/PKGBUILD` L436-446 |
| C8 | ESnet: leave the congestion control at its default; use `fq` | "we no longer recommend setting congestion control to htcp"; "net.core.default_qdisc = fq" | `https://fasterdata.es.net/host-tuning/linux/` (page dated 2025-03-06) |
| C9 | Cilium's bandwidth manager: BBR for pods needs kernel 5.18, and may retransmit more than CUBIC | "BBR for Pods requires a v5.18.x or more recent Linux kernel." and "you might observe a higher rate of TCP retransmissions compared to CUBIC." | `https://docs.cilium.io/en/stable/network/kubernetes/bandwidth-manager/` |
| C11 | The mainline kernel's default congestion control is cubic (the stock `linuxPackages_latest` hosts use mainline defaults unless NixOS overrides them; its kernel config was not read) | `prompt "Default TCP congestion control"` and `default DEFAULT_CUBIC` | `https://raw.githubusercontent.com/torvalds/linux/v6.18/net/ipv4/Kconfig` |
| C10 | Cilium's bandwidth manager sets up MQ/FQ itself and relies on an FQ qdisc on the physical device | "The base infrastructure around MQ/FQ setup provided by Cilium's bandwidth manager"; "hits the FQ queueing discipline on the physical device in the host namespace" | `https://raw.githubusercontent.com/cilium/cilium/v1.20.4/Documentation/network/kubernetes/bandwidth-manager.rst` |
| C12 | `net/ipv4/tcp_bbr.c` at v6.18 contains no ECN code (probe: the strings `ecn` and `ECN` are absent, with `bbr_min_rtt_win_sec` present as positive control). This does not show that a BBR v1 connection ignores ECN end to end: core TCP handles ECN elsewhere | n/a | `net/ipv4/tcp_bbr.c` @v6.18 (probe) |
| C13 | nixpkgs sets `TCP_CONG_CUBIC` and its comment calls cubic the default; mainline Kconfig makes `DEFAULT_CUBIC` the default choice. A search of that nixpkgs file found no `DEFAULT_TCP_CONG`, so the mainline default applies to its kernels. Whether `bbr` and `dualpi2` are built as modules in the nixpkgs or Jovian configs is not established (inferred from `autoModules`; no built `.config` was read) | `TCP_CONG_CUBIC = yes; # This is the default congestion control algorithm since 2.6.19`; `default DEFAULT_CUBIC`; `default "cubic" if DEFAULT_CUBIC` | `pkgs/os-specific/linux/kernel/common-config.nix` L305-306 in `github.com/NixOS/nixpkgs` @58deea6; `net/ipv4/Kconfig` @v6.18 |

### Buffers and TCP defaults

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| B1 | `tcp_rmem` and `tcp_wmem` defaults | "This value overrides net.core.rmem_default used by other protocols. Default: 131072 bytes." (rmem); "It is usually lower than net.core.wmem_default. Default: 16K" (wmem) | ip-sysctl L833-845, L1184-1199 |
| B2 | Receive autotuning is capped by `tcp_rmem[2]` | "automatically size the buffer (no greater than tcp_rmem[2])" | ip-sysctl L664-674 |
| B3 | `rmem_max` and `wmem_max` documented defaults are 4 MiB; 6.18 changed them | "The maximum receive socket buffer size in bytes. Default: 4194304"; "The maximum send socket buffer size in bytes. Default: 4194304"; kernelnewbies 6.18: "Set net.core.rmem_max and net.core.wmem_max to 4 mb" | net.rst L220, L247; `https://kernelnewbies.org/Linux_6.18` |
| B4 | `optmem_max` default | "optmem_max as a limit for its internal structures. Default : 128 KB" | net.rst |
| B5 | NAPI settings and their defaults | "Maximum number of packets taken from all interfaces in one polling cycle (NAPI poll)." Defaults `.netdev_budget = 300,` `.netdev_budget_usecs = 2 * USEC_PER_SEC / HZ,` `.max_backlog = 1000,` | net.rst L279-296; `net/core/hotdata.c` @v6.18 |
| B6 | `tcp_ecn` default 2; values 3-5 are AccECN, merged in 6.18 | "5 AccECN No ECN ===== ==================== ==================== Default: 2"; "3 AccECN AccECN 4 AccECN ECN 5 AccECN No ECN"; "(FEATURED) AccECN (Accurate ECN) protocol patch series" | ip-sysctl L458-468; `https://kernelnewbies.org/Linux_6.18` |
| B7 | `tcp_tw_reuse` default 2 (loopback only); `tcp_fastopen` default 0x1 (client) | "It should not be changed without advice/request of technical experts. Default: 2"; "The client support is enabled by flag 0x1 (on by default)." | ip-sysctl L1130-1137, L981-1004 |
| B8 | `tcp_mtu_probing` 1 | "enabled when an ICMP black hole detected" | ip-sysctl L676-683 |
| B9 | `tcp_notsent_lowat` default is unlimited; Cloudflare runs 131072 | "Default: UINT_MAX (0xFFFFFFFF)"; "Our web servers already set tcp_notsent_lowat to 131072" | ip-sysctl L1201-1212; `https://blog.cloudflare.com/optimizing-tcp-for-high-throughput-and-low-latency/` |
| B10 | ESnet's 10G example uses a middle `tcp_rmem` value of 87380, which is not the 6.18 default of 131072 (B1); another example on the same page uses 131072 | "a 10Gbps flow across a 100ms network requires 120MB of buffering"; `net.ipv4.tcp_rmem = 4096 87380 33554432`; `net.ipv4.tcp_rmem=4096 131072` | `https://fasterdata.es.net/host-tuning/linux/` |
| B11 | `log_martians` is 0 by default: neither `ipv4_devconf` initialiser sets it (absence), and the docs state no default | n/a | `net/ipv4/devinet.c` L71-94 @v6.18; the `log_martians` entry of `https://raw.githubusercontent.com/torvalds/linux/v6.18/Documentation/networking/ip-sysctl.rst` has no `Default` line (probe) |
| B12 | `hpet` default is 64 | `#define HPET_USER_FREQ (64)` | `drivers/char/hpet.c` @v6.12 |
| B13 | `fs.dentry-negative` is a mainline sysctl | "Policy for negative dentries. Set to 1 to always delete the dentry when a file is removed, and 0 to disable it." | `https://docs.kernel.org/admin-guide/sysctl/fs.html` (present on the running kernel) |
| B14 | Receive autotuning is capped by `tcp_rmem[2]`; `rmem_max` and `wmem_max` cap buffers set explicitly with `SO_RCVBUF` and `SO_SNDBUF`. The `tcp_wmem` text says its maximum "does not override" `wmem_max`, so these quotes do not show that `wmem_max` leaves send autotuning uncapped | "maximal size of receive buffer allowed for automatically selected receiver buffers for TCP socket."; "This value does not override net.core.wmem_max."; "The maximum sizes for socket buffers declared via the SO_SNDBUF and SO_RCVBUF mechanisms"; "limited by the values in the /proc/sys/net/core/rmem_max and /proc/sys/net/core/wmem_max files." | ip-sysctl (`tcp_rmem`, `tcp_wmem`); `https://man7.org/linux/man-pages/man7/tcp.7.html` |

### Conntrack, neighbour table, ports

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| K1 | `nf_conntrack_max` defaults to the bucket count | "This value is set to nf_conntrack_buckets by default." Code: "Use a max. factor of one by default to keep the average hash chain length at 2 entries."; "When a table size is given we use the old value of 8" | nf-sysctl L94-96; `net/netfilter/nf_conntrack_core.c` L2631-2666 |
| K2 | Bucket count is derived from memory and is writable at runtime | "never have fewer than 1024 and never more than 262144 buckets"; `.mode = 0644, .proc_handler = nf_conntrack_hash_sysctl` | nf-sysctl L17-22; `net/netfilter/nf_conntrack_standalone.c` L660-666 |
| K3 | Established timeout 5 days; UDP 30 s and 120 s stream | "default 432000 (5 days)" | nf-sysctl L135, L194-198 |
| K4 | kube-proxy sets `nf_conntrack_max` and the established timeout itself | "SetMax adjusts nf_conntrack_max."; `Duration: 24 * time.Hour} // 1 day (1/5 default)`; `obj.Conntrack.MaxPerCore = ptr.To[int32](32 * 1024)`; `obj.Conntrack.Min = ptr.To[int32](128 * 1024)` | `cmd/kube-proxy/app/conntrack.go:36`, `pkg/proxy/apis/config/v1alpha1/defaults.go:81-97` in `github.com/kubernetes/kubernetes` v1.34.0 |
| K5 | Cilium keeps its own connection-tracking tables | "--bpf-ct-global-tcp-max int Maximum number of entries in TCP CT table (default 524288)" | `Documentation/cmdref/cilium-agent.md:35` in `github.com/cilium/cilium` v1.20.4 |
| K6 | Neighbour-table kernel defaults | "purge entries if there are fewer than this number. Default: 128"; "will be cleared when over this number. Default: 512"; "with large numbers of directly-connected peers. Default: 1024" (gc_thresh1, 2, 3) | ip-sysctl L185-202 |
| K7 | Ephemeral port range default | "The default values are 32768 and 60999 respectively." | ip-sysctl L1558 |

### VPN gateway

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| W1 | WireGuard overhead is 80 bytes in the kernel (32 + 8 + 40), giving MTU 1420 | `dev->mtu = ETH_DATA_LEN - overhead;` | `drivers/net/wireguard/device.c` L280-296 @v6.18 |
| W2 | `wg-quick` derives the interface MTU from the endpoint route minus 80; `amneziawg-tools` takes the maximum across endpoints where upstream takes the minimum | `cmd ip link set mtu $(( mtu - 80 )) up dev "$INTERFACE"` | `wg-quick/linux.bash` in both repositories above |
| W3 | AmneziaWG pads handshake messages with S1/S2 and, in newer versions, transport messages with S4 | "S1: int - padding of handshake initial message"; "S4: int - padding of transport messages" | `https://raw.githubusercontent.com/amnezia-vpn/amneziawg-go/master/README.md`; `https://docs.amnezia.org/documentation/amnezia-wg/`; the legacy kernel-module README lists no S3 or S4 |
| W4 | MSS clamp to path MTU in nftables | "'tcp option maxseg size set rt mtu' is equivalent to '-j TCPMSS --clamp-mss-to-pmtu'." Requires "Linux kernel 4.14 and nftables 0.9". | `http://wiki.nftables.org/wiki-nftables/index.php/Mangling_packet_headers` |
| W5 | Tailscale's forwarding-host advice | "Tailscale version 1.54 or later used with a Linux 6.2 or later kernel enables UDP throughput improvements using transport layer offloads." Command: `ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off`, not persistent across reboots. | `https://tailscale.com/kb/1320/performance-best-practices` |
| W6 | Repository facts: the host sets Jc=4, Jmin=50, Jmax=1000, S1=S2=200 and no S3/S4; the module forces `ip_forward=1`, IPv6 forwarding 0, `log_martians=1`, redirects off, `accept_source_route=0`, masquerades `192.168.1.0/24` out of `awg0`, and has no MSS clamp or conntrack setting | n/a | `modules/amnezia-vpn-gateway/default.nix:610-617, 719-753, 883, 903-918`; `flake-modules/hosts/home-vpn-gateway-1/default.nix:100-124` |
| W7 | MSS is the effective MTU minus the fixed IP and TCP headers, and the timestamp option adds 10 to 12 bytes to the TCP header. With MTU 9000 the advertised MSS is 9000 - 20 - 20 = 8960; the 8948 payload per segment with timestamps is derived here (8960 - 12), not quoted | "The MSS value to be sent in an MSS option should be equal to the effective MTU minus the fixed IP and TCP headers."; "adding 10 bytes (up to 12 bytes including padding) to the 20-byte TCP header." | `https://www.rfc-editor.org/rfc/rfc6691.txt` section 4; `https://www.rfc-editor.org/rfc/rfc7323.txt` section 3.2 |
| W8 | No prose source gives WireGuard's overhead. Both pinned code lines assume the IPv6 worst case, 80 bytes (32 + 8 + 40). "60 bytes over IPv4" is arithmetic (20 + 8 + 32) that WireGuard does not state | `cmd ip link set mtu $(( mtu - 80 )) up dev "$INTERFACE"`; `dev->mtu = ETH_DATA_LEN - overhead;` | `src/wg-quick/linux.bash` @v1.0.20210914 in `github.com/WireGuard/wireguard-tools`; `drivers/net/wireguard/device.c` @v6.18 |
| W9 | The AmneziaWG kernel-module README bounds `S1`, `S2` and `Jmax` by an assumed 1280-byte connection MTU. That is an assumption behind the parameter limits, not a recommended tunnel MTU, which stays unsourced | "Assuming a basic internet connection with an MTU value of 1280." | `README.md` @4569c4c in `github.com/amnezia-vpn/amneziawg-linux-kernel-module` |

### Storage, NFS and virtual machines

| ID | Finding | Quote or code | Source |
|---|---|---|---|
| N1 | `nconnect` and I/O size limits | "up to a limit of 16"; "The largest read payload supported by the Linux NFS client is 1,048,576 bytes" | `https://man7.org/linux/man-pages/man5/nfs.5.html` |
| N2 | The TCP RPC slot table starts at 2 and grows dynamically, up to 65536; 16 is the UDP default | `xprt_tcp_slot_table_entries = RPC_MIN_SLOT_TABLE;` with `RPC_MIN_SLOT_TABLE (2U)` and `RPC_MAX_SLOT_TABLE_LIMIT (65536U)` | `net/sunrpc/xprtsock.c:73-75`, `include/linux/sunrpc/xprt.h:22-25`, `net/sunrpc/xprt.c:1704` (`xprt_dynamic_alloc_slot`) @v6.18 |
| N3 | `nfsd` thread default | "By default, eight threads are started" | `https://man7.org/linux/man-pages/man8/rpc.nfsd.8.html` |
| N4 | The dynamic RPC slot allocation commit is in v3.1: `xprt_dynamic_alloc_slot` is in `net/sunrpc/xprt.c` at v3.1 and absent at v3.0 (probe) | "Allow the number of available slots to grow with the TCP window size." | commit d9ba131d8f58 "SUNRPC: Support dynamic slot allocation for TCP connections" (`https://api.github.com/repos/torvalds/linux/commits/d9ba131d8f58c0d2ff5029e7002ab43f913b36f9`); probe on `net/sunrpc/xprt.c` @v3.0, @v3.1 |
| V1 | libvirt multiqueue on an interface uses the `queues` attribute of its `<driver>` element and requires a virtio model; libvirt's own example pairs it with `name='vhost'` | "The optional queues attribute controls the number of queues to be used for either Multiqueue virtio-net or vhost-user"; "Use of multiple packet processing queues requires the interface having the <model type='virtio'/> element." | `https://libvirt.org/formatdomain.html` (v12.9.0) |
| V2 | Host iptables on a VM bridge blocks guest traffic unless disabled; the kernel default is 1 | "generally such processing is *not* desired, as it results in guest traffic being blocked due to host iptables rules"; "pass bridged IPv4 traffic to iptables' chains. Default: 1 (enabled)" | `https://wiki.libvirt.org/Net.bridge.bridge-nf-call_and_sysctl.conf.html`; ip-sysctl L3289-3296 |
| V3 | k3s flags | "Disable running kube-proxy" (`--disable-kube-proxy`); Cilium's k3s guide: "If running Cilium in :ref:`kubeproxy-free` mode, add option ``--disable-kube-proxy``" (raw RST) | `https://github.com/k3s-io/docs` `docs/cli/server.md:159`; `github.com/cilium/cilium` v1.20.4 `Documentation/installation/k3s.rst:23-32` |
| V4 | The `net.bridge.*` sysctls are registered by `br_netfilter`, which registers them when it initialises (as a module, or built in); the bridge documentation says the module is needed only to filter bridged packets with `ip(6)tables` | `register_net_sysctl_sz(net, "net/bridge", table, ARRAY_SIZE(brnf_table))`; `module_init(br_netfilter_init);`; "br_netfilter is only needed if users, for some reason, need to use ip(6)tables to filter packets forwarded by the bridge" | `net/bridge/br_netfilter_hooks.c` @v6.18; `Documentation/networking/bridge.rst` @v6.18 |
| K8 | The Cilium 1.20.4 chart refuses to render unless `kubeProxyReplacement` is `true` or `false`, so `strict` is rejected by that chart. Repository: `k8s-setup/cilium-hr.yaml` pins chart `1.16.4` (L13) and sets `kubeProxyReplacement: strict` (L22); the master's cilium manifest is commented out in `flake-modules/hosts/home-k8s-master-1/default.nix` L161-163, so the repository cannot show which release the live cluster runs. Whether `strict` was valid in 1.16.4 is unchecked | "kubeProxyReplacement must be explicitly set to a valid value (true or false) to continue." | `install/kubernetes/cilium/templates/cilium-configmap.yaml` @v1.20.4 in `github.com/cilium/cilium` |

## Corrections to what we believed

- DualPI2 needs kernel 6.17, not 6.18 (Q4).
- `nf_conntrack_buckets` is writable at runtime; it is not module-parameter
  only (K2). `nf_conntrack_max` defaults to the bucket count, not eight times it
  (K1).
- The kernel's TCP RPC slot table starts at 2, not 16 (N2).
- BBR has not required `fq` since 4.13 (C1), although the v6.18 Kconfig help
  still says so (C2).
- On the CachyOS desktops the congestion-control default is cubic and nothing in
  CachyOS-Settings changes it, so `bbr` in `modules/base` is a deliberate
  override (C5). Which module `bbr` names depends on the kernel layout (C6);
  on the running 7.3 kernel BBRv3 is the separate `bbr3`.
- `fs.dentry-negative` is a mainline sysctl, not a CachyOS patch (B13).
- `log_martians = 0` in base is the kernel default (B11).
- Cilium overrides a global `rp_filter = 1` at startup (R5), so the strict
  `rp_filter` that base sets does not hold on Cilium nodes after the agent
  starts.

## Decision

Proposed. Each item names the evidence it rests on. None is applied by this
record, and each is its own change with a before-and-after measurement.

1. **Cilium nodes opt out of strict `rp_filter`.** `home-k8s-master-1` and any
   other host running Cilium stop setting `all.rp_filter` and
   `default.rp_filter`, because the agent owns them and the larger of `all` and the interface value
   applies (R1, R5, R6). The master's
   `accept_local` and `route_localnet` stay.
2. **Hosts with asymmetric or fwmark routing may need loose `rp_filter` (2)
   (R2); measure first.** The candidates are the gateway and
   `download-server-1`, the two hosts in the Context that run a VPN client.
   Neither changes yet: `awg-quick` and `wg-quick` set `src_valid_mark` for
   full tunnels (R3, R4), so strict mode may already work. Check `nstat -az |
   grep IPReversePathFilter` under load, and change a host to loose only if
   the counter shows drops.
3. **Drop `dualpi2` as the base `default_qdisc`.** The documented benefit is for
   L4S traffic only (Q5), no sender here meets the L4S requirements (Q6), and
   mainline 6.18 has no TCP Prague (Q7). The setting does not reach virtual
   devices such as `veth` and `awg0`, which get `noqueue` (Q1, Q2); on a
   multiqueue NIC it becomes the leaf under an `mq` root (Q3). Desktops keep
   `cake` (the desktop module already forces it; Q8 lists what `cake` needs
   in order to shape). Hosts that send bulk data (storage, download) use
   `fq`, as ESnet recommends (C8). Kubernetes nodes get no base-qdisc change: Cilium's
   bandwidth manager documents its own MQ/FQ setup on the physical device
   (C10, C9). `k8s-setup/cilium-hr.yaml` sets `bandwidthManager.enabled: true`
   and `bbr: true`, but whether that release is what runs on the master, and
   what its NIC carries, was not checked. The gateway and the
   hypervisor use `fq_codel`; there is no source that prefers it over `fq`
   there, so this is chosen by measurement (bufferbloat test through the
   tunnel).
4. **Congestion control by role.** Storage and the hypervisor, which are
   LAN-dominated, use the mainline kernel default, cubic (C11, C13), as ESnet advises leaving the
   congestion control at its default (C8). What the name `bbr`
   selects depends on the kernel build (C4, C6, C7). Whether
   `download-server-1`, which faces WAN peers, keeps `bbr` is decided from an
   `iperf3` comparison, not from a document. The gateway's setting only affects
   its own sockets, which is a design argument, not a sourced one.
5. **Drop settings that equal or undercut the kernel default.** Remove
   `log_martians = 0`, which is the kernel default (B11). Remove the `optmem_max`
   override: base sets 64 KiB and the documented default is 128 KB (B4).
6. **Return `tcp_rmem` and `tcp_wmem` defaults to the kernel's** (131072 and
   16384, B1) on `download-server-1` and the Kubernetes nodes, keeping the
   16 MiB maxima, which exceed the documented 4 MiB default (B2, B3). For
   receive, `tcp_rmem[2]` is the autotuning cap; `rmem_max` and `wmem_max` cap
   explicit `SO_RCVBUF` and `SO_SNDBUF`, and the `tcp_wmem` text says its maximum
   does not override `wmem_max` (B14). Base sets all of them to 16 MiB, so the
   two agree. ESnet's examples do not agree on the
   middle value: 87380 in one, 131072 in another (B10); we keep the 6.18
   default. The memory saving per connection is not documented; measure with
   `ss -tm` before and after.
7. **Do not set conntrack values on Kubernetes nodes.** kube-proxy sets
   `nf_conntrack_max` and the established timeout itself (K4), and it is not
   disabled on the master (see the Context); Cilium keeps its own tables besides (K5). Whether to disable kube-proxy now that Cilium replaces it is a
   separate decision (V3).
8. **Gateway: measure, then clamp.** Find the largest unfragmented payload
   through the tunnel with `ping -M do -s <size>`. If it is below the path MTU,
   add an nftables rule `tcp flags syn tcp option maxseg size set rt mtu` on
   `oifname "awg0"` (W4). `awg-quick` derives the MTU from the endpoint route
   (W2) and the handshake and transport padding changes message sizes (W3);
   `tcp_mtu_probing` is the fallback for black holes (B8). Set `MTU =` in the client config, which is not in
   this repository (W6). Apply the Tailscale offload advice (W5) only to the
   WAN-facing device and only after checking the NIC accepts it.
9. **NFS keeps `nconnect=8` and 1 MiB I/O sizes** (N1), and no slot-table sysctl,
   since the client grows its table dynamically (N2, since v3.1: N4). `rpc.nfsd` documents a
   default of eight threads (N3); `home-storage-server-1` overrides that with
   `nproc = 32`, so its thread count is not a network-sysctl question.
10. **Hypervisor: check bridge netfilter.** Read `sysctl net.bridge` on the
    host. If `br_netfilter` is loaded, set `bridge-nf-call-iptables`,
    `-ip6tables` and `-arptables` to 0 (V2). The guests' multiqueue virtio
    needs the `queues` attribute on the interface's `<driver>` element and a
    virtio model (V1). The guest definitions in
    `libvirtd/home-kvm-hypervisor-1/domains/` already set `queues` on
    `<driver name='vhost'>` (read from those files, not checked here). `br_netfilter` registers the
    `net.bridge.*` sysctls only once it is initialised, and the kernel docs say it
    is needed only for `ip(6)tables` on bridged traffic (V4).
11. **Desktops: measure `netdev_budget`.** Revert the three NAPI values to the
    kernel defaults (B5) on laptops and the Deck if a flent RRUL run shows
    lower latency. No document states the latency effect.
12. **Leave alone:** `hpet.max-user-freq` (B12) and `fs.dentry-negative`
    (B13), both harmless.

## Established since the first round

These started as unsourced items. Each is now backed by a row, with the limit
of what the row shows.

- mac80211 keeps per-station queues (Q11, Q10). That a root qdisc on a Wi-Fi
  interface therefore adds little stays inference.
- `cake`'s `ack-filter` exists as a code comment in `sch_cake.c`, not as a
  documented option (Q12).
- `tcp_bbr.c` at v6.18 has no ECN code (C12); C3 supports only the loss statement, and end-to-end ECN handling by core
  TCP is not covered.
- `accept_local` is tied to `rp_filter` only in `fib_frontend.c` (R7); the
  `route_localnet` link is unproven.
- `tcp_rmem[2]` caps receive autotuning and `rmem_max` and `wmem_max` cap
  explicit `SO_RCVBUF` and `SO_SNDBUF` (B14). The `tcp_wmem` text leaves the
  send-side autotuning cap unclear.
- `net.bridge.*` exists once `br_netfilter` is initialised (V4).
- MSS at MTU 9000 is 8960, and 8948 with timestamps by arithmetic (W7).
- NFS dynamic RPC slots arrived in v3.1 (N4).
- WireGuard overhead: code gives 80 (IPv6 worst case); 60 over IPv4 is
  arithmetic, not a stated figure (W8, W1).
- AmneziaWG's README assumes a 1280 MTU for its parameter limits (W9).
- Cilium 1.20.4 rejects `kubeProxyReplacement: strict` (K8).
- Cubic is the mainline and nixpkgs default congestion control (C13).

## Not decided, no source

These came from the first round of research. No primary source read states
them; each line says what was searched. Each stays open until one does or a
measurement answers it.

- That a root qdisc on a Wi-Fi interface adds little because mac80211 queues per
  station. Q11 documents the queues only; the conclusion is inference.
- Recommended `gc_thresh` values. Searched: the `ip-sysctl` defaults (128, 512,
  1024; K6), Cilium tuning docs, Kubernetes sysctl docs and Calico felix docs.
  None gives a recommendation, and Cilium keeps its own neighbour map.
- Sunshine or Moonlight UDP buffer guidance. Searched: Sunshine v2026.914.233613
  docs and `src/network.cpp`, `stream.cpp`, `misc.cpp`, which set no `SO_RCVBUF`
  and mention no `rmem`. The Moonlight wiki was not searched.
- That a 1 MiB default socket buffer costs meaningful memory on hosts with many
  connections. Searched: `ip-sysctl`, `socket(7)`, `tcp(7)` and `sock.h`; none
  says buffers are or are not preallocated. This is why decision 6 needs a
  measurement.
- Whether the Jovian kernel on the Steam Deck provides `bbr`, `bbr3` and
  `dualpi2`. The nixpkgs result (C13) is inferred from `autoModules`; no built
  `.config` was inspected.
- Whether laptops run a VPN client. The Framework laptop's comments mention
  Tailscale, but the option value was not evaluated.
- Which Cilium release the live cluster runs, and whether `strict` was valid in
  1.16.4 (K8).
- AmneziaWG's recommended tunnel MTU. `docs.amnezia.org` was not searched; the
  README gives only an assumption (W9).
- The libvirt macvtap host-to-guest limit is dropped: guests here use bridges.

## Consequences

- Every network sysctl the fleet sets can be traced to a quote, or is listed as
  unsourced. A reviewer can reject a change by showing its row is wrong.
- Several settings now have a measurement attached instead of a belief. That
  costs benchmark time on live hosts, so each change is a separate commit that
  can be reverted alone.
- `modules/base` keeps applying one block to every host until these changes
  land; this record does not change any value.

## Revisit when

A kernel upgrade changes a default quoted above (the 6.18 change to
`rmem_max` is the pattern), CachyOS changes its BBRv3 layout again (C6),
`cake_mq` reaches the shipped kernel (Q9), or a measurement contradicts one of
the proposals.
