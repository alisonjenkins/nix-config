# The weekly token review (ADR 0037): stage 1 builds the digest with a low-cost model and
# falls back to the mechanical baseline, stage 2 turns the digest into a findings file.
# Output stays in review.stateDir; the runner never commits and sends no prompt or file
# content to a model, only the aggregates and references the digest holds.
{ lib, pkgs, cfg, ... }:
let
  inherit (cfg) review;

  stage1Prompt = ''
    You are stage 1 of a weekly token-use review. Use only the cc-obs-query command line tool,
    and only its digest --baseline, top, tool, session and repeats subcommands.
    1. Run: cc-obs-query digest --baseline --since @SINCE@ --pack @PACK@
       This prints the digest skeleton. Keep its structure and keys exactly.
    2. For a question whose rows show an anomaly, run at most 3 drill-down commands for that
       question (for example cc-obs-query session <id> for a top offender), and use what they
       return to choose evidence references. Add no other keys.
    3. Reply with only the final digest as one JSON object, with "stage1" set to "model".
    Never include prompt text, file content or command output beyond aggregates and references.
  '';

  stage2Prompt = ''
    You are stage 2 of a weekly token-use review. The digest JSON on stdin is your only input;
    use no tools. Write at most 5 findings ranked by estimated saving, each exactly as:
    ## <n>. <title> - est. saving <tokens>/week (<percent>%)
    Evidence: <references from the digest>. Suggested action: build-tool | configure | dismiss. Status: proposed
    Dismissed items from prior_decisions keep their earlier reason. Reply with only the findings.
    Never quote prompt text or file content.
  '';

  # Stage 1 may only run these cc-obs-query subcommands (aggregates and references),
  # through the Bash tool alone: no Read, Glob or Grep over the transcripts.
  stage1Allowed = lib.concatMapStringsSep "," (sub: "Bash(cc-obs-query ${sub}:*)")
    [ "digest --baseline" "top" "tool" "session" "repeats" ];

  runner = pkgs.writeShellApplication {
    name = "observability-stack-review";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.gnused pkgs.gnugrep cfg.ledger.package ];
    text = ''
      state=''${REVIEW_STATE_DIR:-${lib.escapeShellArg review.stateDir}}
      claude_cmd=''${REVIEW_CLAUDE-${lib.escapeShellArg review.claudeCommand}}
      query=''${REVIEW_QUERY:-cc-obs-query}
      pack=''${REVIEW_PACK:-${lib.escapeShellArg "${review.tokenEfficiencyDir}/questions.yaml"}}
      digest_model=''${REVIEW_DIGEST_MODEL:-${lib.escapeShellArg review.digestModel}}
      analysis_model=''${REVIEW_ANALYSIS_MODEL:-${lib.escapeShellArg review.analysisModel}}
      budget_digest=''${REVIEW_BUDGET_DIGEST:-${toString review.maxBudgetUSD.digest}}
      budget_analysis=''${REVIEW_BUDGET_ANALYSIS:-${toString review.maxBudgetUSD.analysis}}
      now=''${REVIEW_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
      period_days=7
      max_findings=5
      # Five findings of a few lines each come to about 2 KiB; 16 KiB leaves room for evidence lists.
      max_findings_bytes=16384

      mkdir -p "$state/digests" "$state/findings" "$state/failures"
      work=$(mktemp -d "$state/work.XXXXXX")
      trap 'rm -rf "$work"' EXIT

      # Every stage is tagged so cc-obs-query leaves the review's own spend out of its data.
      otel=''${OTEL_RESOURCE_ATTRIBUTES:+$OTEL_RESOURCE_ATTRIBUTES,}review.run=1

      fail() {
        local stage=$1 code=$2 message=$3
        jq -n --arg stage "$stage" --argjson exit "$code" --arg at "$now" --arg message "$message" \
          '{stage: $stage, exit: $exit, at: $at, message: $message}' > "$state/failures/''${now//[-:]/}-$stage.json"
        printf 'event=review_failed stage=%s exit=%s message=%q\n' "$stage" "$code" "$message" >&2
        exit 1
      }

      run_claude() {
        local model=$1 budget=$2 prompt=$3 out=$4 input=$5
        shift 5
        # Run from the scratch dir so nothing a stage writes can land in the caller's cwd.
        (
          cd "$work"
          env OTEL_RESOURCE_ATTRIBUTES="$otel" \
            "$claude_cmd" -p "$prompt" --output-format json --model "$model" --max-budget-usd "$budget" \
            --setting-sources "" --strict-mcp-config --disable-slash-commands "$@" < "$input" > "$out"
        )
      }

      stage_ok() { jq -e '.is_error == false' "$1" >/dev/null 2>&1; }

      # Coverage is what reached a findings file: a run whose stage 2 failed leaves a digest
      # but no findings, and its week must be covered again. With no model the digest is
      # the only output, so it counts.
      since_days=$period_days
      if [ -n "$claude_cmd" ]; then
        last=$(find "$state/findings" -name '*.md' | sort | tail -n 1)
        last_end=""
        if [ -n "$last" ]; then last_end=$(sed -n 's|^period: .*/||p' "$last" | head -n 1); fi
      else
        last=$(find "$state/digests" -name '*.json' | sort | tail -n 1)
        last_end=""
        if [ -n "$last" ]; then last_end=$(jq -r '.period.end[0:10] // empty' "$last" 2>/dev/null || true); fi
      fi
      if [[ "$last_end" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        gap=$(jq -rn --arg now "''${now:0:10}T00:00:00Z" --arg end "''${last_end}T00:00:00Z" '(($now | fromdate) - ($end | fromdate)) / 86400 | floor' 2>/dev/null || echo 0)
        if [ "$gap" -gt "$period_days" ]; then
          since_days=$gap
          printf 'event=review_catchup gap_days=%s last_covered=%s\n' "$gap" "$last_end" >&2
        fi
      fi
      since="''${since_days}d"

      stage1_prompt=${lib.escapeShellArg stage1Prompt}
      stage1_prompt=''${stage1_prompt//@SINCE@/$since}
      stage1_prompt=''${stage1_prompt//@PACK@/$pack}

      digest="$work/digest.json"
      cost_digest=0
      have_digest=0
      if [ -n "$claude_cmd" ]; then
        if run_claude "$digest_model" "$budget_digest" "$stage1_prompt" "$work/stage1.json" /dev/null \
            --tools Bash --allowedTools ${lib.escapeShellArg stage1Allowed}; then
          if stage_ok "$work/stage1.json" \
            && jq -er '.result' "$work/stage1.json" | sed -e '/^```/d' > "$work/draft.json" \
            && "$query" digest --write "$work/draft.json" --since "$since" --pack "$pack" --out "$digest" >/dev/null; then
            have_digest=1
          else
            echo "event=review_stage1_rejected fallback=baseline" >&2
          fi
        else
          echo "event=review_stage1_failed exit=$? fallback=baseline" >&2
        fi
        # Stage 1 spent money even when its digest was dropped for the baseline.
        if [ -s "$work/stage1.json" ]; then
          cost_digest=$(jq -r '(.total_cost_usd // 0) | tonumber' "$work/stage1.json" 2>/dev/null || echo 0)
        fi
      else
        echo "event=review_models_off reason=no_claude_command" >&2
      fi

      if [ "$have_digest" = 0 ]; then
        if "$query" digest --baseline --since "$since" --pack "$pack" --out "$digest" >/dev/null; then
          :
        else
          fail digest $? "cc-obs-query digest --baseline failed"
        fi
      fi

      host=$(jq -r '.host' "$digest")
      end=$(jq -r '.period.end[0:10]' "$digest")
      id="$end-$host"
      # The id becomes a file name under the state dir; the host comes from model output.
      if ! [[ "$end" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$host" == *..* ]]; then
        fail digest 0 "digest host or period end is not safe to use in a file name"
      fi
      cp "$digest" "$state/digests/$id.json.tmp"
      mv "$state/digests/$id.json.tmp" "$state/digests/$id.json"
      printf 'event=review_digest_saved id=%s stage1=%s\n' "$id" "$(jq -r '.stage1' "$digest")" >&2

      if [ -z "$claude_cmd" ]; then
        exit 0
      fi

      if run_claude "$analysis_model" "$budget_analysis" ${lib.escapeShellArg stage2Prompt} "$work/stage2.json" "$digest" --tools ""; then
        stage_ok "$work/stage2.json" || fail analysis 0 "stage 2 reported an error"
      else
        fail analysis $? "stage 2 exited nonzero (budget ceiling or error)"
      fi

      # Findings are written to a file the owner promotes into the repository: keep them to
      # the documented shape and size, and never write a literal "null".
      body=$(jq -r '.result // empty' "$work/stage2.json" 2>/dev/null || true)
      if [ -z "$body" ]; then fail analysis 0 "stage 2 returned no findings"; fi
      if [ "$(printf '%s' "$body" | wc -c)" -gt "$max_findings_bytes" ]; then
        fail analysis 0 "stage 2 findings are over $max_findings_bytes bytes"
      fi
      headings=$(printf '%s\n' "$body" | grep -c '^## ' || true)
      stray=$(printf '%s\n' "$body" | grep '^## ' | grep -vc '^## [1-5]\. ' || true)
      if [ "$headings" -lt 1 ] || [ "$headings" -gt "$max_findings" ] || [ "$stray" -ne 0 ] \
        || ! printf '%s\n' "$body" | grep -m1 . | grep -q '^## 1\. '; then
        fail analysis 0 "stage 2 findings are not 1 to $max_findings headings numbered '## 1.' onwards"
      fi

      cost_total=$(jq -n --argjson a "$cost_digest" --argjson b "$(jq '(.total_cost_usd // 0) | tonumber' "$work/stage2.json")" \
        '(($a + $b) * 1000000 | round) / 1000000')
      {
        echo "---"
        echo "review: $id"
        echo "host: $host"
        echo "period: $(jq -r '.period.start[0:10]' "$digest")/$end"
        echo "pack_version: $(jq -r '.pack.version' "$digest")"
        echo "own_cost_usd: $cost_total"
        echo "---"
        printf '%s\n' "$body"
      } > "$state/findings/$id.md.tmp"
      mv "$state/findings/$id.md.tmp" "$state/findings/$id.md"
      printf 'event=review_findings_saved id=%s own_cost_usd=%s\n' "$id" "$cost_total" >&2
    '';
  };
in
{
  inherit runner;
}
