# Documenting code

## Where each kind lives

| Kind | Home |
|---|---|
| Why a line exists | Inline comment next to it |
| What a public API does | Doc comment on the item |
| How to use a module | Module-level doc plus a runnable example |
| Why a design was chosen | An ADR (see [structure.md](structure.md)) |
| Setup and tasks | README or docs/ (see [readme.md](readme.md)) |

## Inline comments

Comment why, not what. Explain the reasoning behind a non-obvious line, workaround, or invariant directly next to it. A comment that restates the code is noise; delete or fix stale comments in the same change that edits the code. Evidence shows comments change with code: Fluri et al. 2007 found comment changes happen in the same revision as the code change (reported as 97% in secondary sources; abstract not retrieved; update both together).

For the user's own repos, the `programming` skill is the authority: follow it on comment density, and do not put ticket or issue numbers in comments. Published guides recommend linking an issue from a TODO or workaround; where `programming` applies, it wins.

## API doc comments

Document every public item: what it does, parameters, return value, errors, panics or exceptions, side effects, and a minimal example. When deprecating an item, name the replacement.

Each language follows its own conventions for doc comment sections:
- Rust: API guidelines (C-FAILURE) name Errors, Panics and Safety sections; the literal "# Errors" heading is the rustdoc convention.
- Python: Args, Returns, and Raises sections.
- Go: start the doc comment with the item name (package comments begin "Package " and type comments are complete sentences naming the symbol).
- TSDoc: @param and @returns tags without types (TypeScript already has them).

Examples in doc comments should be executed by the test runner so they cannot rot (Rust doctests, Python doctest, Go example tests).

## Per-language table

| Language | Tool and convention | Enforcement |
|---|---|---|
| Rust | rustdoc, /// and //!, doctests | rustc missing_docs lint ("allow by default because it can be noisy"), cargo doc with warnings denied |
| Python | docstrings, Sphinx or similar | ruff rules D100 to D107 confirmed (undocumented public module, class, method, function, package, magic method, nested class, __init__), pydocstyle conventions |
| Go | doc comments, godoc/pkgsite | go vet default checks include no doc-comment check; revive exported rule "warns on undocumented exported functions and methods"; staticcheck non-default ST1000, ST1020, ST1021, ST1022 |
| TypeScript | TSDoc, typedoc | eslint-plugin-jsdoc |
| Nix | nixpkgs uses RFC 145 /** */ comments through nixdoc (lib/strings.nix and lib/lists.nix use /** blocks, and doc/doc-support/lib-function-docs.nix runs nixdoc) | nixdoc CLI |
| Shell | Google Shell Style Guide ("File Header" top-level comment; "Function Comments" for library functions) | shellcheck does not check docs |

## Enforce it

Add documentation checks to automated verification:
- Run missing-docs lints in CI.
- Ensure the doc build fails on warnings.
- Run a link check on documentation.
- Keep docs updated in the same PR as the code (see [structure.md](structure.md)).

Macke and Doyle, "Testing the Effect of Code Documentation on Large Language Model Code Understanding" (2024, arXiv:2404.03114): "providing an LLM with "incorrect" documentation can greatly hinder code understanding, while incomplete or missing documentation does not seem to significantly affect an LLM's ability to understand code." Keep docs accurate or delete them.

## Anti-patterns

| Pattern | Fix |
|---|---|
| Comment restating the code | Delete or say why |
| Types repeated in TSDoc tags | Remove, the signature has them |
| Examples that are not executed | Make them doctests |
| TODO with no owner or condition | State the condition, or file the work and delete the comment (per `programming`, without a ticket number in the comment) |
| Stale comment after a refactor | Fix in the same change |

## Sources and confidence

| Source | URL |
|---|---|
| Rust API guidelines documentation | https://rust-lang.github.io/api-guidelines/documentation.html |
| rustdoc book | https://doc.rust-lang.org/rustdoc/ |
| rustc allowed-by-default lints | https://doc.rust-lang.org/rustc/lints/listing/allowed-by-default.html |
| Google Python style guide docstrings | https://google.github.io/styleguide/pyguide.html |
| Go doc comments | https://go.dev/doc/comment |
| revive rules | https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md |
| staticcheck checks | https://staticcheck.dev/docs/checks/ |
| TSDoc | https://tsdoc.org/ |
| ruff D rules | https://docs.astral.sh/ruff/rules/ |
| eslint-plugin-jsdoc | https://github.com/gajus/eslint-plugin-jsdoc |
| nixdoc | https://github.com/nix-community/nixdoc |
| Google Shell Style Guide | https://google.github.io/styleguide/shellguide.html |
| Fluri et al. 2007 | (cite by author and year) |
| Macke and Doyle 2024 (LLM code understanding) | https://arxiv.org/abs/2404.03114 |

Confidence: checked by running the tool or reading source on 2026-10-28. Remaining unverified: the Fluri 97% figure (abstract not retrieved).
