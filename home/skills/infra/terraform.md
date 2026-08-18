# Terraform

## Local operations

```
terraform init
terraform plan [-var-file=vars.tfvars]
terraform state list
terraform state show <resource>
terraform output [-json]
```

`terraform apply` mutates live infrastructure — **ask first**, and show the
plan output you are asking about. Never `-auto-approve` on someone's behalf.

## Registry lookup

```
curl -s "https://registry.terraform.io/v1/providers?q=<query>" \
  | jq '.providers[] | {name, description, version: .tag}'
curl -s "https://registry.terraform.io/v2/provider-docs?filter[provider-name]=<name>&filter[category]=resources" \
  | jq '.data[] | .attributes.title'
curl -s "https://registry.terraform.io/v1/modules?q=<query>" \
  | jq '.modules[] | {id, description, version}'
curl -s "https://registry.terraform.io/v1/modules/<ns>/<name>/<provider>" \
  | jq '{version, inputs: .root.inputs, outputs: .root.outputs}'
```

## Practice

- Read the plan before proposing it: a plan that destroys and recreates a
  stateful resource is a different conversation from an in-place update.
- State is the crown jewel. Never `state rm`/`import` without explicit
  agreement on what it will do.
- Provider and module versions are pinned; a version bump is its own commit.
