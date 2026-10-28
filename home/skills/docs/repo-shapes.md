# Docs by repo shape

## Default

A single-project repo is the default. Add structure when a second unit appears, not before.

| Shape | Root README | Per-unit docs | Changelog | Ownership | Agent files |
|---|---|---|---|---|---|
| Single repo | Purpose, setup, links to docs/ | None | One CHANGELOG.md at the root | CODEOWNERS optional | One AGENTS.md or CLAUDE.md only if agents need more than the README |
| Monorepo | Links to one package index | A short README in every publishable package | Per package where versions are independent | CODEOWNERS entry per package | Root file for shared rules, nested file per package |
| Polyrepo | What the repo is and where the org index lives | None | Per repo | Per repo | Org-wide defaults in a .github repo |

## Monorepo

- Put a README in each publishable package directory. npm shows the README at the package root; crates.io reads the manifest's readme field relative to that package's Cargo.toml [npm docs, Cargo manifest docs]. Google: "All top-level directories for a code package should have an up-to-date README.md file." [Google docguide READMEs].

- With Cargo workspaces, [workspace.package] can share readme, documentation and repository, but readme and license-file resolve relative to the workspace root, not the member [Cargo workspaces docs].

- Keep one package index and link to it from the root README. Babel's packages/README.md lists every package with links and its root README links to it once. Of six monorepos checked on 2026-10-28 only Babel does this; the others point to a docs site or list crates in a changelog section. Treat it as an observed pattern, not a standard.

- Shared docs (contributing, architecture, conventions) live once at the root or in docs/ and packages link to them. Copying them into each package is a judgement against, not a sourced rule.

- Ownership: a CODEOWNERS entry per package directory. A pattern covers its subdirectories ("any of its subdirectories"), so a package directory with no later matching line keeps the owner of the pattern above it; write-access approval is the fallback only when an explicit ownerless line (for example /apps/github after /apps/ @octocat) overrides it. Last matching pattern wins; file location order is .github/, root, docs/ and the first found is used [GitHub CODEOWNERS docs].

- Agent files: nested AGENTS.md files work nearest-wins [agents.md]. Claude Code loads subdirectory CLAUDE.md files on demand when it reads a file there, and claudeMdExcludes skips packages you never touch; starting a session from the package directory scopes it [Claude Code memory and large-codebases docs]. Keep shared rules in the root file.

- Releases: release-please manifest mode lists each package in release-please-config.json, the changelog path is "relative to the package directory", defaults to CHANGELOG.md, and records versions in .release-please-manifest.json [release-please manifest]. With Lerna `lerna version --conventional-commits`, each updated package gets CHANGELOG.md in its own directory; fixed mode also writes a root CHANGELOG.md, while independent mode writes per-package files only (`--no-changelog` turns it off) [Lerna version and publish]. Changesets writes one CHANGELOG.md per package directory and no root file (`changelogPath = path.resolve(dir, "CHANGELOG.md")` for each released package).

- A docs site over many packages: the MkDocs monorepo plugin pulls sub-project mkdocs.yml files in with !include if present; Docusaurus supports multiple docs instances, and its docs suggest two separate sites for very large sets because a change rebuilds everything; Sphinx intersphinx links projects through objects.inv inventories, cached for 5 days by default.

- Relative links in a package README break on registries that render it away from the repo. crates.io resolves relative README links against the `repository` field when it points to github.com, gitlab.com or bitbucket.org (media like svg, png, jpg, jpeg, gif, mp4, webm, ogg, webp resolve to raw/HEAD, other links to blob/HEAD; AVIF is not supported). npm and PyPI show no relative-link handling in docs or source, so use absolute URLs for any README published there.

## Single repo

A single repo has a root README that states purpose and setup and links to docs/. Put CONTRIBUTING.md and one CHANGELOG.md at the root.

Add AGENTS.md or CLAUDE.md only when agents need instructions the README does not give. See structure.md for the docs/ tree.

## Polyrepo

- Org-wide community health files go in a public repo named .github; defaults apply to repositories "owned by the account" that lack their own file, with precedence .github/ folder, root, then docs/; default license files cannot be provided this way [GitHub docs].

- The kubernetes and rust-lang .github repos hold only community health files and do not index the org's repos (observed).

- Give each repo a catalog-info.yaml next to the docs source (mkdocs.yml is a sibling of catalog-info.yaml) so a Backstage catalog can list owners and docs; the techdocs annotation backstage.io/techdocs-ref: dir:. sits in each entity's catalog-info.yaml and points at the docs source folder (dir:./sub-folder for a subfolder) [Backstage TechDocs how-to guides].

- Link across repos with published docs URLs or commit-pinned permalinks; branch URLs drift.

- Relative links across repos are not verified by any source.

- Give each shared doc one owning repo and link to it.

- Turborepo's docs say drift is the default in a polyrepo, so add a link check in CI if present.

## Anti-patterns

| Pattern | Fix |
|---|---|
| Root README repeating every package README | Link to one package index |
| Packages with no README | Add a short one in each publishable package |
| Shared docs copied into each package | Link to the one copy |
| Relative links in a published README | Absolute URLs |
| One wiki shared by many repos | A docs site or one owning repo, with links |

## Sources and confidence

| Source | URL |
|---|---|
| npm package README docs | https://docs.npmjs.com/about-package-readme-files |
| Cargo manifest | https://doc.rust-lang.org/cargo/reference/manifest.html |
| Cargo workspaces | https://doc.rust-lang.org/cargo/reference/workspaces.html |
| Google docguide READMEs | https://google.github.io/styleguide/docguide/READMEs.html |
| GitHub CODEOWNERS | https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners |
| agents.md | https://agents.md/ |
| Claude Code memory | https://code.claude.com/docs/en/memory |
| Claude Code large codebases | https://code.claude.com/docs/en/large-codebases |
| release-please manifest | https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md |
| Lerna version and publish | https://lerna.js.org/docs/features/version-and-publish |
| mkdocs-monorepo-plugin | https://github.com/backstage/mkdocs-monorepo-plugin |
| Docusaurus multi-instance | https://docusaurus.io/docs/docs-multi-instance |
| Sphinx intersphinx | https://www.sphinx-doc.org/en/master/usage/extensions/intersphinx.html |
| GitHub default community health file | https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file |
| Backstage software catalog | https://backstage.io/docs/features/software-catalog/ |
| Backstage TechDocs how-to guides | https://backstage.io/docs/features/techdocs/how-to-guides |
| Turborepo | https://turborepo.dev/docs/crafting-your-repository |

Confidence: checked by running the tool or reading source on 2026-10-28. Remaining unverified: PyPI and npm relative-link handling (nothing found; PyPI search was partial); Nx, Bazel, Pants, Microsoft/Atlassian monorepo pages and semantic-release's monorepo plugin not fetched; no source covers a central docs repo.
