#!/usr/bin/env bash
# Cattle-replace self-heal [B12,B20,B25]. On boot, a replaced VM's persisted Node
# object carries the OLD providerID + stale VolumeAttachments → CCM can't find the
# server and CSI won't re-attach. If the Node's providerID != this VM's hcloud id,
# drop the stale Node + its VolumeAttachments and restart the server so it
# re-registers cleanly. No-op on a normal reboot (providerID matches).
#
# PATH-driven (no hardcoded store paths) so the systemd unit's `path` provides the
# real tools in prod and the unit test can shim mocks. Externals are overridable
# via env for unit testing:
#   NODE_NAME_OVERRIDE  node name        (default: kernel hostname)
#   METADATA_URL        hcloud metadata  (default: hcloud link-local)
#   KUBECONFIG          kubeconfig       (default: k3s.yaml)
#   HEAL_API_RETRIES    readyz wait iters (default 60; tests set 0 to skip)
#
# set -e (with pipefail): a bare-command failure inside a $(...) aborts the script
# instead of silently yielding empty + falling through to "no heal needed" — so a
# regression to a missing command surfaces (and the PATH-constrained unit test
# catches it). Idempotent mutations below keep explicit `|| true`.
set -euo pipefail

NODE="${NODE_NAME_OVERRIDE:-$(cat /proc/sys/kernel/hostname)}"
METADATA_URL="${METADATA_URL:-http://169.254.169.254/hetzner/v1/metadata}"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

kc() { k3s kubectl "$@"; }

# Wait for the local API to be ready (skippable in tests).
for _ in $(seq 1 "${HEAL_API_RETRIES:-60}"); do
  kc get --raw=/readyz >/dev/null 2>&1 && break
  sleep 5
done

INSTANCE_ID=$(curl -s "$METADATA_URL" | yq '.instance-id')
WANT="hcloud://$INSTANCE_ID"
HAVE=$(kc get node "$NODE" -o jsonpath='{.spec.providerID}' 2>/dev/null || true)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
  echo "no instance-id from metadata — skipping heal"; exit 0
fi
if [ -z "$HAVE" ] || [ "$HAVE" = "$WANT" ]; then
  echo "providerID ok (have=${HAVE:-none}) — no heal needed"; exit 0
fi

echo "stale providerID: have=$HAVE want=$WANT — healing"
# Stale VolumeAttachments: detached at hcloud when the old VM died, but the VA
# still claims attached → CSI won't re-attach [B20]. Delete those on this node.
for va in $(kc get volumeattachments \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers 2>/dev/null \
  | awk -v n="$NODE" '$2==n {print $1}'); do
  echo "deleting stale VolumeAttachment $va"
  kc delete volumeattachment "$va" --wait=false || true
done
# Drop the stale Node so it re-registers fresh (CCM assigns the new providerID by
# name). k3s only registers at startup → restart it [B12].
kc delete node "$NODE" --wait=false || true
echo "restarting k3s-server-bootstrap to re-register the node"
systemctl restart --no-block k3s-server-bootstrap.service || true
