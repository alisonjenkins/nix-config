{ pkgs, lib, cfg }:
let
  configExe = lib.getExe' cfg.package "config.sh"; # wrapped: honors RUNNER_ROOT
  runExe = lib.getExe' cfg.package "run.sh"; # wrapped: honors RUNNER_ROOT
  labelsCsv = lib.concatStringsSep "," cfg.extraLabels;

  tokenFileArg = lib.escapeShellArg (toString cfg.tokenFile);
  runnerDirArg = lib.escapeShellArg (toString cfg.runnerDir);
  reposArg = lib.concatStringsSep " " (map lib.escapeShellArg cfg.repos);
  orgsArg = lib.concatStringsSep " " (map lib.escapeShellArg cfg.orgs);

  # PATH that runner JOBS (and the runner's own git/tar) see. launchd does not
  # inherit /run/current-system/sw/bin, so every dep must be explicit.
  jobPath = lib.makeBinPath ([
    pkgs.nix
    pkgs.git
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gnutar
    pkgs.gzip
    pkgs.bash
  ] ++ cfg.extraPackages);

  repoCache = "${toString cfg.runnerDir}/.org-repo-cache";
  lockDir = "${toString cfg.runnerDir}/.lock";
in
rec {
  # ---- registration / removal token helper ---------------------------------
  # Usage: github-runner-mint-token <repo|org> <owner/repo|org>  -> token on stdout
  regTokenScript = pkgs.writeShellApplication {
    name = "github-runner-mint-token";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      kind="$1"; target="$2"
      tok="$(tr -d '\n' < ${tokenFileArg})"
      if [ "$kind" = "org" ]; then
        url="https://api.github.com/orgs/$target/actions/runners/registration-token"
      else
        url="https://api.github.com/repos/$target/actions/runners/registration-token"
      fi
      curl -fsS -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $tok" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url" | jq -er .token
    '';
  };

  # ---- de-register (watchdog path) -----------------------------------------
  # Usage: github-runner-deregister <repo|org> <target>
  deregisterScript = pkgs.writeShellApplication {
    name = "github-runner-deregister";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils regTokenScript cfg.package ];
    text = ''
      scope="$1"; target="$2"
      export RUNNER_ROOT=${runnerDirArg}
      export HOME=${runnerDirArg}
      remtok="$(github-runner-mint-token "$scope" "$target")" || exit 0
      ${configExe} remove --token "$remtok" || true
    '';
  };

  # ---- spawn: configure + run ONE ephemeral runner, watchdog-bounded -------
  # Usage: github-runner-spawn <repo|org> <target> <url>
  spawnScript = pkgs.writeShellApplication {
    name = "github-runner-spawn";
    runtimeInputs = [ pkgs.coreutils regTokenScript deregisterScript cfg.package ];
    text = ''
      scope="$1"; target="$2"; url="$3"

      export RUNNER_ROOT=${runnerDirArg}
      export HOME=${runnerDirArg}
      # Jobs (and the runner's own git/tar) need a real PATH; launchd gives none.
      export PATH=${jobPath}:"$PATH"
      export RUNNER_ALLOW_RUNASROOT=0

      name="${cfg.runnerNamePrefix}-$(date +%s)-$RANDOM"
      regtoken="$(github-runner-mint-token "$scope" "$target")"

      # Ephemeral => start from clean state; wipe any leftovers from a crash.
      rm -rf "$RUNNER_ROOT/_work" "$RUNNER_ROOT/.runner" \
             "$RUNNER_ROOT/.credentials" "$RUNNER_ROOT/.credentials_rsaparams" || true

      ${configExe} \
        --url "$url" \
        --token "$regtoken" \
        --ephemeral \
        --unattended \
        --replace \
        --disableupdate \
        --name "$name" \
        --labels ${lib.escapeShellArg labelsCsv} \
        --work "$RUNNER_ROOT/_work"

      # --ephemeral: run.sh processes exactly ONE job then de-registers + exits.
      # Watchdog: bound the long-poll so a false-positive (job actually meant for
      # a different label / GitHub-hosted) cannot pin the runner forever.
      rc=0
      timeout --signal=INT ${toString (cfg.spawnTimeoutMinutes * 60)} ${runExe} || rc=$?

      # Watchdog fired (124): runner never took a job and is still registered.
      # Best-effort de-register so we don't leak offline runners.
      if [ "$rc" = "124" ]; then
        echo "watchdog: no job within ${toString cfg.spawnTimeoutMinutes}m, de-registering" >&2
        github-runner-deregister "$scope" "$target" || true
      fi
      exit 0
    '';
  };

  # ---- poller: the launchd-invoked entrypoint ------------------------------
  pollScript = pkgs.writeShellApplication {
    name = "github-runner-poll";
    # The repos/orgs loops iterate Nix-generated word lists whose length varies
    # by config; shellcheck can't see that and warns on single-element lists.
    excludeShellChecks = [ "SC2043" ];
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.procps
      spawnScript
    ];
    text = ''
      LOCK=${lib.escapeShellArg lockDir}
      CACHE=${lib.escapeShellArg repoCache}
      tok="$(tr -d '\n' < ${tokenFileArg})"

      api() { # api <path>  -> JSON on stdout (fails closed)
        curl -fsS \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer $tok" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com$1"
      }

      # ---- concurrency=1 lock (atomic mkdir; reclaim only if no live runner) -
      acquire_lock() {
        if mkdir "$LOCK" 2>/dev/null; then echo $$ > "$LOCK/pid"; return 0; fi
        if ! pgrep -f 'Runner.Listener|github-runner-spawn' >/dev/null 2>&1; then
          rm -rf "$LOCK"
          mkdir "$LOCK" 2>/dev/null && { echo $$ > "$LOCK/pid"; return 0; }
        fi
        return 1
      }
      release_lock() { rm -rf "$LOCK"; }

      # ---- detection: is a queued job waiting that THIS runner should take? --
      # Match iff job is queued AND it asks for a self-hosted runner whose
      # labels we advertise. GitHub-hosted jobs never carry "self-hosted".
      jobs_match() { # stdin: run-jobs JSON -> exit 0 if a matching queued job exists
        jq -e --arg want ${lib.escapeShellArg labelsCsv} '
          ($want | split(",")) as $wl
          | [ .jobs[]
              | select(.status == "queued")
              | select(
                  (.labels | index("self-hosted"))
                  or ([ .labels[] | select(. as $l | $wl | index($l)) ] | length > 0)
                )
            ] | length > 0
        ' >/dev/null 2>&1
      }

      repo_has_queued() { # <owner/repo> -> 0 if a matching queued job exists
        local repo="$1" runs ids id
        runs="$(api "/repos/$repo/actions/runs?status=queued&per_page=20")" || return 1
        ids="$(printf '%s' "$runs" | jq -r '.workflow_runs[].id')" || return 1
        [ -n "$ids" ] || return 1
        for id in $ids; do
          if api "/repos/$repo/actions/runs/$id/jobs" | jobs_match; then return 0; fi
        done
        return 1
      }

      org_repos() { # <org> -> echoes owner/repo lines (cached repoListCacheMinutes)
        local org="$1" maxage chunk n page
        maxage=$(( ${toString cfg.repoListCacheMinutes} * 60 ))
        if [ -f "$CACHE" ] && [ "$(( $(date +%s) - $(stat -f %m "$CACHE") ))" -lt "$maxage" ]; then
          grep -i "^$org/" "$CACHE" || true
          return 0
        fi
        : > "$CACHE.tmp"
        for o in ${orgsArg}; do
          page=1
          while :; do
            chunk="$(api "/orgs/$o/repos?type=all&per_page=100&page=$page")" || break
            n="$(printf '%s' "$chunk" | jq 'length')" || break
            [ "$n" -gt 0 ] || break
            printf '%s' "$chunk" | jq -r '.[].full_name' >> "$CACHE.tmp"
            [ "$n" -lt 100 ] && break
            page=$((page + 1))
          done
        done
        mv "$CACHE.tmp" "$CACHE"
        grep -i "^$org/" "$CACHE" || true
      }

      # ---- tick: cheap detection FIRST (no lock), spawn only on a real hit ---
      hit_scope=""; hit_target=""; hit_url=""
      for repo in ${reposArg}; do
        if repo_has_queued "$repo"; then
          hit_scope=repo; hit_target="$repo"; hit_url="https://github.com/$repo"; break
        fi
      done
      if [ -z "$hit_scope" ]; then
        for org in ${orgsArg}; do
          while IFS= read -r repo; do
            [ -n "$repo" ] || continue
            if repo_has_queued "$repo"; then
              hit_scope=org; hit_target="$org"; hit_url="https://github.com/$org"; break 2
            fi
          done < <(org_repos "$org")
        done
      fi

      if [ -z "$hit_scope" ]; then echo "tick: no queued jobs"; exit 0; fi

      if ! acquire_lock; then echo "tick: runner already active, skip"; exit 0; fi
      trap release_lock EXIT
      echo "tick: queued job for $hit_scope $hit_target -> spawning ephemeral runner"
      github-runner-spawn "$hit_scope" "$hit_target" "$hit_url"
    '';
  };
}
