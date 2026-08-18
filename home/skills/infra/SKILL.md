---
name: infra
description: Infrastructure and operations — the infrastructure-as-code-first rule, when direct mutation of live systems is allowed and when to ask, and per-tool guidance for Nix deployment, Kubernetes, Terraform, AWS, and the GitHub CLI. Use when deploying, changing cluster or cloud state, debugging a running service, or reaching for kubectl, terraform, aws, gh, or deploy-rs.
---

# Infrastructure

## The rule

**Infrastructure as code first.** Propose the change in the IaC repo and let
CI/CD apply it. Mutating live infrastructure directly — cloud consoles, ad-hoc
`kubectl edit`, `aws` writes — is sometimes acceptable for personal infra, but
**always ask the user for permission first**. Never mutate live infra
unprompted.

Reading live state is always fine and is usually the right first step: check
what is actually deployed before proposing a change to what should be.

## Working rules

- **Idempotence.** Check current state before mutating. Every operation should
  be safe to re-run.
- **Retry transient failures** with backoff before giving up. When a subtask is
  genuinely unrecoverable, deliver the rest and report the gap explicitly.
- Timestamps in reports and logs are ISO8601 UTC.
- Prefer machine-and-human-readable output (`--json`, `-o json`, markdown
  tables) over free-form dumps.
- Resolve tools through the devshell or `nix-shell` rather than assuming they
  are on `PATH`.

## Routing

| Working with | Read |
|---|---|
| This flake: build, switch, deploy-rs, remote hosts | [nix.md](nix.md) |
| Clusters, pods, workload debugging | [kubernetes.md](kubernetes.md) |
| Providers, modules, plan/apply | [terraform.md](terraform.md) |
| Accounts, credentials, cloud resources | [aws.md](aws.md) |
| Issues, PRs, releases, repo and code search | [github.md](github.md) |
