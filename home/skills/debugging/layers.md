# Choosing where to measure

Most stubborn faults are a mismatch between where the problem is and where you
are looking. Measure at the layer closest to the real resource.

## Across a virtualisation or container boundary

Host-reported statistics about a guest are frequently meaningless, especially
where memory is pinned, pre-allocated, or passed through. The host reports what
it handed over, not what is being used. **Measure inside the guest.**

## Across a network filesystem

The client's view is assembled from caches. Attribute caches, lookup caches and
negative caches all keep answering after the server-side object is gone or has
changed identity. Probe from the side that owns the data, or defeat the cache
explicitly.

## Across a userspace/hardware boundary

An application-level graph can show every node correctly wired while the
hardware state machine underneath is stuck: a device in a suspended power
state, a link down, a queue frozen. The software view is describing its own
intent, not the hardware's state. Read the hardware's own state.

## Across a supervisor boundary

A supervisor reports whether its contract is met, not whether the work is
happening. Ask the workload directly.

## Practical rule

Write down the chain from your probe to the resource. Every hop in that chain
is somewhere the truth can be replaced with a cached, summarised, or intended
value. The fewer hops, the better the evidence.
