#!/usr/bin/env python3
# Remove `compat.CompatEMFMixin` from supplementaries-common.mixins.json
# inside a supplementaries jar.
#
# Why: supplementaries' CompatEMFMixin @Inject targets
# traben.entity_model_features.models.parts.EMFModelPartCustom and expects
# the pre-3.0 callback signature (without EMFModelPartRoot). EMF 3.x adds
# `EMFModelPartRoot` to that callback. Result on EMF 3.0+:
#
#     InvalidInjectionException: Invalid descriptor on
#       supplementaries-common.mixins.json:compat.CompatEMFMixin
#       Expected (...,CallbackInfo)V
#       but found  (...,EMFModelPartRoot,CallbackInfo)V
#
# AllTheLeaks 1.1.8 carries a runtime patch (`UntrackedIssue002`) that masks
# this on EMF [3.0.0, 3.0.6) but not on 3.0.6+, and any resource pack that
# causes EMF to load an EMFModelPartCustom (any FreshAnimations-style JEM
# pack) triggers the mixin apply at first model bake.
#
# Stripping the mixin loses the EMF-skin compat feature on entities that
# carry "Special Item Display Name" patrons sup uses for cosmetic skins —
# in practice that's the trinkets-on-mob hat overlay; everything else
# still renders normally. Worth it for boot stability.
import io, json, sys, zipfile

CONFIG = "supplementaries-common.mixins.json"
MIXIN_NAME = "compat.CompatEMFMixin"


def main():
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()
    src = zipfile.ZipFile(io.BytesIO(data), "r")
    if CONFIG not in src.namelist():
        sys.exit(f"[supp-strip] {CONFIG} not found in {path}")

    cfg = json.loads(src.read(CONFIG).decode("utf-8"))
    client = cfg.get("client", [])
    if MIXIN_NAME not in client:
        # Already stripped — idempotent no-op
        print(f"[supp-strip] {MIXIN_NAME} already absent in {path}")
        return
    cfg["client"] = [m for m in client if m != MIXIN_NAME]
    new_cfg = json.dumps(cfg, indent=4).encode("utf-8")
    print(f"[supp-strip] stripped {MIXIN_NAME} from {CONFIG} in {path}")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            if info.filename == CONFIG:
                dst.writestr(info, new_cfg)
            else:
                dst.writestr(info, src.read(info.filename))
    src.close()
    with open(path, "wb") as f:
        f.write(buf.getvalue())


if __name__ == "__main__":
    main()
