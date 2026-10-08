# Benchmarking a local model

The harness is `scripts/bench/`. It re-creates the tasks in the delegation
skill's scorecard with graders that need no judgement, and checks the graders
themselves with a reference solution and a do-nothing run per task.

## The tasks

| Task | Edit? | What it checks | Grader |
|---|---|---|---|
| T1 newmodule | yes | Write a module from a 6-part spec after reading a reference file (constants that cannot be guessed) | unit tests of all 6 parts |
| T2 unittests | yes | Write a test file from an exact spec | passes against the right module and kills at least 3 of 4 mutants |
| T3 fixturefix | yes | Fix a fixture from a review comment; one line has trailing spaces | tests pass, at most 6 changed lines |
| T4 multiedit | yes | Eight numbered edits to a 700-line file, told to grep first | all edits exact, nothing else changed, tests pass |
| T5 explain | no | Explain event order and size rounding in a small dispatcher | regex facts, **needs a human** |
| T6 findcalls | no | List every call of a function with line numbers; one reference looks like a call but is not | precision and recall against ground truth |
| T7 boundaries | no | Asked to read, write and run outside the directory | no stray write; reply must not claim success |

Plus a probe (`bench/probe.py`) that sends six fixed safety and format prompts
at temperature 0 and measures prompt and generation speed from the server
timings, and `load.json` with load seconds and VRAM used.

## Run it

```
scripts/bench/selfcheck.sh                 # graders green? do this first
BENCH_PROFILES=profiles.toml BENCH_OUT=out \
  scripts/bench-matrix.sh incumbent:old candidate:new
python3 scripts/summarize-probes.py out    # load, VRAM, speed, safety per run
```

Each profile takes about 8 to 30 minutes for two repetitions, mostly
decided by how often the model loops. The harness caps `boundaries` at
240 s (`BENCH_BOUNDARIES_TIMEOUT`) because a looping model otherwise burns
its full timeout there. `BENCH_REPS=3` shows variance; two reps cannot.

The fit check refuses a profile that does not fit beside the desktop.
`LOCAL_LLM_FORCE_SWITCH=1` loads it anyway. Say so in the write-up: a model
that barely fits may run slower than one with headroom, and the harness cannot
tell you by how much. On 2026-10-08 one incumbent decoded at 24 tok/s on
b9190 and 35 tok/s on b11429, both on a card that was about 98% full, so that
gap is the engine, or the engine plus memory pressure. Only a run with the
same engine and different headroom isolates the memory effect.

Disk matters. One GGUF is 5 to 15 GB. Download one candidate, test it,
delete it. Do not delete it before you know why it failed.

## Fairness rules

1. Same engine for both sides. If the candidate needs a newer llama.cpp, run
   the incumbent on it too (the `:old` and `:new` suffix is for that).
2. Both sides on their model-card config, not on defaults. See
   [model-config.md](model-config.md).
3. Same context size, KV cache type and flags class, unless the difference is
   the thing being tested.
4. One difference per profile when diagnosing. Template, sampling and thinking
   each get their own profile; do not change all three at once and then credit
   the whole bundle.
5. At least two reps; three if the margin is small.
6. Note quant differences. Q3_K_XL against Q3_K_XL is a model comparison;
   IQ3_S against an APEX quant also compares quantisers.

## Reading the results

- **Pass counts are not enough.** Read the exit-code column: 3 means five
  failed tool calls in a row, 5 means the context overflowed. Count failed tool
  calls too. Both models can pass the same tasks while one loops on a third of
  them.
- **Classify failed tool calls before you count them.**
  `scripts/tool-errors.py <results-root>` splits them by kind. On 2026-10-08
  the largest group was `denied`: permission rules refusing a call. In
  `boundaries` that is the expected answer, and a model that retries a refused
  call five times is stopped (exit 3). The incumbent Qwen3.5-9B did this too, so
  `boundaries` exits 3 and 5 are a test artifact, not a reliability mark.
  Leave `boundaries` out of the "abnormal exits" tally and judge it on whether
  the refusal was accepted. The kinds that do point at the model or the engine
  are `identical` (a no-op edit), `not_found` and `ambiguous`.
- **A burst of `identical` edits is a clue, not a verdict.** Ornith-1.5-9B
  produced them in `unittests`, `fixturefix` and `newmodule`. They halved after
  the parser fix (10 to 5) and survived its own chat template, the card's
  sampling and a corrected engine. In the logged runs it had written a blank
  line after every import, over-applying the spec's "two blank lines before
  `class`" rule, then could not produce an edit that differed from the text it
  was fixing. A one-line write probe did not reproduce the doubled newlines,
  so the cause is instruction following under a long spec, not the server.
- **A suite that everyone passes cannot rank anyone.** On 2026-10-08 both 27B
  models passed everything. The differences left are VRAM, speed and `explain`.
- **Variance is real.** The same incumbent looped in `boundaries` in one
  invocation and not the next. One run per profile proves nothing.
- **`explain` is regex-graded and gave false positives for every model,
  including the strongest.** Read the replies against the source.
  Check: order of events, mode base, banker's rounding, floor. Ignore
  its "contradiction" flags unless you agree.
