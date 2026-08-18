# AWS

## Credentials

Credentials come from `aws-vault`. Prefix the command rather than exporting a
session, and be aware that a bare `aws-vault exec` may be intercepted and
backgrounded — use the `AWS_VAULT=` prefix form when driving it from a script
or agent session.

Always confirm which account and region a command will hit before running it.

## Reading

```
aws sts get-caller-identity
aws <service> describe-* / list-* / get-*   --output json
```

Read-only calls are fine unprompted. Anything that creates, modifies, or
deletes a resource — or that costs money — needs the user's agreement first,
and belongs in the Terraform repo rather than the CLI.

## Debugging access denials

An `AccessDenied` is answered by evidence, not guesswork: find the actual call
in CloudTrail, then read the identity's attached policies and the resource
policy, and the trust policy if the failure is on `sts:AssumeRole` or
`AssumeRoleWithWebIdentity` (the usual shape for GitHub OIDC in CI).

## Cost

Provisioning large instances, GPU capacity, or anything without a cost control
is a decision for the user, not a default.
