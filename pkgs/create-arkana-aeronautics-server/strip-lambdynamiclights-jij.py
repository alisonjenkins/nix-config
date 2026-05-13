#!/usr/bin/env python3
# Remove META-INF/jarjar/lambdynamiclights-api*.jar (and its metadata.json
# entry) from a mod jar. Used to break a JPMS package conflict where
# ars_nouveau bundles lambdynamiclights-api as JIJ — exporting the same
# `dev.lambdaurora.lambdynlights.api.*` package as the top-level
# sodiumdynamiclights mod, which immersivelanterns hard-deps. Two
# providers to one consumer (`sauce`, also JIJ'd by other ars_* mods)
# trips ResolutionException at module-layer build.
import io, json, os, sys, zipfile, re

JAR_RE = re.compile(r"^META-INF/jarjar/lambdynamiclights-api[^/]*\.jar$")
META = "META-INF/jarjar/metadata.json"

def main():
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()
    src = zipfile.ZipFile(io.BytesIO(data), "r")
    names = set(src.namelist())
    if not any(JAR_RE.match(n) for n in names):
        return  # nothing to strip
    print(f"[jij-strip] {path.rsplit('/', 1)[-1]} — removing lambdynamiclights-api JIJ")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            n = info.filename
            if JAR_RE.match(n):
                continue
            content = src.read(n)
            if n == META:
                meta = json.loads(content.decode("utf-8"))
                meta["jars"] = [
                    j for j in meta.get("jars", [])
                    if j.get("identifier", {}).get("artifact") != "lambdynamiclights-api"
                ]
                content = json.dumps(meta, indent=2).encode("utf-8")
            dst.writestr(info, content)
    src.close()
    # In the server image build, mods/*.jar are symlinks into individual
    # /nix/store fetchurl paths so each jar lands in its own OCI layer.
    # Those targets are read-only; replace the symlink with a writable
    # copy before stamping the stripped jar on top.
    if os.path.islink(path):
        os.unlink(path)
    with open(path, "wb") as f:
        f.write(buf.getvalue())

if __name__ == "__main__":
    main()
