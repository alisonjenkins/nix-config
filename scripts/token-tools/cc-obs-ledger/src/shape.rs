//! Privacy-safe label for a Bash command: which programs ran and in what combination,
//! never what they were given. Every word in the output comes from the fixed
//! vocabulary below, so an unknown program name, path, URL, env value or any other
//! text of the command cannot reach the label.

const MAX_LEN: usize = 80;
const MAX_SEGMENTS: usize = 4;
/// How many layers of `bash -c` / `nix develop -c` wrappers are looked through.
const MAX_DEPTH: u8 = 2;
const UNPARSED: &str = "unparsed";
const OTHER: &str = "other";

const PROGRAMS: &[&str] = &[
    "cargo",
    "git",
    "gh",
    "nix",
    "nix-shell",
    "nixos-rebuild",
    "home-manager",
    "just",
    "nh",
    "jq",
    "rg",
    "grep",
    "find",
    "fd",
    "ls",
    "cat",
    "head",
    "tail",
    "sed",
    "awk",
    "sort",
    "uniq",
    "wc",
    "cut",
    "tr",
    "cp",
    "mv",
    "rm",
    "mkdir",
    "touch",
    "chmod",
    "ln",
    "stat",
    "readlink",
    "realpath",
    "dirname",
    "basename",
    "echo",
    "printf",
    "test",
    "date",
    "pwd",
    "curl",
    "python3",
    "python",
    "node",
    "npm",
    "go",
    "make",
    "bash",
    "sh",
    "zsh",
    "sleep",
    "kill",
    "ps",
    "tee",
    "xargs",
    "diff",
    "patch",
    "tar",
    "unzip",
    "systemctl",
    "journalctl",
    "docker",
    "kubectl",
    "ssh",
    "scp",
    "rsync",
    "cc-obs-query",
];

/// Programs whose first non-flag argument is a subcommand worth keeping, and the only
/// subcommands kept. Anything else is dropped, since an unknown token can be a name.
const SUBCOMMANDS: &[(&str, &[&str])] = &[
    (
        "cargo",
        &[
            "test", "build", "check", "clippy", "fmt", "run", "bench", "doc", "update", "add",
            "install", "nextest", "tree", "metadata",
        ],
    ),
    (
        "git",
        &[
            "status",
            "log",
            "diff",
            "show",
            "add",
            "commit",
            "push",
            "pull",
            "fetch",
            "rebase",
            "switch",
            "checkout",
            "worktree",
            "stash",
            "branch",
            "merge",
            "reset",
            "restore",
            "clone",
            "remote",
            "tag",
            "cherry-pick",
            "apply",
            "blame",
            "rev-parse",
            "config",
            "ls-files",
        ],
    ),
    (
        "gh",
        &[
            "pr", "issue", "run", "api", "repo", "workflow", "release", "auth",
        ],
    ),
    (
        "nix",
        &[
            "build",
            "develop",
            "shell",
            "run",
            "flake",
            "eval",
            "fmt",
            "search",
            "store",
            "path-info",
            "hash",
            "copy",
            "profile",
            "log",
            "derivation",
            "repl",
            "why-depends",
        ],
    ),
    (
        "just",
        &[
            "switch", "boot", "build", "test", "update", "check", "deploy", "fmt", "lint",
        ],
    ),
    (
        "docker",
        &[
            "run", "build", "ps", "images", "compose", "exec", "logs", "pull", "push", "stop", "rm",
        ],
    ),
    (
        "kubectl",
        &[
            "get",
            "describe",
            "apply",
            "delete",
            "logs",
            "exec",
            "rollout",
            "port-forward",
            "config",
        ],
    ),
    ("npm", &["install", "run", "test", "ci", "build", "start"]),
    (
        "systemctl",
        &[
            "status",
            "start",
            "stop",
            "restart",
            "enable",
            "disable",
            "reload",
            "daemon-reload",
            "is-active",
            "list-units",
            "show",
            "cat",
        ],
    ),
];

/// Wrappers that run the next word as the real command.
const PREFIX_WRAPPERS: &[&str] = &["env", "time", "nohup", "command", "sudo", "nice"];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Op {
    Start,
    Pipe,
    And,
    Or,
}

#[derive(Default)]
struct Flags {
    cd: bool,
    env: bool,
    bg: bool,
    heredoc: bool,
}

/// The shape label of a Bash command, e.g. `cargo test | tail [cd][env]`.
pub fn command_shape(command: &str) -> String {
    let mut flags = Flags::default();
    let Some(items) = analyse(command, 0, &mut flags) else {
        return UNPARSED.to_owned();
    };
    if items.is_empty() {
        return UNPARSED.to_owned();
    }
    let total = items.len();
    let mut kept = total.min(MAX_SEGMENTS);
    loop {
        let label = render(&items, kept, &flags);
        if label.len() <= MAX_LEN || kept <= 1 {
            return label;
        }
        kept = kept.saturating_sub(1);
    }
}

