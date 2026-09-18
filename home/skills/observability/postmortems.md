# Postmortems

Reconstructing what happened, writing it up blamelessly, and tracking
action items. Paging rotations and live incident comms are out of
scope; this file starts once the incident is over and the question is
"what happened and what do we do about it."

## Reconstruction is investigation, applied after the fact, for the whole incident

`investigation.md`'s method (symptom-first triage, correlating across
signals, distrusting the dashboard) applies to the whole incident
window rather than one symptom. Build the full timeline by pulling the
correlation thread (trace ID → traces → logs) across the window, not
just to the first anomaly. One root cause commonly shows multiple
symptoms across services; stopping at the first produces an incomplete
or wrong root cause.

The "distrust the dashboard" checks apply retroactively: a metric that
looked fine during the incident because its query was scoped wrong or
its time range defaulted badly needs re-checking in hindsight, not
trusting because nobody caught it at the time.

## Blameless means explaining what made sense at the time, not who to fault

A postmortem that names an individual as the cause has stopped one
level too shallow. "Engineer X pushed a bad config" is an observation;
the root cause is whatever let a bad config reach production
undetected: missing validation, missing staging parity, a missing alert
on the signal that would have caught it (a `coverage.md`-style gap to
name in the follow-up items).

## Action items are gap-closing, and they route to the file that owns the gap

A missing instrumentation signal routes to
`programming/observability.md` via `improving.md`'s "closing gaps"
section; missing alert or monitoring coverage routes to `coverage.md`
or `improving.md`'s alert-design section. The postmortem *finds and
routes* the gap; it does not re-derive the fix.

## A postmortem with no unresolved action items is a red flag

If reconstruction revealed nothing worth fixing, either it stopped too
early or the incident really was pure bad luck with no systemic
contributor. The latter is rare enough to state explicitly, not assume
silently.
