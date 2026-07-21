# Spec-Kit Setup for GitHub Copilot CLI

Spec-kit has been configured in your Nix setup to work with GitHub Copilot CLI.

## What was changed

1. **Added `spec-kit` package**: The `specify` CLI tool is now installed and available in your PATH
2. **Removed `cavekit` from opencode**: Cavekit was removed from the opencode (Copilot) configuration since cavekit is Claude Code-specific
3. **Cavekit remains in Claude Code**: Your claude-code setup still has cavekit installed

## How to use spec-kit with Copilot CLI

### First time setup (per project)

In any project where you want to use spec-kit:

```bash
cd /path/to/your/project
specify init . --integration copilot
```

This will create:
- `.specify/` directory with spec templates  
- `.github/copilot-instructions.md` with project context (optional)
- Agent files that Copilot CLI can use

### Using spec-kit commands in Copilot CLI

Once initialized, you can use spec-kit commands in `gh copilot`:

```bash
# Start Copilot CLI
gh copilot

# Use spec-kit commands (examples):
/speckit.constitution Create principles focused on code quality...
/speckit.specify Build an application that...
/speckit.plan The application uses...
/speckit.tasks
/speckit.implement
```

Or in non-interactive mode:

```bash
gh copilot -p "/speckit.specify Build a CLI tool for..." --allow-all-tools
```

### Available spec-kit commands

- `/speckit.constitution` - Define project principles and guidelines
- `/speckit.specify` - Create specifications (what to build)
- `/speckit.plan` - Create technical implementation plans (how to build)
- `/speckit.tasks` - Break down plans into tasks
- `/speckit.implement` - Execute implementation
- And more... (see [spec-kit docs](https://github.com/github/spec-kit))

### Verify installation

```bash
# Check specify CLI is installed
specify --version

# Check spec-kit integration
specify --help
```

## Updating spec-kit

Spec-kit is installed via Nix. To update:

1. Update the version/rev in `pkgs/spec-kit/default.nix`
2. Update the hash
3. Run `home-manager switch`

## Documentation

- [Spec-Kit GitHub](https://github.com/github/spec-kit)
- [Spec-Kit Documentation](https://github.github.io/spec-kit/)
- [Copilot CLI Docs](https://docs.github.com/copilot/how-tos/copilot-cli)

## Troubleshooting

If `/speckit.*` commands aren't available in Copilot CLI:

1. Make sure you ran `specify init . --integration copilot` in your project
2. Restart `gh copilot` session
3. Check that agent files were created in `.github/` or your integration directory
