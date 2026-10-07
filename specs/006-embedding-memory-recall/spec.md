# Feature Specification: Embedding-based recall of memories and skills

**Feature Branch**: `worktree-vectorized-inventing-octopus` (spec directory `006-embedding-memory-recall`)

**Created**: 2026-10-07

**Status**: Draft (retrospective: stories 1 to 3 are built and measured; stories 4 to 6 remain)

**Input**: User description: "Use EmbeddingGemma 2 to make Claude's memory and skills more effective and cheaper in tokens and dollars. Build the evaluation harness, a memory-recall hook behind a Nix option, benchmark it against Claude's default memory and cavemem, compare skill loading, close the accuracy gap with the default, then make sure it is not more expensive. Document what is done and what remains."

## Context

The owner's Claude Code sessions load a memory index (`MEMORY.md`, about 3,900 tokens for 83 memories) and a skill listing into every session and every subagent. The model then decides which file to open. Two problems follow: the always-loaded text is large, and the one-line index descriptions hold none of the detail that lives only in a memory's body, so the model often answers without it.

An embedding model (EmbeddingGemma 2, run locally on CPU) can pick the likely-relevant memory or skill section from the user's prompt in tens of milliseconds, with no model call. This work built that retrieval, measured it against the defaults, and found where it helps.

Measured so far (details and raw results: `docs/memory-recall.md`, ADRs 0029 and 0030, `scripts/retrieval-eval/bench/results/`):

- Retrieval puts the right memory in the top 3 for 97% of held-out queries.
- Injecting snippets only (the first design) got 26 to 35% of key facts into the answer. Injecting whole memories above a confidence threshold, with a names-only catalogue in place of the index, reaches 88 to 91%, level with a model that always reads a file (86 to 92%) and about 10 points above a model that opens files only when it asks to.
- The always-loaded index drops from about 3,900 to about 780 tokens.
- With a prompt layout that matches how Claude Code uses the cache, the catalogue plus injection costs $0.025 to $0.028 per query against $0.041 to $0.042 for the defaults (33 to 40% less). An earlier run that showed the opposite was a flaw in the benchmark, corrected in `bb99162e` and `e3026773`.
- For skills, retrieving sections picks the right source 95% of the time at about one sixth of the tokens and $0.020 per query against $0.086 for loading whole skill files.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Trustworthy comparison against the defaults (Priority: P1) — built

The owner needs to know whether embedding retrieval beats Claude's default memory and skill loading on retrieval time, answer quality, detail lost, tokens and dollars, before changing how their sessions work.

**Why this priority**: every other decision depends on a measurement that can be trusted. Two early results were wrong (an orphaned server skewed a timing run; a prompt layout defeated the cache and inflated dollar cost), so correctness of the method is the value.

**Independent Test**: rerun the comparison drivers on the dev and held-out query sets and compare the printed tables with the saved results.

**Acceptance Scenarios**:

1. **Given** a dev set and a held-out set of questions with known key facts, **When** the comparison runs, **Then** it reports retrieval time, facts reaching the model, facts in the answer, tokens, cache reads and writes, and dollars per system.
2. **Given** a call that resumes an earlier conversation, **When** it runs, **Then** the earlier turns are billed as cache reads, not resent at full price.
3. **Given** a rerun merged into saved results, **When** the tables print, **Then** every column, including cache reads and writes, carries through.

---

### User Story 2 - Relevant memories appear without the model asking (Priority: P1) — built

When the owner sends a prompt, the memories most likely to matter are in front of the model already, including detail that is only in the memory body.

**Why this priority**: this is the accuracy gain; without it the token saving would cost answer quality.

**Independent Test**: send the benchmark questions through the hook and check the injected text contains the key facts.

**Acceptance Scenarios**:

1. **Given** a prompt whose best memory scores at or above the whole-memory threshold, **When** the hook runs, **Then** that memory is injected in full.
2. **Given** a best score between the floor and the whole-memory threshold, **When** the hook runs, **Then** only matching snippets are injected.
3. **Given** the embedding server is down, a prompt is too short, or nothing clears the floor, **When** the hook runs, **Then** it injects nothing and exits cleanly, so a prompt is never blocked.
4. **Given** the module option is off, **When** the host builds, **Then** no server, hook or timer is created.

---

### User Story 3 - A smaller always-loaded index (Priority: P2) — built, not adopted

A names-only catalogue replaces the descriptive `MEMORY.md` in context, cutting about 3,100 tokens from every session and subagent while keeping a fallback when retrieval misses.

**Why this priority**: it is where the token and dollar saving comes from, but it changes a file Claude's own memory writer maintains, so it follows the injection.

**Independent Test**: generate the catalogue, count its tokens, and run the benchmark with it as the only index.

**Acceptance Scenarios**:

