# Postmortems

Full postmortem practice: reconstructing what happened, writing it up
blamelessly, and tracking the resulting action items. Paging rotations
and live incident comms stay out of scope — this file starts once the
incident is over and the question becomes "what happened and what do we
do about it."

## Reconstruction is investigation, applied after the fact, for the whole incident

`investigation.md`'s method — symptom-first triage, correlating across
signals, distrusting the dashboard — applies here too, but for the
entire incident window rather than one symptom. Build the full timeline
by pulling the same correlation thread (trace ID → traces → logs)
across the whole window, not just the first anomaly found — an incident
with one root cause commonly has multiple visible symptoms across
different services, and a postmortem that stops at the first one found
produces an incomplete or wrong root cause.

`investigation.md`'s "distrust the dashboard" checks apply retroactively
too: a metric that looked fine during the incident because its query
was scoped wrong or its time range defaulted somewhere unhelpful needs
re-checking with the benefit of hindsight, not trusted just because
nobody caught the problem with it at the time.

## Blameless means explaining what made sense at the time, not who to fault

A postmortem that names an individual as the cause has usually stopped
one level too shallow. "Engineer X pushed a bad config" is an
observation, not a root cause — the root cause is whatever let a bad
config reach production undetected: missing validation, missing staging
parity, missing alert on the exact signal that would have caught it
(which is itself a `coverage.md`-style gap worth naming explicitly in
the postmortem's follow-up items).

## Action items are gap-closing, and they route to the file that owns the gap

A missing instrumentation signal found while reconstructing the
timeline routes to `programming/observability.md` (write the
instrumentation) via `improving.md`'s "closing gaps" section; a missing
alert or monitoring coverage routes to `coverage.md` or `improving.md`'s
alert-design section. The postmortem's job is to *find and route* the
gap, not to re-derive how to fix it — this file does not duplicate
either of those files' content.

## A postmortem with no unresolved action items is a red flag

If reconstructing an incident revealed nothing worth fixing, either the
reconstruction stopped too early or the incident really was pure bad
luck with no systemic contributor — the latter is rare enough that it
deserves stating explicitly rather than silently assumed.
