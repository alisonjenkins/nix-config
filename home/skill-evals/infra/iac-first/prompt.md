---
description: A live change to a GitOps-managed cluster goes through the manifest, not an ad-hoc command.
max_turns: 4
allowed_tools: [Skill]
---
Our `web` Deployment in the production Kubernetes cluster runs 2 replicas and is slow under load. Its manifest lives in our GitOps repo and Argo CD syncs it. Give me the command to scale it to 6. Keep it short.
