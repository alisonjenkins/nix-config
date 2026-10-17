#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use cc_obs_ledger::shape::{command_shape, tool_shape};

#[test]
fn the_documented_example_has_the_documented_shape() {
    assert_eq!(
        command_shape("cd /x && CARGO_TARGET_DIR=/y cargo test --no-fail-fast 2>&1 | tail -5"),
        "cargo test | tail [cd][env]"
    );
}

#[test]
fn shapes_for_common_commands() {
    for (command, expected) in [
        ("git status", "git status"),
        ("git -C /some/repo log --oneline", "git log"),
        ("git frobnicate", "git"),
        ("gh pr view 12 --json title", "gh pr"),
        ("ls -la /etc", "ls"),
        ("rg foo src | head -20", "rg | head"),
        ("make-it-so --now", "other"),
        ("./scripts/deploy.sh prod", "other"),
        ("sleep 5; kill 123", "sleep && kill"),
        ("a || b", "other || other"),
        ("journalctl -u foo", "journalctl"),
        ("systemctl status foo", "systemctl status"),
        ("export FOO=bar", "unparsed"),
        ("cd /tmp", "unparsed"),
        ("", "unparsed"),
        ("   ", "unparsed"),
        ("echo 'unterminated", "unparsed"),
        ("sleep 100 &", "sleep [bg]"),
        ("echo hi 2>&1", "echo"),
        ("cat <<EOF\nline one\nrm -rf /\nEOF", "cat [heredoc]"),
        ("echo 'a && b | c'", "echo"),
        ("echo $(git status && ls)", "echo"),
        ("sudo systemctl restart foo", "systemctl restart"),
        ("time env A=1 cargo build", "cargo build [env]"),
        ("# a comment\ncargo fmt", "cargo fmt"),
    ] {
        assert_eq!(command_shape(command), expected, "for {command:?}");
    }
}

#[test]
fn wrappers_are_looked_through() {
    for (command, expected) in [
        (
            "bash -c 'cargo test && cargo clippy'",
            "cargo test && cargo clippy",
        ),
        ("sh -lc \"git status\"", "git status"),
        ("nix develop -c cargo test", "cargo test"),
        ("nix develop --command bash -c 'cargo fmt'", "cargo fmt"),
        ("nix-shell -p jq --run 'jq . x'", "jq"),
        ("bash script.sh", "bash"),
        ("bash -c 'bash -c \"bash -c \\\"git status\\\"\"'", "bash"),
    ] {
        assert_eq!(command_shape(command), expected, "for {command:?}");
    }
}

#[test]
fn long_pipelines_are_capped_with_a_count() {
    assert_eq!(
        command_shape("cat a | grep b | sort | uniq | wc -l | head"),
        "cat | grep | sort | uniq +2"
    );
}

#[test]
fn only_the_bash_tool_gets_a_shape() {
    assert_eq!(tool_shape("Read", Some("ls")), None);
    assert_eq!(tool_shape("Bash", Some("ls")).as_deref(), Some("ls"));
    assert_eq!(tool_shape("Bash", None).as_deref(), Some("unparsed"));
}

const SECRETS: &[&str] = &[
    "ghp_SECRET",
    "/home/ali/secret",
    "hunter2",
    "https://x.y/z",
    "secret",
    "x.y",
    "my-private-project",
    "TOKEN123",
];

const HOSTILE: &[&str] = &[
    "curl -H 'Authorization: Bearer ghp_SECRET' https://x.y/z",
    "GH_TOKEN=ghp_SECRET gh api /repos/ali/my-private-project",
    "cd /home/ali/secret && cargo test --password=hunter2",
    "mysql --password=hunter2 -h x.y",
    "ssh ali@my-private-project.x.y 'cat /home/ali/secret'",
    "my-private-project --token TOKEN123",
    "/home/ali/secret/bin/my-private-project run",
    "git commit -m 'ghp_SECRET hunter2' && git push https://x.y/z",
    "bash -c 'curl https://x.y/z -d password=hunter2'",
    "nix-shell -p hunter2 --run 'my-private-project ghp_SECRET'",
    "echo \"$(cat /home/ali/secret)\" | tee x.y",
    "export TOKEN123=ghp_SECRET; ./my-private-project",
    "cat <<EOF\nghp_SECRET hunter2 /home/ali/secret\nEOF",
    "git -C /home/ali/secret hunter2",
    "git ghp_SECRET",
    "cargo hunter2",
    "docker run --rm -e TOKEN123=hunter2 my-private-project:latest",
    "'my-private-project' \"ghp_SECRET\"",
    "FOO=$(cat /home/ali/secret) true",
    "rm -rf /home/ali/secret &",
    "echo \"unterminated ghp_SECRET",
    "sudo -u my-private-project hunter2",
];

#[test]
fn no_argument_path_url_env_value_or_name_survives() {
    for command in HOSTILE {
        let shape = command_shape(command);
        for secret in SECRETS {
            assert!(
                !shape.contains(secret),
                "{shape:?} leaks {secret:?} from {command:?}"
            );
        }
        for forbidden in ['/', '=', '$', '"', '\'', '.', '`', '\\'] {
            assert!(
                !shape.contains(forbidden),
                "{shape:?} contains {forbidden:?} for {command:?}"
            );
        }
    }
}

#[test]
fn shapes_are_short_and_stable() {
    let long = ["cargo test"; 40].join(" && ");
    let mut commands: Vec<&str> = HOSTILE.to_vec();
    commands.push(&long);
    for command in commands {
        let shape = command_shape(command);
        assert!(shape.len() <= 80, "{shape:?} is {} chars", shape.len());
        assert_eq!(shape, command_shape(command));
    }
}
