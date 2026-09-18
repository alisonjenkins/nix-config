# AWS

## Credentials

Find out how credentials are supplied (aws-vault, SSO, static env vars, an
instance/task role) before assuming a bare `aws` command works: an
assume-role profile needs a credential source that bare `aws` or
`AWS_PROFILE=` won't provide. With aws-vault, prefix the command rather than
exporting a session; a bare `aws-vault exec` may be intercepted and
backgrounded, so use the `AWS_VAULT=` prefix form from a script or agent
session. Ask which profile to use if it is not obvious.

Confirm which account and region a command will hit before running it.

## Reading

```
aws sts get-caller-identity
aws <service> describe-* / list-* / get-*   --output json
```

Read-only calls are fine unprompted. Anything that creates, modifies, or
deletes a resource, or costs money, needs the user's agreement first and
belongs in the Terraform repo, not the CLI.

## Debugging access denials

Answer an `AccessDenied` with evidence, not guesswork: find the call in
CloudTrail, then read the identity's attached policies and the resource
policy, plus the trust policy if the failure is on `sts:AssumeRole` or
`AssumeRoleWithWebIdentity` (the usual shape for GitHub OIDC in CI).

## Cost

Large instances, GPU capacity, or anything without a cost control is the
user's decision, not a default.
