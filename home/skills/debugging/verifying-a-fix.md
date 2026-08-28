# Verifying a fix

The symptom disappearing is weak evidence. Symptoms disappear for many reasons,
including reasons that will bring them back.

## Verify in the environment the user actually uses

A fix that sets or defaults an environment variable must be checked in a shell
that matches how the program is really launched, not the agent's shell, and
not a test run that happens to clear the variable.

- If the login session already exports the variable, a "set default" mechanism
  is a **no-op**. Check `echo $VAR` in a plain login shell before believing it.
  A default only applies where nothing has set the value already; overriding
  needs an explicit override, not a default.
- Beware **single-instance applications**. Launching one while an old instance
  is running hands off to that old, unfixed process, and you will observe and
  log the old behaviour. Fully exit it first.

## Verify the setting reached the right process

Environment variables placed before a wrapper command are inherited by the
*wrapper*, not the program you meant. Placement relative to the command
separator decides which process gets them.

Inspect the target process's actual environment (`/proc/<pid>/environ`) rather
than inferring from behaviour.

## Positive control

Before concluding "the setting has no effect", prove your observation method
can detect the effect at all. A test that cannot see success is not evidence of
failure.

## State the evidence

Report what you ran and what it printed. "Should work now" is not a result. If
a check was skipped, say which and why: see
`superpowers:verification-before-completion`.
