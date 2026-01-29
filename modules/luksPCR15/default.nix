{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  inherit (lib)
    head
    optional
    foldl'
    nameValuePair
    listToAttrs
    optionals
    concatStringsSep
    sortOn
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options = {
    systemIdentity = {
      enable = mkEnableOption "hashing of Luks values into PCR 15 and subsequent checks";
      pcr15 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The expected value of PCR 15 after all luks partitions have been unlocked
          Should be a 64 character hex string as ouput by the sha256 field of
          'systemd-analyze pcrs 15 --json=short'
          If set to null (the default) it will not check the value.
          If the check fails the boot will abort and you will be dropped into an emergency shell, if enabled.
          In ermergency shell type:
          'systemctl disable check-pcrs'
          'systemctl default'
          to continue booting
        '';
        example = "6214de8c3d861c4b451acc8c4e24294c95d55bcec516bbf15c077ca3bffb6547";
      };
    };
    boot.initrd.luks.devices = lib.mkOption {
      type =
        with lib.types;
        attrsOf (submodule {
          config.crypttabExtraOpts = optionals config.systemIdentity.enable [
            "tpm2-device=auto"
            "tpm2-measure-pcr=yes"
          ];
        });
    };
  };
  config = mkIf config.systemIdentity.enable {
    boot.kernelParams = [
      # "rd.luks=no" # Enable systemd-cryptsetup-generator
    ];

    boot.initrd.availableKernelModules = [
      "tpm_crb"
      "tpm_tis"
    ];

    boot.initrd.systemd.storePaths = [
      "${pkgs.gnugrep}/bin/grep"
      "${pkgs.jq}/bin/jq"
    ];

    boot.initrd.systemd.services =
      {
        check-pcrs = mkIf (config.systemIdentity.pcr15 != null) {
          script = ''
            echo "Checking PCR 15 value"
            if [[ $(systemd-analyze pcrs 15 --json=short | ${pkgs.jq}/bin/jq -r ".[0].sha256") != "${config.systemIdentity.pcr15}" ]] ; then
              echo "PCR 15 check failed"
            fi

            echo "=== PCR 15 Validation Starting ==="
            echo "Expected PCR15: ${config.systemIdentity.pcr15}"

            # Wait a moment for PCR measurements to stabilize after cryptsetup
            echo "Waiting for PCR measurements to stabilize..."
            sleep 2

            # Retry logic for reading PCR15 (in case of transient issues)
            max_attempts="3"
            attempt="1"
            pcr_data=""

            while [[ $attempt -le $max_attempts ]]; do
              echo "Attempt $attempt of $max_attempts to read PCR 15..."
              pcr_data=$(systemd-analyze pcrs 15 --json=short 2>&1 || echo "FAILED_TO_READ_PCR")

              if [[ "$pcr_data" != "FAILED_TO_READ_PCR" ]]; then
                echo "Successfully read PCR data on attempt $attempt"
                break
              fi

              if [[ $attempt -eq $max_attempts ]]; then
                echo "ERROR: Failed to read PCR 15 data after $max_attempts attempts"
                echo "This could indicate TPM issues or systemd-analyze problems"
                # Create debug info that persists
                mkdir -p /run/pcr15-debug 2>/dev/null || true
                echo "PCR15_CHECK_FAILED: Unable to read PCR data after $max_attempts attempts" > /run/pcr15-debug/failure-reason
                echo "$(date): PCR15 check failed - unable to read PCR data" >> /run/pcr15-debug/boot-log
                exit 1
              fi

              echo "Failed to read PCR data, waiting before retry..."
              sleep 1
              attempt=$((attempt + 1))
            done

            echo "Raw PCR data: $pcr_data"

            current_pcr=$(echo "$pcr_data" | ${pkgs.jq}/bin/jq -r ".[0].sha256" 2>/dev/null || echo "PARSE_FAILED")

            # Fallback parsing if jq fails
            if [[ "$current_pcr" == "PARSE_FAILED" || "$current_pcr" == "null" ]]; then
              echo "jq parsing failed, trying alternative method..."
              # Try to extract SHA256 using sed/grep as fallback
              current_pcr=$(echo "$pcr_data" | ${pkgs.gnugrep}/bin/grep -o '"sha256":"[^"]*"' | cut -d'"' -f4 || echo "PARSE_FAILED")
            fi

            if [[ "$current_pcr" == "PARSE_FAILED" || "$current_pcr" == "null" ]]; then
              echo "ERROR: Failed to parse PCR 15 SHA256 value from systemd-analyze output"
              echo "Raw systemd-analyze output was: $pcr_data"
              # Create debug info that persists
              mkdir -p /run/pcr15-debug 2>/dev/null || true
              echo "PCR15_CHECK_FAILED: Parse error" > /run/pcr15-debug/failure-reason
              echo "Expected: ${config.systemIdentity.pcr15}" >> /run/pcr15-debug/failure-reason
              echo "Raw data: $pcr_data" >> /run/pcr15-debug/failure-reason
              echo "$(date): PCR15 check failed - parse error" >> /run/pcr15-debug/boot-log
              exit 1
            fi

            echo "Current PCR15:  $current_pcr"

            if [[ "$current_pcr" != "${config.systemIdentity.pcr15}" ]]; then
              echo "=== PCR 15 CHECK FAILED ==="
              echo "Expected: ${config.systemIdentity.pcr15}"
              echo "Actual:   $current_pcr"
              echo ""
              echo "This indicates the system state has changed since the PCR15 value was recorded."
              echo "Possible causes:"
              echo "- LUKS device configuration changed"
              echo "- TPM PCR measurements changed"
              echo "- Kernel or initrd changes affecting measurement"
              echo ""
              echo "To fix: Boot from recovery media, mount system, and update pcr15Value"
              echo "Get new value with: systemd-analyze pcrs 15 --json=short | ${pkgs.jq}/bin/jq -r '.[0].sha256'"

              # Create debug info that persists to help with troubleshooting
              mkdir -p /run/pcr15-debug 2>/dev/null || true
              echo "PCR15_CHECK_FAILED: Value mismatch" > /run/pcr15-debug/failure-reason
              echo "Expected: ${config.systemIdentity.pcr15}" >> /run/pcr15-debug/failure-reason
              echo "Actual: $current_pcr" >> /run/pcr15-debug/failure-reason
              echo "$(date): PCR15 check failed - value mismatch" >> /run/pcr15-debug/boot-log

            # Also try to save to EFI System Partition for accessibility after boot failure
            if [[ -d /boot/EFI ]] || [[ -d /efi ]]; then
              boot_dir="/boot"
              [[ -d /efi ]] && boot_dir="/efi"

              mkdir -p "$boot_dir/pcr15-debug" 2>/dev/null || true
              {
                echo "PCR15 Boot Failure Debug Info"
                echo "Generated: $(date)"
                echo "Expected: ${config.systemIdentity.pcr15}"
                echo "Actual: $current_pcr"
                echo "Raw PCR data: $pcr_data"
                echo ""
                echo "To resolve:"
                echo "1. Boot from NixOS recovery/installation media"
                echo "2. Mount your system and access the configuration"
                echo "3. Run 'systemd-analyze pcrs 15 --json=short | ${pkgs.jq}/bin/jq -r \".[0].sha256\"'"
                echo "4. Update pcr15Value in configuration.nix with the new value"
                echo "5. Rebuild and reboot"
              } > "$boot_dir/pcr15-debug/failure-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
            fi

              exit 1
            else
              echo "PCR 15 check succeeded"
            fi
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          unitConfig.DefaultDependencies = "no";
          after = [ "cryptsetup.target" ];
          before = [ "sysroot.mount" ];
          requiredBy = [ "sysroot.mount" ];
        };
      };
  };
}
