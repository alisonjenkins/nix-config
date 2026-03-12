# Rust Unikernel Template

A Rust project template for building unikernels with [NanoVMs/ops](https://ops.city/) and deploying to AWS as AMIs.

## Quick Start

```bash
# Enter the development shell
nix develop

# Build the static binary
just build

# Run locally (Linux only)
just ops-run

# Create AWS AMI (requires AWS credentials)
just ami-create
```

## Prerequisites

### Local Development

- Nix with flakes enabled
- Linux for local unikernel testing (ops doesn't support macOS)
- macOS developers can build binaries but need CI for AMI creation

### AWS Deployment

#### 1. S3 Bucket

Create an S3 bucket for temporary image uploads:

```bash
aws s3 mb s3://my-unikernel-images --region eu-west-2
```

Update `ops-config.json` with your bucket name:

```json
{
  "CloudConfig": {
    "BucketName": "my-unikernel-images"
  }
}
```

#### 2. IAM Role for GitHub Actions

Create an IAM role with the following trust policy for GitHub OIDC:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

Attach this policy to the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage",
        "ec2:DeregisterImage",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DeleteSnapshot",
        "ec2:ImportSnapshot",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:DescribeImportSnapshotTasks"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-unikernel-images",
        "arn:aws:s3:::my-unikernel-images/*"
      ]
    }
  ]
}
```

#### 3. GitHub OIDC Provider

If you haven't already, create the GitHub OIDC provider in your AWS account:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### 4. Repository Variables

Configure these variables in your GitHub repository settings:

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC | `arn:aws:iam::123456789:role/github-actions` |
| `AWS_REGION` | AWS region for deployment | `eu-west-2` |
| `S3_BUCKET` | S3 bucket for image uploads | `my-unikernel-images` |

## Available Commands

### Development

| Command | Description |
|---------|-------------|
| `just build` | Build static binary with Nix |
| `just check` | Run all checks (clippy, fmt, tests) |
| `just test` | Run tests with cargo-nextest |
| `just fmt` | Format code |
| `just lint` | Run clippy lints |
| `just watch` | Watch for changes and rebuild |

### Local Unikernel (Linux only)

| Command | Description |
|---------|-------------|
| `just ops-build` | Build unikernel image |
| `just ops-run` | Run in QEMU |
| `just ops-run-debug` | Run with debug output |

### AWS AMI

| Command | Description |
|---------|-------------|
| `just ami-create [name]` | Create AMI from binary |
| `just ami-list` | List AMIs in region |
| `just ami-delete <name>` | Delete an AMI |

### AWS Instances

| Command | Description |
|---------|-------------|
| `just instance-create <image>` | Launch EC2 instance |
| `just instance-list` | List running instances |
| `just instance-logs <name>` | Get instance logs |
| `just instance-delete <name>` | Terminate instance |

## Configuration

### ops-config.json

The `ops-config.json` file controls unikernel settings:

```json
{
  "CloudConfig": {
    "Platform": "aws",
    "Zone": "eu-west-2a",
    "BucketName": "my-unikernel-images",
    "Flavor": "t3.micro"
  },
  "RunConfig": {
    "Ports": ["8080"],
    "Memory": "512m"
  },
  "Env": {
    "RUST_LOG": "info"
  }
}
```

See the [ops documentation](https://docs.ops.city/) for all available options.

## CI/CD Pipeline

The GitHub Actions workflow:

1. **test**: Runs `nix flake check` on all PRs
2. **build-ami**: Creates an AMI on main branch merges
3. **deploy-instance**: Optionally deploys an instance (workflow_dispatch)

AMI names follow the pattern: `my-crate-<commit-sha>`

## Troubleshooting

### "ops: command not found" on macOS

ops only supports Linux. Use CI for AMI creation or run in a Linux VM.

### AMI creation fails with permissions error

Ensure your IAM role has the required EC2 and S3 permissions listed above.

### Instance not accessible

1. Check security group allows inbound traffic on port 8080
2. Check instance logs: `just instance-logs <name>`
3. Verify the AMI was created successfully: `just ami-list`

### Binary too large

Ensure release profile optimizations are enabled in `Cargo.toml`:

```toml
[profile.release]
lto = true
codegen-units = 1
strip = true
```