1. **Given** the memory directory, **When** the catalogue command runs, **Then** it writes one name per memory and rewrites the file only if its content changed.
2. **Given** a new memory saved by Claude, **When** the catalogue is regenerated, **Then** the new name appears.
3. **Given** a query whose memory was not injected, **When** the model sees the catalogue, **Then** 99% of key facts still reach the model across the benchmark.

---

### User Story 4 - Skills get the same treatment (Priority: P2) — built (ADR 0031); acceptance scenario 3 (combined ceiling) not built

When the owner asks for something a skill covers, the relevant skill sections reach the model without it loading whole skill files.

**Why this priority**: the measured saving is larger than for memory (about one sixth of the tokens, $0.020 against $0.086 per query), but no hook exists yet.

**Independent Test**: run the skills comparison with the hook's logic and check the right source is chosen at least as often as the default flow (95%).

**Acceptance Scenarios**:

1. **Given** a prompt that matches a skill section above a threshold, **When** the hook runs, **Then** the section is injected and the skill file is not loaded whole.
2. **Given** no match, **When** the hook runs, **Then** nothing is injected and the skill listing still lets the model choose.
3. **Given** the memory hook is also enabled, **When** both run, **Then** their output is combined without exceeding a stated token ceiling.

---

### User Story 5 - Decide whether to use it for real (Priority: P2) — logging and enablement built; the trial and its decision are the owner's, after `just switch`

The owner turns the module on for their own sessions on `ali-desktop` and decides whether to replace `MEMORY.md` with the catalogue, based on their own prompts rather than the benchmark's.

**Why this priority**: all benchmark queries had a matching memory; real prompts mostly do not, and those pay the injection's overhead for nothing.

**Independent Test**: enable the option, use it for a trial period with logging on, and read the log.

**Acceptance Scenarios**:

1. **Given** the module is enabled, **When** a prompt is sent, **Then** the hook records the prompt's best score, what was injected and how many tokens it added, without recording the prompt text.
2. **Given** a trial of real prompts, **When** the log is summarised, **Then** it states the share of prompts with a matching memory and the average tokens added per prompt.
3. **Given** the summary, **When** the owner decides, **Then** the decision and its numbers go into an ADR.

---

### User Story 6 - Land the work (Priority: P3) — remaining

The 65 atomic commits reach `main` with their signatures, through a pull request.

**Why this priority**: nothing has been pushed; the work only matters once it is reviewable.

**Independent Test**: the pull request's checks are green and every commit is signed and atomic.

**Acceptance Scenarios**:

1. **Given** the branch, **When** the owner asks for a pull request, **Then** no fixup commits remain and `nix build .#memory-recall` and the flake check pass.
2. **Given** the pull request is approved, **When** it merges, **Then** it lands by rebase, not squash.

---

### User Story 7 - Skill descriptions that cost less context (Priority: P2) — to do

The listing of every skill's description is always in context (4,247 tokens for 39 skills) and is the largest recurring cost the hooks do not touch. Find a cheaper way to keep skills discoverable, for example shorter descriptions with the detail retrieved on demand, or a hook-built listing.

**Why this priority**: the skills hook only spares whole-file loads (ADR 0031); this is where the larger saving is.

**Independent Test**: measure tokens of the listing before and after, and rerun the skills comparison to check the right skill is still chosen at least as often (95%).

**Acceptance Scenarios**:

1. **Given** the current skills, **When** descriptions are slimmed or served another way, **Then** the always-loaded skill text is measurably smaller and the right-source rate does not fall.
2. **Given** a skill that retrieval cannot reach, **When** the description is the only route to it, **Then** the description still names what it is for.

---

### User Story 8 - Skills that scale past the description cap (Priority: P2) — to do

Claude Code caps the skill listing at 1% of the context window, and many more skills are planned. Skill summaries must be optimised so that adding skills does not push earlier ones out of the listing or inflate its cost.

**Why this priority**: without this, every new skill makes all of them less discoverable.

**Independent Test**: add synthetic skills until the listing reaches the cap and check that every skill is still reachable, by listing or by retrieval.

**Acceptance Scenarios**:

1. **Given** the listing at the cap, **When** another skill is added, **Then** no existing skill becomes undiscoverable.
2. **Given** 100 skills, **When** the always-loaded text is measured, **Then** it stays within the cap.

---

### User Story 9 - Fewer wrong memories injected (Priority: P2) — to do

At 0.74 about 3% of off-topic and 20% of adjacent prompts get an injection, and 84% of injections are right. Review whether the wrong injections can be reduced without making correct memories fail to inject.

**Why this priority**: a wrong whole memory costs about 1,000 tokens and misleads the model.

**Independent Test**: sweep alternatives (thresholds, a margin between the first and second score, per-kind floors) on the dev and held-out sets and on trial-log scores, comparing false injections against recall.

