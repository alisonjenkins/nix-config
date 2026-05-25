// End-to-end test: assemble a fake jar with a synthetic mods.toml,
// parse it, and walk the dependency graph the way main.rs does. Uses no
// network, no real pack files — just exercises the pure logic stitched
// together.
use find_mod_bumps::jar::parse_jar_mods;
use find_mod_bumps::state::load_pack_state_from_strings;
use find_mod_bumps::topo::toposort_leaves_first;
use find_mod_bumps::version::in_range;
use std::collections::{HashMap, HashSet};
use std::io::Write;

fn write_fake_jar(dir: &std::path::Path, name: &str, toml_body: &str) -> std::path::PathBuf {
    let p = dir.join(name);
    let f = std::fs::File::create(&p).unwrap();
    let mut zw = zip::ZipWriter::new(f);
    let opts: zip::write::SimpleFileOptions =
        zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    zw.start_file("META-INF/neoforge.mods.toml", opts).unwrap();
    zw.write_all(toml_body.as_bytes()).unwrap();
    zw.finish().unwrap();
    p
}

#[test]
fn end_to_end_state_and_jar_parse() {
    let tmp = tempdir_simple("fmb_e2e");
    let jar = write_fake_jar(
        &tmp,
        "foo-1.0.jar",
        r#"
[[mods]]
modId = "foo"
version = "1.0.0"

[[dependencies.foo]]
modId = "bar"
versionRange = "[2.0,3.0)"
type = "required"
"#,
    );
    let parsed = parse_jar_mods(&jar);
    assert_eq!(parsed["foo"].version, "1.0.0");
    assert_eq!(parsed["foo"].deps[0].mod_id, "bar");

    // Pack state with one curseforge entry pointing at this jar's name.
    let mods = r#"
        { projectID = 1; fileID = 10; required = true; filename = "foo-1.0.jar"; }
    "#;
    let state = load_pack_state_from_strings(mods, "", "");
    assert!(state.contains_key("foo-1.0.jar"));

    // Reverse-edge for toposort: foo has zero dependents, bar has {foo}.
    let mut dependents: HashMap<String, HashSet<String>> = HashMap::new();
    dependents.insert("bar".to_string(), {
        let mut s = HashSet::new();
        s.insert("foo".to_string());
        s
    });
    let bumpable: HashSet<String> = ["foo"].into_iter().map(String::from).collect();
    let order = toposort_leaves_first(&bumpable, &dependents);
    assert_eq!(order, vec!["foo".to_string()]);
}

#[test]
fn range_checks_with_real_world_shapes() {
    // Smoke-test that combining version + range parsers handles the
    // common forms found in mods.toml files.
    assert!(in_range("6.0.10", "[6.0.0,7.0.0)"));
    assert!(!in_range("7.0.0", "[6.0.0,7.0.0)"));
    assert!(in_range("21.1.74", "[21.1.0,)"));
    assert!(in_range("1.5.2", "*"));
    assert!(in_range("", "[1,2)"));
}

// Bare-bones tempdir helper so this test crate doesn't pull in `tempfile`
// as a dev-dependency just for one path.
fn tempdir_simple(prefix: &str) -> std::path::PathBuf {
    let mut p = std::env::temp_dir();
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    p.push(format!("{}-{}", prefix, stamp));
    std::fs::create_dir_all(&p).unwrap();
    p
}
