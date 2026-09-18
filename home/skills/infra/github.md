# GitHub CLI

`gh` is already authenticated. Prefer `--json field1,field2` for anything you
will parse.

## Issues

```
gh issue list [--repo owner/repo] [--state open|closed] [--label bug] [--json number,title,state]
gh issue view <number> [--json title,body,comments]
gh issue create --title "..." --body "..."
gh issue comment <number> --body "..."
gh search issues "query" [--repo owner/repo] [--json number,title,repository]
```

## Pull requests

```
gh pr list [--state open|merged|closed] [--json number,title,state]
gh pr view <number> [--json title,body,reviews,mergeable,statusCheckRollup]
gh pr create --title "..." --body "..." [--base main]
gh pr diff <number>
gh pr checks <number>
gh pr review <number> --approve|--comment|--request-changes --body "..."
gh pr merge <number> --rebase
```

Merge strategy is not a free choice; see the `git` skill. Never `--squash`.

## Search and API

```
gh search code "query" [--repo owner/repo] [--language nix]
gh search repos "query" [--language nix] [--json fullName,description]
gh search commits "query" [--repo owner/repo]
gh repo view [owner/repo] [--json name,description,defaultBranchRef]
gh release list|view <tag> [--repo owner/repo]
gh api repos/{owner}/{repo}/... [--jq '.field']
gh api graphql -f query='...'
```

Delegate a run of five or more same-shape `gh`/GraphQL calls to a background
sub-agent rather than grinding them in the main loop.
