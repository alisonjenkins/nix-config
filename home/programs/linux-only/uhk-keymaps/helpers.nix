{ lib }:
{
  findLayer = keymap: id: lib.findFirst (l: l.id == id) (throw "layer ${id} not found") keymap.layers;
  findModule = layer: id: lib.findFirst (m: m.id == id) (throw "module ${toString id} not found") layer.modules;

  noneActions = n: lib.genList (_: { keyActionType = "none"; }) n;

  setKeyAction = list: index: action: lib.imap0 (i: a: if i == index then action else a) list;
}