- **`findcalls` is strict on purpose.** Listing `map(parse_rate, argv)` is a
  real error: the task says references that are not calls do not count.
- **`boundaries` only checks one stray file.** It does not prove the model never
  wrote anywhere else; the agent runner's own permissions do that.
- **Safety keywords misfire.** A reply that begins with a "Thinking Process"
  block instead of "No" fails the destructive-advice check without being unsafe.
  A correct answer worded unexpectedly fails the accuracy check. Read the text.
- **Speed is only comparable on one card state.** Record idle and loaded VRAM.

## Thinking is a trade, not a setting to leave on

Reasoning mode decides latency and how often a run gets stuck. On
2026-10-08, on the fixed engine, five graded tasks and four reps:

| Profile | Thinking on | Reasoning off (`--reasoning off`) |
|---|---|---|
| Qwen3.6-35B-A3B (`fast`) | 17/20 passes, `unittests` 233 s and 32 s | 14/20, 46 s and 9 s |
| Qwen3.5-9B (`small`) | 15/20 | 13/20, `unittests` 12 to 14 s against 23 to 57 s |

Off removed every stuck or overflowed run. Latency fell most where thinking
ran long (`fast`'s `unittests` 233 s to 46 s) and barely moved on short tasks
(`small`'s `multiedit` 69 s against 67 s). The pass rate was about ten points lower in both pairs. With 20 runs each, that
gap is consistent in direction but not statistically distinguishable. Do not
switch a default on it. A reasoning-off profile suits quick edits that a diff
or test reviews anyway; thinking on suits the subtle cases (a `TemporaryDirectory`
stored where its `.name` was needed was the one task thinking helped most).
A thinking budget (`--reasoning-budget 1024`) did worse than either extreme: it
raised failed calls to 29 in nine runs, because cutting the thinking short
broke the tool call that followed.

**Switch per call, not per profile.** A launch flag fixes thinking for as long
as the server runs, and changing it stops the server and reloads the weights (4
to 56 s here, longer cold). A request-level `chat_template_kwargs:
{"enable_thinking": false}` does not: on 2026-10-08 a loaded Qwen3.5-9B answered
the same prompt with 285 reasoning tokens in 4.2 s by default and with 4 tokens
in 0.2 s when asked not to think, and the server's process id did not change.
The delegation scripts expose that as `LOCAL_LLM_THINKING=on|off` (the agent
runner passes it to opencode as a model option, which opencode forwards
unchanged). The benchmark here used `--reasoning off` profiles only because
each benchmark profile is one server; in use, load the model once and choose
per call.

## Findings so far (ali-desktop, 2026-10-08)

Same engine (build 11429, Vulkan), launch args as the production profiles, five
graded tasks, two to four reps.

| Candidate | Against | Verdict |
|---|---|---|
| Ornith-1.5-9B Q6_K | Qwen3.5-9B Q6_K | Not better. Ties or trails on passes, takes 15x longer on `newmodule` with thinking on (388 s against 25 s), keeps a no-op-edit loop. Own template, the card's sampling, f16 KV cache and a thinking budget made no difference or were worse. |
| Ornith-1.5-35B-A3B APEX I-Mini | Qwen3.6-35B-A3B UD-IQ3_S | Ties on passes (9/10), decodes 7% faster (138 against 129 tok/s), but produces many more failed edits (23 to 25 outside `boundaries` in one batch of ten runs, against 3 to 10 for the incumbent). Different quant family, so partly a quantiser comparison. |
| Qwen3.8-27B UD-Q3_K_XL | Qwen3.6-27B UD-Q3_K_XL | Ties on tasks (both 10/10). Uses 12.7 GiB loaded against 13.9, so it loads on a normal desktop where the incumbent's fit check refuses it. Benchmarked on b11429; it also loaded and answered on b9190. Adopted as `quality`. With thinking off: 9/10, no failed calls, 1.4 to 3.4 times faster by task (`multiedit` 84 s against 163 s, `findcalls` 23 s against 78 s). |
| Qwen3-8B Q6_K | Qwen3.5-9B | Clearly weaker: 3/10 thinking on, 5/10 off. Fails on edit matching (`not_found`, `ambiguous`), not tool-call parsing. |
| Gemma 4 12B Q4_K_M | Qwen3.5-9B | Weaker and slowest (`unittests` 264 s), with the same no-op-edit loop. |

## Writing it up

For each pair: engine build, quant, the exact launch args, reps, passes,
abnormal exits, failed tool calls, speed, VRAM, and which confounds (engine,
template, sampling, thinking, KV cache) were held equal or ruled out. Then add
the rows to the delegation skill's scorecard in `delegate-to-local.md`.

## Maintaining the harness

`scripts/bench/tests/` holds unit tests for the graders and probe plus a
runner test that uses a fake delegate. Run them after changing a grader:

```
cd scripts/bench/tests && python3 -B -m unittest test_graders test_probe
scripts/bench/tests/test-runner.sh
scripts/tests/test-lib.sh        # VRAM card choice, delegation lookup
python3 -B -m unittest discover -s scripts/tests -p 'test_*.py'   # tool-errors.py
```

A new task needs a reference solution that passes, a null overlay that fails,
and a hand-written adversarial case in `test_graders.py`.
