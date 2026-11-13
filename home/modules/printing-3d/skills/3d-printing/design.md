# Design and strength check

## Pin down the unknowns first

A part fitted to a real object needs measurements the user may not have given.
For each one, make it a named parameter with a one-line comment, pick a safe
default, and tell the user which to measure before printing. Example from a door
hook: door thickness, the gap above the door (limits the top plate thickness),
and whether a door stop sits where a leg goes. A wrong guess here costs a print,
so say so out loud instead of burying it.

## Orientation decides the geometry

PLA printed by FDM is much weaker across layers than along them. Printed values
vary a lot by printer and settings: along the layers about 45-55 MPa, across
them as low as 11-25 MPa. Design so every load runs along the layers:

1. Draw the part as a 2D profile in XY.
2. `linear_extrude` it along Z for the width.
3. Print it lying on its side, profile flat on the bed. Layer lines then follow
   every bend, and there are no overhangs to support.

Keep all walls multiples of the 0.4 mm nozzle line (2.0, 2.4, 3.0 ...). Rounding
convex corners with a small radius is fine; check a 2 mm wall survives the offset.

## Verify the model, not just the code

`openscad` renders PNGs headless, so look at the result instead of trusting the code:

- 3D view: `openscad -o x.png --camera=0,0,0,55,0,25,0 --viewall --autocenter --imgsize=800,600 x.scad`
  (rotation `55,0,25` is a three-quarter view). Read the PNG.
- Exact 2D profile: `openscad -o p.svg p.scad` on a file that ends in the 2D
  module, then `magick p.svg p.png` (or `convert`). Read the PNG.
- Check the STL bounding box against the intended size.
- Re-export the STL after every edit and compare with `cmp` against a fresh
  export before saying it is current.

## Strength check

Do the hand calc before declaring a load-bearing part done. A first design of a
door hook rated about 0.5 kg until the calc exposed a flaw; fixing it gave 5 kg.

1. Draw the free body: load P, where it acts, every contact with the object.
2. A hung load on one side tips the part. The tip is resisted by a couple of
   two contact forces with a vertical gap between them: `N = P * d / dy`.
3. Stress at each section: `sigma = Kt * M / Z`, with `Z = b * t^2 / 6` for a
   rectangle `b` wide and `t` thick. Use `Kt = 1.5` at inner fillets.
4. Check each contact leg as a cantilever. Stiffness is `k = 3 E I / L^3`, and
   PLA `E` is about 3000 MPa. A short stiff leg resists the tip; a long thin leg
   is soft and cannot. A tight "spring" interference on a stiff leg is a huge
   force (about 100 N per mm for a 30 mm wide, 12 mm long, 2 mm thick leg), so
   do not rely on one.
5. Allowables: in-plane tensile strength about 45 MPa (conservative). Sustained
   load: 20 percent of that. This 20 percent is an engineering assumption, no
   source gave a creep limit for FDM PLA. Peak load: strength divided by 2.
6. Turn the worst section into a rating in kg, sustained and peak, and tell the
   user. Say it is a 2D hand calc, not a simulation.

Always add the PLA warnings: creep under steady load, and softening near the
glass transition (about 55-65 C), so no sun, heaters or hot cars. Recommend a
loaded test (about twice the rated load for a day or two) before real use.
