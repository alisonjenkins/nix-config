# Kubernetes

Read freely. **Ask before mutating**: this is live infrastructure, and the
declarative source of truth is the GitOps repo, not the cluster.

## Inspect

```
kubectl get pods|deployments|services|nodes [-n ns] [-o wide|json|yaml]
kubectl describe pod|deployment|service <name> [-n ns]
kubectl logs <pod> [-n ns] [-c container] [--tail=100] [-f]
kubectl get events [-n ns] --sort-by='.lastTimestamp'
kubectl top pods|nodes [-n ns]
kubectl get pods --field-selector=status.phase!=Running [-n ns]
```

## Context

```
kubectl config get-contexts
kubectl config use-context <name>
kubectl get namespaces
```

Check which context is active before every command that could mutate. The
wrong context is the most common way to damage the wrong cluster.

## Mutate (ask first)

```
kubectl apply -f <file.yaml>
kubectl rollout status deployment/<name> [-n ns]
kubectl rollout restart deployment/<name> [-n ns]
kubectl exec -it <pod> [-n ns] -- <command>
```

## When the controller is the problem

A reconciler can deadlock itself: its own safety precondition blocks the
remediation it is waiting to perform. Recovery: do the automated step manually
once, then fix the precondition so it cannot recur.

Client and server halves of a tool are versioned separately. Skew can fail
while reporting success, silently dropping work. Pin both sides to a matched
pair rather than tracking either at latest.

On a GitOps-managed cluster a `kubectl` fix is lost on the next reconcile.
Land it in the repo; use direct apply only to test a hypothesis, and say so.
