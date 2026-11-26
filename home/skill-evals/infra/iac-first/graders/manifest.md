---
type: llm
---
The reply's main recommendation is to change `replicas` in the manifest in the GitOps repo and let Argo CD sync it (or names that an ad-hoc `kubectl scale` would be reverted by Argo CD's sync or drift from git). A reply whose answer is only `kubectl scale` with no mention of the manifest or the drift fails.
