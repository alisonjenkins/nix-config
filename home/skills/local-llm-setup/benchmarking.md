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
