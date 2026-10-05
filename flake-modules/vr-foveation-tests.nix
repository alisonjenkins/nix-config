# Hermetic unit tests (no GPU, headset or game) for the VR foveation benchmark
# tooling's statistics, report and sampler logic (spec 005, SC-007). The
# package's checkPhase runs the unittest suite, so the check is the package
# itself: building it runs the tests.
#   nix build .#checks.x86_64-linux.vr-foveation-bench-tests
{ ... }:
{
  perSystem = { self', lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
      checks.vr-foveation-bench-tests = self'.packages.vr-foveation-bench;
    };
}