**Acceptance Scenarios**:

1. **Given** a candidate gate, **When** it is run on both query sets, **Then** false injections fall and recall of the right memory does not.
2. **Given** the trial log, **When** its best-score distribution is compared with the benchmark's, **Then** the gate is judged on real prompts too.

---

### Edge Cases

- A prompt with no matching memory still pays for any snippet that clears the floor (about 35 tokens per snippet, about 1,000 for a stray whole memory that reaches the higher threshold).
- Memory files whose bodies exceed the body cap are truncated when injected.
- The embedding cache is keyed by model, document format and dimensions; changing any of them must rebuild it, never reuse stale vectors.
- A memory added or edited after the last index run is not retrievable until the index runs again.
- A benchmark server on a loaded machine can answer in seconds instead of milliseconds; timing runs must pin CPUs.
- The thresholds are calibrated for one model at 256 dimensions over 83 memories; a different model or a much larger memory set needs recalibrating.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST rank memories and skill sections against a prompt using locally computed embeddings, with no external service and no model call per prompt.
- **FR-002**: The prompt hook MUST inject whole memories above a high confidence threshold and snippets above a lower floor, and nothing otherwise.
- **FR-003**: The hook MUST fail open: any error, timeout, missing server or short prompt injects nothing and never blocks the prompt.
- **FR-004**: The system MUST produce a names-only catalogue of memories and regenerate it on request, rewriting the file only when it changes.
- **FR-005**: The feature MUST be off by default behind a single option, and enabling it MUST require naming the memory directory.
- **FR-006**: The embedding model and the llama.cpp build it needs MUST be pinned and reproducible from the flake.
- **FR-007**: The comparison harness MUST score every system on a dev set and a held-out set, and MUST report retrieval time, facts in the retrieved text, facts in the answer, input tokens, cache reads, cache writes, output tokens, model time and dollars.
- **FR-008**: The harness MUST keep text that is the same on every call in the system block and per-query text in the user turn, and MUST continue one conversation for multi-call flows.
- **FR-009**: Results MUST be saved in the repository with the commands that reproduce them, and claims in documentation MUST match the saved numbers.
- **FR-010**: A skills hook MUST inject matching skill sections and obey the same fail-open rule (built: `skill-recall`).
- **FR-011**: When enabled, the hook MUST log score, injection kind and tokens added per prompt without storing prompt text (built: `--log`, `log-summary`).

### Key Entities

- **Memory**: a file with a name, a one-line description and a body, indexed as description plus body chunks.
- **Skill section**: a heading-delimited part of a skill file, indexed separately.
- **Vector cache**: stored embeddings per chunk, valid only for one model, document format and dimension count.
- **Query set**: questions with key facts and the memory expected to answer them; a dev set used to tune and a held-out set used to judge.
- **System (under test)**: one way of giving the model memory or skills, such as the default index, an always-read flow, or the catalogue plus injection.
- **Catalogue**: the names-only list that replaces the descriptive index.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the catalogue and injection, key facts reach the answer within 3 points of a model that always reads a file, on both query sets (met: 88 to 91% against 86 to 92%).
- **SC-002**: The always-loaded memory text is at least 75% smaller (met: about 3,900 to about 780 tokens).
- **SC-003**: Dollar cost per query is lower than both defaults on both sets (met: 33 to 40% lower, single runs).
- **SC-004**: Retrieval adds under 100 ms to a prompt (met: tens of milliseconds, measured as a real hook process).
- **SC-005**: Skill retrieval picks the right source at least as often as the default and costs at most a quarter as much per query (met in the benchmark: 95% and about a quarter; the hook's floor lowers recall to 70% for the right section in the top 3, see ADR 0031).
- **SC-006**: Over a trial of real prompts, the average tokens added per prompt stay under the average tokens the catalogue saves (not yet measured).
- **SC-007**: A third, untouched query set agrees with the held-out result to within 5 points (not yet run).

## Assumptions

- The owner is the only user; the module targets their NixOS desktop and home-manager setup.
- The benchmark's model of the default (a reader that opens files only when it asks to) is an emulation; the always-read default is the comparison that does not depend on it.
- Claude Code's own prompt and cache behaviour can change; cost results are single runs and carry up to $0.014 of run-to-run noise for the same system.
- `pkgs.llama-cpp-upstream` stays necessary until nixpkgs' llama.cpp supports the `gemma-embedding2` architecture.
- Asahi-related contributions and external publication are out of scope; this is the owner's own configuration work.

## Dependencies

- EmbeddingGemma 2 Q8_0 weights from Hugging Face (Kaggle needs credentials).
- A running local embedding server for the hook and for the benchmark drivers.
- ADR 0029 (embedding retrieval for memory and skills) and ADR 0030 (inject confident memories, use a catalogue).
