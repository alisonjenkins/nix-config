# Repo documentation structure

## Default shape

```text
README.md                   # Index plus links to docs/
LICENSE
CONTRIBUTING.md
SECURITY.md
CODE_OF_CONDUCT.md          # Optional
CHANGELOG.md                # Keep a Changelog, Unreleased on top
ARCHITECTURE.md             # Only above about 10k lines of code
AGENTS.md                   # Only if agents work in the repo
.github/
  CODEOWNERS
  ISSUE_TEMPLATE/
  PULL_REQUEST_TEMPLATE.md
docs/
  README.md                 # Index of every page
  tutorials/
  how-to/
  reference/
  explanation/
  decisions/                # ADRs, NNNN-title.md
  runbooks/                 # Operations, infrastructure repos
```

Grow the tree, do not scaffold it. Diataxis says "Use Diátaxis as a guide, not a plan", "It certainly does not mean that you should create empty structures for tutorials/howto guides/reference/explanation with nothing in them." and "Good structure develops from within."
Start with a README and add a folder when the second page of a type appears.

## Root, .github and docs

GitHub recognises CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, SUPPORT, and ACCESSIBILITY in the root, .github/ or docs/, with precedence .github/ then root then docs/; defaults from a .github repo apply to repos "owned by the account" that lack their own file. FUNDING.yml and vulnerability report templates are .github/ only; issue and PR templates live under .github/.

CODEOWNERS may live in .github/, root or docs/; the first file found is used and the last matching pattern wins. GitHub finds the README in the same order (.github, root, docs) and shows only the first.

## Keep docs with the code

Keep docs in the same repo and update them in the same PR as the code. Google advises updating docs in the same change: "A small set of fresh and accurate docs is better than a large assembly of "documentation" in various states of disrepair." (best_practices.html), "First delete what you're certain is wrong, ignore what's unclear." (best_practices.html), and notes that "Docs thrive when they're treated like tests: a necessary chore one learns to savor because it rewards over time." (philosophy.html).

Write the Docs advises keeping sources near the code, avoiding overlap between sources, and warns to "Treat incorrect docs as worse than missing docs". Do not use the GitHub wiki as the primary store: it sits outside the code review flow, and GitHub's wiki page does not mention PR review. Start with Markdown in the repo; add a site generator such as MkDocs only when readers need search or versions.

## Organise by reader need

The Diataxis four types (tutorials for learning by doing, how-to guides for a task, reference for lookup, explanation for understanding) "require four different approaches", and Divio is the origin of the model. Map them to folders only when each has content.

Add a README per directory as recommended by Google: "All top-level directories for a code package should have an up-to-date README.md file." State what the directory is for, which files to read first, and who maintains it.

## Decision records

Record one decision per file. Follow the Nygard format: title, context, decision ("We will ..."), status, and consequences. Numbers are never reused; keep and mark a superseded record rather than deleting it.

MADR adds considered options and statuses proposed, rejected, accepted, deprecated, superseded-by, with files named NNNN-title-with-dashes.md under docs/decisions/. If the repo already has an ADR folder (for example docs/adr/), keep using it; use docs/decisions/ only in a new repo. Link an ADR from the doc or code that depends on it instead of copying the reasoning.

## Architecture overview

ARCHITECTURE.md (matklad) suits roughly 10k to 200k lines of code: an overview, a codemap that answers "where is the thing that does X", invariants (especially what is deliberately absent), layer boundaries, and cross-cutting concerns. Keep it short, name entities instead of linking files or symbols because links go stale, and review it a few times a year.

For diagrams use the C4 levels (system context, container, component, code). The C4 checklist asks for a title, a key or legend, and a label on every arrow.

## Changelog and releases

Follow Keep a Changelog 1.1.0: use CHANGELOG.md, put the latest version first, keep an Unreleased section on top, and write change types Added, Changed, Deprecated, Removed, Fixed, Security for end users.

