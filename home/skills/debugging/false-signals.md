# Signals that lie

Each of these has reported "fine" while the system was broken. When one of
them is your only evidence, go and get better evidence.

## Process and service state

- **A clean exit is not a healthy exit.** A service can crash-loop while
  logging status 0 and no error. Look for a stale lockfile or single-instance
  guard left by an unclean shutdown, which makes each new start abort quietly.
- **"No failed units" is not health.** Restart limits and rate-limiting can
  suppress the failed state entirely, so a service flapping every few seconds
  shows green. Check restart counts and timestamps, not just active state.
- **A unit being active is not the workload working.** Active means the
  supervisor is satisfied, nothing more.

## Network

- **A handshake succeeding does not mean the protocol works.** A connection
  upgrade or accept can complete and then carry no data at all. Prove frames
  or bytes actually flow end to end.
- **L2 reachability is not L3/L4 reachability.** ARP resolving proves nothing
  about whether traffic is passing; a stateful firewall or killswitch can drop
  everything after ARP succeeds. Test with the protocol you actually care
  about, not `ping`.

## Storage and mounts

- **A subpath resolving does not mean the mount is alive.** Cached lookups and
  adjacent paths keep answering while the root of the mount is broken. Pick a
  probe that hits the specific broken object directly.
- **Client-side attribute caching hides server-side truth.** If a check reads
  through a cache, it is reporting the cache's state, not the resource's.

## Configuration

- **A parser can reject one value and silently discard the whole section.**
  The only evidence may be a single terse log line. After any config change,
  grep the daemon's log for its rejection message rather than concluding it
  worked because nothing else errored.
- **A flag's name is not its behaviour.** A flag can encode an assumption from
  a different topology and do nothing, or the exact opposite of what it says.
  Verify the effect, not the intent.

## The general form

If the signal you are trusting is produced by something *other than* the thing
that is broken, it is not evidence. Find the probe that touches the broken
object itself.
