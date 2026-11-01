#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git ripgrep gnugrep coreutils findutils
# shellcheck shell=bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../check.sh"

# shellcheck source=/dev/null
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

SCRATCH_DIRS=()
cleanup() {
    local d
    for d in "${SCRATCH_DIRS[@]}"; do
        if [ -d "$d" ]; then
            rm -rf "$d"
        fi
    done
}
trap cleanup EXIT INT TERM

make_good_repo() {
    local dir
    dir="$(make_fixture_repo)"
    SCRATCH_DIRS+=("$dir")

    cat > "$dir/LICENSE" << 'EOF'
MIT License
EOF

    cat > "$dir/CONTRIBUTING.md" << 'EOF'
# Contributing
EOF

    cat > "$dir/SECURITY.md" << 'EOF'
# Security Policy
EOF

    mkdir -p "$dir/docs"
    cat > "$dir/docs/README.md" << 'EOF'
# Documentation

- [Guide](guide.md)
EOF

    cat > "$dir/docs/guide.md" << 'EOF'
# User Guide

This is the user guide.
EOF

    cat > "$dir/README.md" << 'EOF'
# Good Project

A reliable project description.

## Installation

```bash
cargo install good-project
```

## Usage

```bash
good-project --help
```

## Documentation

See [docs/README.md](docs/README.md) for details.

## License

MIT
EOF

    git -C "$dir" add .
    git -C "$dir" commit -q -m "initial"
    echo "$dir"
}

test_good_repo_zero_findings() {
    local repo; repo="$(make_good_repo)"
    local out
    out="$(main "$repo" 2>&1)"
    assert_eq "0 findings" "$out" "good repo produces 0 findings"
}

test_readme_missing() {
    local repo; repo="$(make_good_repo)"
    rm "$repo/README.md"
    rm -f "$repo/docs/README.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "HIGH	README.md	no README file found in root, .github/, or docs/" "readme_missing fires"
}

test_readme_short() {
    local repo; repo="$(make_good_repo)"
    cat > "$repo/README.md" << 'EOF'
# Short

## Usage
Usage info
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "MEDIUM	README.md	README has fewer than 10 lines" "readme_short fires"
}

test_readme_long() {
    local repo; repo="$(make_good_repo)"
    {
        cat "$repo/README.md"
        local i=0
        while [ "$i" -lt 550 ]; do
            echo "extra line $i"
            i=$((i + 1))
        done
    } > "$repo/README.md.tmp" && mv "$repo/README.md.tmp" "$repo/README.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	README.md	README has more than 500 lines" "readme_long fires"
}

test_no_install_or_usage() {
    local repo; repo="$(make_good_repo)"
    sed -i -e 's/## Installation/## Setup/' -e 's/## Usage/## Examples/' "$repo/README.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "MEDIUM	README.md	no heading matching (install|quickstart|getting started|usage)" "no_install_or_usage fires"
}

test_no_license() {
    local repo; repo="$(make_good_repo)"
    rm "$repo/LICENSE"
    sed -i -e 's/## License/## Copyright/' "$repo/README.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "MEDIUM	README.md	no LICENSE/LICENSE.md/COPYING in root and no License heading in README" "no_license fires"
}

