# Security while coding

Not a substitute for a threat model. These are the habits that belong in
ordinary code, applied by default rather than in a dedicated security pass.

## Minimise the attack surface

Every entry point, every dependency, every enabled feature and every open port
is surface. The most reliable security work is deleting things.

- Complexity is surface. Code nobody can fully read is code whose behaviour
  under hostile input nobody can predict.
- Debug endpoints, verbose error pages, and "temporary" bypasses reach
  production. Do not write them without a removal plan.
- An unused dependency is pure surface with no benefit. Remove it.

## Least privilege

Grant the narrowest permission that works, for the shortest time that works.
A process, a token, a database user, a service account, a container: each gets
what it needs for its job and nothing for anyone else's. Escalating later is
cheap; discovering that everything ran as root is not.

## Validate at the boundary

Anything that crossed a process boundary is untrusted, without exception:
request bodies, query parameters, environment variables, file contents,
responses from other services, and anything a previous version of your own code
wrote to disk.

- Validate on the way **in**, once, at the edge, and convert to a type that
  carries the guarantee. Then internal code does not re-check and does not
  forget to.
- Prefer allow-lists to deny-lists. You can enumerate what is valid; you cannot
  enumerate what is malicious.
- Never build a query, a command line, a path, or markup by string
  concatenation with untrusted data. Use the parameterised form the library
  offers, every single time, including "just this once for a script".

## Secrets

Never in source, never in a log line, never in an error message returned to a
caller. Read them from the environment or a secret store at the point of use.
Where the repository already has a mechanism for this, use that one rather than
inventing a second.

## Apply security patches quickly

A known vulnerability in a pinned dependency is a finding, not a footnote. When
a lockfile update is available for one, say so plainly and treat it as work,
not as noise to be deferred indefinitely.

The counterpart: do not pin a dependency to a version you have not checked, and
do not silently bump one past a major boundary while doing something else.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt), tips 72-73. Full tip list: https://pragprog.com/tips/