Conventional Commits can drive versions (fix is PATCH, feat is MINOR, a breaking change is MAJOR); other types such as docs and chore "have no implicit effect in Semantic Versioning (unless they include a BREAKING CHANGE)". GitHub Releases attach notes to git tags; "Automatically generated release notes include a list of merged pull requests", and categories come from a release.yml in the .github directory with PR labels per category.

## Generated reference

Keep generated output (rustdoc, godoc, typedoc, terraform-docs tables) out of hand-written folders; build it in CI or link to the published copy. This is a convention, not a sourced rule. See infrastructure.md and code.md for per-tool detail if those files exist.

## Ownership and checks

Add a CODEOWNERS entry for docs/. A link check gates PRs: lychee-action's "fail" input defaults to false, so set it to true to fail the job if present. No published convention exists for "last reviewed" front matter; the nearest cadence is matklad's "a few times a year".

## Anti-patterns

| Pattern | Fix | Source |
|---|---|---|
| Stale docs left in place | Delete or fix in the same change | Google |
| Sprawl and duplicated content | One owner per fact, link to it | Write the Docs |
| Docs only in the wiki | Move into the repo | GitHub wiki page (review not mentioned) |
| Empty Diataxis sections | Add a folder when it has a page | Diataxis |
| Links to files or symbols that go stale | Name the entity | matklad |
| Orphan pages | Link every page from docs/README.md | observed: every exemplar has an index, no source states a rule |
| Deep nesting | none | not sourced, keep two levels unless a reader would get lost |

## Exemplars

| Repo | Shape | What works |
|---|---|---|
| nixpkgs | doc/ topic folders, navigation file controls the index | Root policy files |
| cli/cli | Flat docs/ | README index |
| kubernetes/community | Per-SIG folders | README index, OWNERS per directory |
| tokio | Root policy files | A CHANGELOG per crate next to the code it describes |
| rust-lang/rust | Long books are separate repos | Pulled in as submodules |

Observed from GitHub listings on 2026-10-28.

## Sources and confidence

| Source | URL | Used for |
|---|---|---|
| GitHub community health files | https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file | Community health file locations and precedence |
| GitHub CODEOWNERS | https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners | File locations and matching rules |
| GitHub wikis | https://docs.github.com/en/communities/documenting-your-project-with-wikis/about-wikis | Wiki capabilities and review limits |
| Google docguide best practices | https://google.github.io/styleguide/docguide/best_practices.html | Doc freshness and directory READMEs |
| Google docguide READMEs | https://google.github.io/styleguide/docguide/READMEs.html | Directory README requirement |
| Google docguide philosophy | https://google.github.io/styleguide/docguide/philosophy.html | Docs like tests and deleting incorrect docs |
| Write the Docs principles | https://www.writethedocs.org/guide/writing/docs-principles/ | Keeping sources near code and avoiding overlap |
| Diataxis | https://diataxis.fr/ | Four documentation types and emergent structure |
| Diataxis how to use | https://diataxis.fr/how-to-use-diataxis/ | Emergent structure and anti-scaffolding |
| Divio | https://docs.divio.com/documentation-system/ | Origin of the four documentation types |
| Nygard ADRs | https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions | Architecture decision record format |
| MADR | https://adr.github.io/madr/ | Extended ADR format and file naming |
| matklad ARCHITECTURE.md | https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html | Architecture guide scope, codemap, and review cadence |
| C4 checklist | https://c4model.com/diagrams/checklist | Diagram levels and checklist requirements |
| Keep a Changelog | https://keepachangelog.com/en/1.1.0/ | Changelog structure and change types |
| Conventional Commits | https://www.conventionalcommits.org/en/v1.0.0/ | Commit types and SemVer mapping |
| GitHub automatically generated release notes | https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes | Release notes from pull requests and categories |
| lychee-action | https://github.com/lycheeverse/lychee-action | Dead link checking in CI |

Confidence: researched 2026-10-28, claims re-checked against primary pages 2026-10-28; nesting depth, orphan-page rule (no source), freshness metadata convention, arc42/Docusaurus/Sphinx/mdBook guidance not fetched.