test_many_badges() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'
![b1](https://img.shields.io/badge1)
![b2](https://img.shields.io/badge2)
![b3](https://img.shields.io/badge3)
![b4](https://img.shields.io/badge4)
![b5](https://img.shields.io/badge5)
![b6](https://img.shields.io/badge6)
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	README.md	more than 5 badge images in README" "many_badges fires"
}

test_no_badges_script_exits_zero() {
    # Run as a subprocess: command substitution in the other tests does not
    # inherit errexit, so only a real invocation sees the script die.
    local repo; repo="$(make_good_repo)"
    local out rc=0
    out="$(bash "$TARGET" "$repo" 2>&1)" || rc=$?
    assert_eq "0" "$rc" "script exits 0 on a README with no badges"
    assert_eq "0 findings" "$out" "script reports findings on a README with no badges"
}

test_fence_no_language() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'
```
unfenced code
```
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "code fence opened with no language" "fence_no_language fires"
}

test_image_no_alt() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'
![](docs/assets/logo.png)
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "markdown image with empty alt text" "image_no_alt fires on empty alt"

    cat >> "$repo/README.md" << 'EOF'
<img src="logo.png">
EOF
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "<img> tag without alt attribute" "image_no_alt fires on img without alt"
}

test_bad_link_text() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'
See [click here](docs/README.md) for info.
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "uninformative link text" "bad_link_text fires"
}

test_broken_relative_link() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'
See [nonexistent](docs/nonexistent.md) file.
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "HIGH	README.md:" "broken_relative_link reports file:line"
    assert_contains "$out" "broken relative link: docs/nonexistent.md" "broken_relative_link reports target"
}

test_orphan_doc() {
    local repo; repo="$(make_good_repo)"
    cat > "$repo/docs/unlinked.md" << 'EOF'
# Unlinked
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "MEDIUM	docs/unlinked.md	orphan doc not reachable from README" "orphan_doc fires"
}

test_docs_dir_no_index() {
    local repo; repo="$(make_good_repo)"
    rm "$repo/docs/README.md"
    cat > "$repo/docs/a.md" << 'EOF'
# A
EOF
    cat > "$repo/docs/b.md" << 'EOF'
# B
EOF
    sed -i -e '/docs\/README\.md/d' "$repo/README.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	docs	docs/ has 3+ markdown files but no docs/README.md and root README does not link into docs/" "docs_dir_no_index fires"
}

test_missing_community_files() {
    local repo; repo="$(make_good_repo)"
    rm "$repo/CONTRIBUTING.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	CONTRIBUTING.md	missing CONTRIBUTING.md in root, .github/, or docs/" "missing CONTRIBUTING fires"

    git -C "$repo" tag v1.0.0
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	CHANGELOG.md	missing CHANGELOG.md in root, .github/, or docs/" "missing CHANGELOG fires with git tag"
}

test_placeholder_text() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'
TODO: implement feature
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "placeholder text found:" "placeholder_text fires"
}

test_agent_file_duplication() {
    local repo; repo="$(make_good_repo)"
    cat > "$repo/CLAUDE.md" << 'EOF'
# Claude rules
EOF
    cat > "$repo/AGENTS.md" << 'EOF'
# Agent rules
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "MEDIUM	CLAUDE.md	both CLAUDE.md and AGENTS.md exist without import; import one from the other per agent-files.md" "agent_file_duplication fires"
}

test_agent_file_long() {
    local repo; repo="$(make_good_repo)"
    {
        echo "# Claude rules"
        local i=0
        while [ "$i" -lt 210 ]; do
            echo "rule line $i"
            i=$((i + 1))
        done
    } > "$repo/CLAUDE.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	CLAUDE.md	CLAUDE.md exceeds 200 lines" "agent_file_long fires"
}

test_readme_no_docs_link() {
    local repo; repo="$(make_good_repo)"
    sed -i -e 's|docs/README\.md|something_else|g' "$repo/README.md"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "LOW	README.md	docs/ has markdown files but README never mentions docs/" "readme_no_docs_link fires"
}

test_relative_path() {
    local fixture; fixture="$(make_good_repo)"
    cat >> "$fixture/README.md" << 'EOF'

[Guide](docs/guide.md)
EOF
    local out
    out="$( ( cd "$fixture" && main . ) 2>&1 )"
    assert_not_contains "$out" "orphan doc" "output does not contain orphan doc"

    cat > "$fixture/docs/stray.md" << 'EOF'
# Stray
EOF
    out="$( ( cd "$fixture" && main . ) 2>&1 )"
    assert_contains "$out" "MEDIUM	docs/stray.md	orphan doc not reachable from README" "orphan reported for stray.md"
}

test_fence_and_inline_code() {
    local repo; repo="$(make_good_repo)"
    cat >> "$repo/README.md" << 'EOF'

```text
[x](missing-in-fence.md)
```

`[y](missing-inline.md)`

[z](missing-real.md)
EOF
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "missing-real.md" "broken link outside code is reported"
    assert_not_contains "$out" "missing-in-fence.md" "link in code fence is ignored"
    assert_not_contains "$out" "missing-inline.md" "link in inline code is ignored"
}

test_good_repo_zero_findings
test_readme_missing
test_readme_short
test_readme_long
test_no_install_or_usage
test_no_license
test_many_badges
test_no_badges_script_exits_zero
test_fence_no_language
test_image_no_alt
test_bad_link_text
test_broken_relative_link
test_orphan_doc
test_docs_dir_no_index
test_missing_community_files
test_placeholder_text
test_agent_file_duplication
test_agent_file_long
test_readme_no_docs_link
test_relative_path
test_fence_and_inline_code

print_summary
