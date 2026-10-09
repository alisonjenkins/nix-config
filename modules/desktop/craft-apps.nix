{ config, lib, pkgs, ... }:

let
  cfg = config.modules.desktop;

  apps = {
    photocraft = "Photocraft (Photoshop-style image editor)";
    vectorcraft = "VectorCraft (Illustrator-style vector illustration)";
    filmcraft = "FilmCraft (Premiere-style video editor)";
    lightcraft = "LightCraft (Lightroom-style photo library and raw development)";
    pdfcraft = "PdfCraft (Acrobat-style PDF tools)";
    effectcraft = "EffectCraft (After Effects-style motion graphics)";
    designcraft = "DesignCraft (InDesign-style page layout)";
  };
in
{
  options.modules.desktop.craftApps = lib.mapAttrs
    (_: description: {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        inherit description;
      };
    })
    apps;

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.concatLists (
      lib.mapAttrsToList
        (name: _: lib.optional cfg.craftApps.${name}.enable pkgs.${name})
        apps
    );
  };
}