/// The label for a `tool_use` block: only the Bash tool has one.
pub fn tool_shape(tool: &str, command: Option<&str>) -> Option<String> {
    (tool == "Bash").then(|| command_shape(command.unwrap_or_default()))
}

fn render(items: &[(Op, String)], kept: usize, flags: &Flags) -> String {
    let mut out = String::new();
    for (index, (op, label)) in items.iter().take(kept).enumerate() {
        if index > 0 {
            out.push_str(match op {
                Op::Pipe => " | ",
                Op::Or => " || ",
                Op::And | Op::Start => " && ",
            });
        }
        out.push_str(label);
    }
    let dropped = items.len().saturating_sub(kept);
    if dropped > 0 {
        out.push_str(&format!(" +{dropped}"));
    }
    for (set, tag) in [
        (flags.cd, "[cd]"),
        (flags.env, "[env]"),
        (flags.bg, "[bg]"),
        (flags.heredoc, "[heredoc]"),
    ] {
        if set {
            if !out.contains('[') {
                out.push(' ');
            }
            out.push_str(tag);
        }
    }
    out
}

fn analyse(command: &str, depth: u8, flags: &mut Flags) -> Option<Vec<(Op, String)>> {
    let mut items = Vec::new();
    for (index, (op, text)) in split(command, flags)?.into_iter().enumerate() {
        items.extend(segment(&words(&text)?, op, index == 0, depth, flags));
    }
    Some(items)
}

fn flush(out: &mut Vec<(Op, String)>, current: &mut String, op: &mut Op, next: Op) {
    if current.trim().is_empty() {
        current.clear();
        return;
    }
    out.push((*op, std::mem::take(current)));
    *op = next;
}

/// Splits on top-level `&&`, `||`, `;`, `|`, `&` and newlines, outside quotes and
/// subshells. `None` for an unterminated quote.
fn split(command: &str, flags: &mut Flags) -> Option<Vec<(Op, String)>> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut op = Op::Start;
    let mut quote: Option<char> = None;
    let mut parens: usize = 0;
    let mut before: Option<char> = None;
    let mut chars = command.chars().peekable();
    while let Some(c) = chars.next() {
        let prev = before.replace(c);
        if let Some(q) = quote {
            current.push(c);
            if c == '\\' && q == '"' {
                if let Some(escaped) = chars.next() {
                    current.push(escaped);
                }
            } else if c == q {
                quote = None;
            }
            continue;
        }
        match c {
            '\'' | '"' | '`' => {
                quote = Some(c);
                current.push(c);
            }
            '\\' => match chars.next() {
                Some('\n') => current.push(' '),
                Some(escaped) => {
                    current.push('\\');
                    current.push(escaped);
                }
                None => {}
            },
            '(' => {
                parens = parens.saturating_add(1);
                current.push(c);
            }
            ')' => {
                parens = parens.saturating_sub(1);
                current.push(c);
            }
            _ if parens > 0 => current.push(c),
            '#' if prev.is_none_or(char::is_whitespace) => {
                while chars.peek().is_some_and(|n| *n != '\n') {
                    chars.next();
                }
            }
            '<' => {
                current.push(c);
                if chars.peek() == Some(&'<') {
                    flags.heredoc = true;
                }
            }
            '&' => {
                if chars.peek() == Some(&'&') {
                    chars.next();
                    flush(&mut out, &mut current, &mut op, Op::And);
                } else if matches!(prev, Some('>' | '<')) || chars.peek() == Some(&'>') {
                    current.push(c);
                } else {
                    flags.bg = true;
                    flush(&mut out, &mut current, &mut op, Op::And);
                }
            }
            '|' => {
                if chars.peek() == Some(&'|') {
                    chars.next();
                    flush(&mut out, &mut current, &mut op, Op::Or);
                } else {
                    flush(&mut out, &mut current, &mut op, Op::Pipe);
                }
            }
            ';' => flush(&mut out, &mut current, &mut op, Op::And),
            '\n' => {
                flush(&mut out, &mut current, &mut op, Op::And);
                if flags.heredoc {
                    break;
                }
            }
            _ => current.push(c),
        }
    }
    if quote.is_some() {
        return None;
    }
    flush(&mut out, &mut current, &mut op, Op::And);
    Some(out)
}

