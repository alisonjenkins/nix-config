# Fast UNIT tests (seconds, no VM) for the Hetzner node boot/heal bash logic [V27].
# Mocks kubectl/curl/yq/systemctl on PATH; PATH deliberately omits inetutils
# (hostname) + gnugrep to guard the bare-command-127 class [B27].
#   nix build .#checks.x86_64-linux.hetzner-node-heal
{ ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
      checks.hetzner-node-heal =
        let
          heal = ../lib/hetzner-node-heal.sh;
          mocks = pkgs.symlinkJoin {
            name = "heal-mocks";
            paths = [
              # hcloud metadata: emit YAML carrying the scenario instance-id
              (pkgs.writeShellScriptBin "curl" ''echo "instance-id: ''${MOCK_INSTANCE_ID:-null}"'')
              # yq '.instance-id' — pull the value out of that YAML
              (pkgs.writeShellScriptBin "yq" ''${pkgs.gnused}/bin/sed -n 's/^instance-id: //p' '')
              # systemctl — record the call
              (pkgs.writeShellScriptBin "systemctl" ''echo "systemctl $*" >> "$CALLLOG"'')
              # k3s kubectl … — canned reads from env, record mutations
              (pkgs.writeShellScriptBin "k3s" ''
                shift   # drop 'kubectl'
                if [ "$1" = get ] && [ "$2" = --raw=/readyz ]; then exit 0; fi
                if [ "$1" = get ] && [ "$2" = node ]; then echo "''${MOCK_PROVIDERID:-}"; exit 0; fi
                if [ "$1" = get ] && [ "$2" = volumeattachments ]; then printf '%b' "''${MOCK_VAS:-}"; exit 0; fi
                if [ "$1" = delete ]; then echo "kubectl $*" >> "$CALLLOG"; exit 0; fi
                exit 0
              '')
            ];
          };
        in
        pkgs.runCommand "hetzner-node-heal-test"
          { nativeBuildInputs = [ pkgs.bash pkgs.gnugrep ]; } ''
          set -euo pipefail
          # The SCRIPT runs under a constrained node-side PATH: coreutils + gawk +
          # mocks ONLY — NO inetutils(hostname), NO gnugrep — so a regression to a
          # bare `hostname`/`grep` fails here in seconds [B27]. The test's own
          # assertions keep the full builder PATH (grep etc.).
          run() {
            env "$@" \
              PATH="${mocks}/bin:${lib.makeBinPath [ pkgs.coreutils pkgs.gawk ]}" \
              CALLLOG="$PWD/calllog" KUBECONFIG=/dev/null \
              HEAL_API_RETRIES=0 NODE_NAME_OVERRIDE=cp ${pkgs.bash}/bin/bash ${heal}
          }

          echo "## A: providerID matches -> no-op"
          : > calllog
          outA=$(run MOCK_INSTANCE_ID=146 MOCK_PROVIDERID=hcloud://146 2>&1) || { echo "exit!=0: $outA"; exit 1; }
          echo "$outA"
          grep -q "no heal needed" <<<"$outA" || { echo "FAIL A: expected no-op"; exit 1; }
          [ ! -s calllog ] || { echo "FAIL A: no-op mutated: $(cat calllog)"; exit 1; }

          echo "## B: stale providerID -> heal (own VA + node + restart)"
          : > calllog
          outB=$(run MOCK_INSTANCE_ID=999 MOCK_PROVIDERID=hcloud://OLD \
                     MOCK_VAS="csi-mine cp\ncsi-other worker\n" 2>&1) || { echo "exit!=0: $outB"; exit 1; }
          echo "$outB"
          grep -q "delete volumeattachment csi-mine" calllog || { echo "FAIL B: own VA not deleted"; cat calllog; exit 1; }
          ! grep -q "csi-other" calllog || { echo "FAIL B: other node's VA touched"; exit 1; }
          grep -q "delete node cp" calllog || { echo "FAIL B: stale node not deleted"; cat calllog; exit 1; }
          grep -q "restart .*k3s-server-bootstrap" calllog || { echo "FAIL B: bootstrap not restarted"; cat calllog; exit 1; }

          echo "## C: no instance-id -> skip"
          : > calllog
          outC=$(run MOCK_INSTANCE_ID=null MOCK_PROVIDERID=hcloud://OLD 2>&1) || { echo "exit!=0: $outC"; exit 1; }
          echo "$outC"
          grep -q "no instance-id" <<<"$outC" || { echo "FAIL C: expected skip"; exit 1; }
          [ ! -s calllog ] || { echo "FAIL C: skip mutated"; exit 1; }

          echo "ALL PASS"
          touch $out
        '';
    };
}