/// Shell words of one segment with quotes removed. `None` for an unterminated quote.
fn words(segment: &str) -> Option<Vec<String>> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut in_word = false;
    let mut quote: Option<char> = None;
    let mut chars = segment.chars();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (Some(q), _) if c == q => quote = None,
            (Some('"'), '\\') | (None, '\\') => {
                if let Some(escaped) = chars.next() {
                    current.push(escaped);
                }
                in_word = true;
            }
            (Some(_), _) => current.push(c),
            (None, '\'' | '"' | '`') => {
                quote = Some(c);
                in_word = true;
            }
            (None, _) if c.is_whitespace() => {
                if in_word {
                    out.push(std::mem::take(&mut current));
                    in_word = false;
                }
            }
            (None, _) => {
                current.push(c);
                in_word = true;
            }
        }
    }
    if quote.is_some() {
        return None;
    }
    if in_word {
        out.push(current);
    }
    Some(out)
}

fn is_assignment(word: &str) -> bool {
    let Some((name, _)) = word.split_once('=') else {
        return false;
    };
    let mut chars = name.chars();
    chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn basename(word: &str) -> &str {
    word.rsplit('/').next().unwrap_or(word)
}

fn segment(all: &[String], op: Op, first: bool, depth: u8, flags: &mut Flags) -> Vec<(Op, String)> {
    let mut rest = all;
    loop {
        let Some((head, tail)) = rest.split_first() else {
            return Vec::new();
        };
        if is_assignment(head) {
            flags.env = true;
            rest = tail;
            continue;
        }
        let program = basename(head);
        if PREFIX_WRAPPERS.contains(&program) {
            rest = tail;
            while let Some((flag, after)) = rest.split_first() {
                if !flag.starts_with('-') {
                    break;
                }
                rest = after;
            }
            continue;
        }
        match program {
            "cd" => {
                flags.cd |= first;
                return Vec::new();
            }
            "export" => {
                flags.env = true;
                return Vec::new();
            }
            _ => break,
        }
    }
    let Some(head) = rest.first() else {
        return Vec::new();
    };
    let program = basename(head);
    if depth < MAX_DEPTH {
        if let Some(items) = unwrap_wrapper(program, rest, op, first, depth, flags) {
            return items;
        }
    }
    vec![(op, label(program, rest))]
}

/// Looks through `bash -c`, `nix-shell --run`, `nix develop -c`; `None` when the
/// program is not a wrapper or carries no inner command.
fn unwrap_wrapper(
    program: &str,
    rest: &[String],
    op: Op,
    first: bool,
    depth: u8,
    flags: &mut Flags,
) -> Option<Vec<(Op, String)>> {
    let inner_depth = depth.saturating_add(1);
    let inner_string = match program {
        "bash" | "sh" | "zsh" => {
            let at = rest.iter().position(|w| {
                w == "-c" || (w.len() <= 4 && w.starts_with('-') && w.contains('c'))
            })?;
            rest.get(at.saturating_add(1))?
        }
        "nix-shell" => {
            let at = rest.iter().position(|w| w == "--run" || w == "--command")?;
            rest.get(at.saturating_add(1))?
        }
        "nix" if matches!(rest.get(1).map(String::as_str), Some("develop" | "shell")) => {
            let at = rest.iter().position(|w| w == "-c" || w == "--command")?;
            let inner = rest.get(at.saturating_add(1)..)?;
            let items = segment(inner, op, false, inner_depth, flags);
            return (!items.is_empty()).then_some(items);
        }
        _ => return None,
    };
    let mut inner_flags = Flags::default();
    let mut items = analyse(inner_string, inner_depth, &mut inner_flags)?;
    flags.cd |= inner_flags.cd && first;
    flags.env |= inner_flags.env;
    flags.bg |= inner_flags.bg;
    flags.heredoc |= inner_flags.heredoc;
    items.first_mut()?.0 = op;
    Some(items)
}

fn label(program: &str, rest: &[String]) -> String {
    let Some(known) = PROGRAMS.iter().find(|p| **p == program) else {
        return OTHER.to_owned();
    };
    let Some((_, allowed)) = SUBCOMMANDS.iter().find(|(p, _)| p == known) else {
        return (*known).to_owned();
    };
    let mut args = rest.iter().skip(1);
    let mut subcommand = None;
    while let Some(arg) = args.next() {
        if *known == "git" && (arg == "-C" || arg == "-c") {
            args.next();
        } else if !arg.starts_with('-') {
            subcommand = Some(arg);
            break;
        }
    }
    match subcommand {
        Some(sub) if allowed.contains(&sub.as_str()) => format!("{known} {sub}"),
        _ => (*known).to_owned(),
    }
}
