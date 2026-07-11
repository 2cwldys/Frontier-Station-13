# Serenity to Aurora Sprite Swap Candidates

Research-only proposal. Nothing in this document has been applied to either codebase. Every entry below is a **1:1 candidate**: an item that already exists in Aurora would have its `icon`/`icon_state` swapped to match the equivalent Serenity item. No new items are proposed.

## Summary

- **524 candidate entries** proposed below (representing **610 individual Aurora `/obj/item` type paths**, since 8 entries consolidate 94 near-identical subtypes -- e.g. all 47 `/obj/item/dnainjector/*` mutation variants share one icon/icon_state swap, so they are listed once).
- **156 entries flagged CAUTION** -- the sprite is state-dependent (damage/charge/on-off/emag) or uses a computed icon_state expression, or both. These are still included per instructions, just flagged for a human to double-check before swapping.
- Confidence breakdown: **490 HIGH**, **23 MODERATE** (name/desc text differs somewhat despite identical type path), **11 MODERATE/path-only** (name or desc not explicitly set in-file on one side).
- `/obj/item/radio/intercom` and all intercom subtypes are excluded entirely, per instruction.

### Methodology

- Scope: every `.dm` file under `code/game/objects/items/**` and `code/modules/clothing/**` in both codebases, plus each codebase's single base-class file (`code/game/objects/items.dm`) so inherited `icon`/`icon_state` values (where a subtype does not redefine them) resolve correctly instead of showing as unset.
- Aurora and Serenity share the same upstream lineage, but Serenity still carries the older `/obj/item/weapon/...` and `/obj/item/device/...` path segments that Aurora has since dropped (e.g. Serenity's `/obj/item/weapon/wrench` vs Aurora's `/obj/item/wrench`). Matching was done on type paths normalized by stripping those two legacy segments, then requiring an otherwise-identical remaining path.
- For each matched pair, `icon`/`icon_state`/`name`/`desc` were resolved by walking up the type's parent chain (respecting `parent_type` overrides) within each codebase until an explicit value was found, so recolor/variant subtypes that only override `icon_state` still get the correct inherited `icon` file.
- A pair is only listed here if the resolved `icon` and/or `icon_state` actually differ between the two codebases. Pairs that resolved identically were dropped as not a sprite difference.
- Matches with a weak/unclear name-and-description correlation were dropped entirely rather than included (a handful of such pairs were found and excluded, e.g. two items that only coincidentally shared a normalized type path with no similar name or description).
- CAUTION flags were derived from (a) any `icon`/`icon_state` assignment found elsewhere in the type's code body (procs such as `update_icon()`, `burnout()`, etc.), signalling the sprite is state-dependent, and (b) `icon_state` values that are computed expressions (`pick(...)`, `initial(...)`, string interpolation) rather than fixed literals.
- This was a scripted/systematic pass (parsing `.dm` type definitions) followed by manual spot-checking, not an exhaustive hand-read of every file; given the volume (600+ raw candidates across roughly 6,000 Aurora and 2,800 Serenity type definitions in scope), treat this as a strong first-pass proposal for human review, not a guaranteed-perfect list.

## Table of contents

- [Tools](#tools) (18)
- [Weapons](#weapons) (38)
- [Devices](#devices) (53)
- [Storage & Containers](#storage--containers) (79)
- [Stacks & Materials](#stacks--materials) (19)
- [Chemistry / Reagent Containers](#chemistry--reagent-containers) (8)
- [Clothing - Head](#clothing---head) (39)
- [Clothing - Masks](#clothing---masks) (12)
- [Clothing - Glasses](#clothing---glasses) (8)
- [Clothing - Ears](#clothing---ears) (15)
- [Clothing - Gloves](#clothing---gloves) (1)
- [Clothing - Shoes](#clothing---shoes) (17)
- [Clothing - Suits](#clothing---suits) (38)
- [Clothing - Under (Uniforms)](#clothing---under-uniforms) (40)
- [Clothing - Accessories](#clothing---accessories) (22)
- [Clothing - Other](#clothing---other) (3)
- [Hardsuit / RIG Control Modules](#hardsuit--rig-control-modules) (35)
- [ID Cards & Access](#id-cards--access) (16)
- [Implants](#implants) (13)
- [DNA Injectors (Genetics)](#dna-injectors-genetics) (1)
- [Personal Care & Cosmetics](#personal-care--cosmetics) (12)
- [Smoking & Fire](#smoking--fire) (8)
- [Tape & Sealing](#tape--sealing) (8)
- [Medical / Morgue](#medical--morgue) (1)
- [Engineering Misc](#engineering-misc) (4)
- [Food, Toys & Misc Props](#food-toys--misc-props) (5)
- [Misc / Other](#misc--other) (11)

---

## Tools (18)

#### 1. gas analyzer

- **Aurora**: `/obj/item/analyzer` -- code/game/objects/items/devices/scanners.dm
  name: gas analyzer -- icon: icons/obj/item/scanner.dmi -- icon_state: `airanalyzer`
- **Serenity**: `/obj/item/device/analyzer` -- code/game/objects/items/devices/scanners.dm
  name: analyzer -- icon: icons/obj/device.dmi -- icon_state: `atmos`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 2. pocket crowbar

- **Aurora**: `/obj/item/crowbar/red` -- code/game/objects/items/tools/crowbar.dm
  name: pocket crowbar -- icon: icons/obj/tools.dmi -- icon_state: `crowbar_red`
- **Serenity**: `/obj/item/weapon/crowbar/red` -- code/game/objects/items/weapons/tools.dm
  name: crowbar -- icon: icons/obj/tools.dmi -- icon_state: `red_crowbar`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 3. fire extinguisher

- **Aurora**: `/obj/item/extinguisher` -- code/game/objects/items/weapons/extinguisher.dm
  name: fire extinguisher -- icon: icons/obj/chemical.dmi -- icon_state: `fire_extinguisher0`
- **Serenity**: `/obj/item/weapon/extinguisher` -- code/game/objects/items/weapons/extinguisher.dm
  name: fire extinguisher -- icon: icons/obj/items.dmi -- icon_state: `fire_extinguisher0`
- Confidence: HIGH -- identical type path structure and identical name ("fire extinguisher").

#### 4. fire extinguisher

- **Aurora**: `/obj/item/extinguisher/mini` -- code/game/objects/items/weapons/extinguisher.dm
  name: fire extinguisher -- icon: icons/obj/chemical.dmi -- icon_state: `miniFE0`
- **Serenity**: `/obj/item/weapon/extinguisher/mini` -- code/game/objects/items/weapons/extinguisher.dm
  name: fire extinguisher -- icon: icons/obj/items.dmi -- icon_state: `miniFE0`
- Confidence: HIGH -- identical type path structure and identical name ("fire extinguisher").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 5. health analyzer

- **Aurora**: `/obj/item/healthanalyzer` -- code/game/objects/items/devices/scanners.dm
  name: health analyzer -- icon: icons/obj/item/scanner.dmi -- icon_state: `healthanalyzer`
- **Serenity**: `/obj/item/device/healthanalyzer` -- code/game/objects/items/devices/scanners.dm
  name: health analyzer -- icon: icons/obj/device.dmi -- icon_state: `health`
- Confidence: HIGH -- identical type path structure and identical name ("health analyzer").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. blue

- **Aurora**: `/obj/item/pen/crayon/blue` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonblue`
- **Serenity**: `/obj/item/weapon/pen/crayon/blue` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonblue`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 7. green

- **Aurora**: `/obj/item/pen/crayon/green` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayongreen`
- **Serenity**: `/obj/item/weapon/pen/crayon/green` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayongreen`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 8. mime

- **Aurora**: `/obj/item/pen/crayon/mime` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonmime`
- **Serenity**: `/obj/item/weapon/pen/crayon/mime` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonmime`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 9. orange

- **Aurora**: `/obj/item/pen/crayon/orange` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonorange`
- **Serenity**: `/obj/item/weapon/pen/crayon/orange` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonorange`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 10. purple

- **Aurora**: `/obj/item/pen/crayon/purple` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonpurple`
- **Serenity**: `/obj/item/weapon/pen/crayon/purple` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonpurple`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 11. rainbow

- **Aurora**: `/obj/item/pen/crayon/rainbow` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonrainbow`
- **Serenity**: `/obj/item/weapon/pen/crayon/rainbow` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonrainbow`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 12. red

- **Aurora**: `/obj/item/pen/crayon/red` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonred`
- **Serenity**: `/obj/item/weapon/pen/crayon/red` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonred`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 13. yellow

- **Aurora**: `/obj/item/pen/crayon/yellow` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: icons/obj/storage/fancy/crayon.dmi -- icon_state: `crayonyellow`
- **Serenity**: `/obj/item/weapon/pen/crayon/yellow` -- code/game/objects/items/crayons.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `crayonyellow`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 14. welding tool

- **Aurora**: `/obj/item/weldingtool` -- code/game/objects/items/tools/tools.dm
  name: welding tool -- icon: icons/obj/item/welding_tools.dmi -- icon_state: `welder`
- **Serenity**: `/obj/item/weapon/weldingtool` -- code/game/objects/items/weapons/tools.dm
  name: welding tool -- icon: icons/obj/tools.dmi -- icon_state: `welder_m`
- Confidence: HIGH -- identical type path structure and identical name ("welding tool").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 15. experimental welding tool

- **Aurora**: `/obj/item/weldingtool/experimental` -- code/game/objects/items/tools/tools.dm
  name: experimental welding tool -- icon: icons/obj/item/welding_tools.dmi -- icon_state: `expwelder`
- **Serenity**: `/obj/item/weapon/weldingtool/experimental` -- code/game/objects/items/weapons/tools.dm
  name: experimental welding tool -- icon: icons/obj/tools.dmi -- icon_state: `welder_l`
- Confidence: HIGH -- identical type path structure and identical name ("experimental welding tool").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 16. advanced welding tool

- **Aurora**: `/obj/item/weldingtool/hugetank` -- code/game/objects/items/tools/tools.dm
  name: advanced welding tool -- icon: icons/obj/item/welding_tools.dmi -- icon_state: `advwelder`
- **Serenity**: `/obj/item/weapon/weldingtool/hugetank` -- code/game/objects/items/weapons/tools.dm
  name: upgraded welding tool -- icon: icons/obj/tools.dmi -- icon_state: `welder_h`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 17. industrial welding tool

- **Aurora**: `/obj/item/weldingtool/largetank` -- code/game/objects/items/tools/tools.dm
  name: industrial welding tool -- icon: icons/obj/item/welding_tools.dmi -- icon_state: `indwelder`
- **Serenity**: `/obj/item/weapon/weldingtool/largetank` -- code/game/objects/items/weapons/tools.dm
  name: industrial welding tool -- icon: icons/obj/tools.dmi -- icon_state: `welder_l`
- Confidence: HIGH -- identical type path structure and identical name ("industrial welding tool").

#### 18. wirecutters

- **Aurora**: `/obj/item/wirecutters` -- code/game/objects/items/tools/tools.dm
  name: wirecutters -- icon: icons/obj/tools.dmi -- icon_state: `wirecutters`
- **Serenity**: `/obj/item/weapon/wirecutters` -- code/game/objects/items/weapons/tools.dm
  name: wirecutters -- icon: icons/obj/tools.dmi -- icon_state: `cutters`
- Confidence: HIGH -- identical type path structure and identical name ("wirecutters").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

---

## Weapons (38)

#### 1. photon disruption grenade

- **Aurora**: `/obj/item/grenade/anti_photon` -- code/game/objects/items/weapons/grenades/anti_photon_grenade.dm
  name: photon disruption grenade -- icon: icons/obj/grenade.dmi -- icon_state: `photon`
- **Serenity**: `/obj/item/weapon/grenade/anti_photon` -- code/game/objects/items/weapons/grenades/anti_photon_grenade.dm
  name: photon disruption grenade -- icon: icons/obj/grenade.dmi -- icon_state: `emp`
- Confidence: HIGH -- identical type path structure and identical name ("photon disruption grenade").

#### 2. fragmentation grenade

- **Aurora**: `/obj/item/grenade/fake` -- code/game/objects/items/weapons/grenades/fake_grenade.dm
  name: fragmentation grenade -- icon: icons/obj/grenade.dmi -- icon_state: `frag`
- **Serenity**: `/obj/item/weapon/grenade/fake` -- code/game/objects/items/weapons/grenades/prank_grenades.dm
  name: grenade -- icon: icons/obj/grenade.dmi -- icon_state: `frggrenade`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "fragmentation grenade" / Serenity: "grenade") -- verify these are truly the same item before swapping.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 3. fragmentation grenade

- **Aurora**: `/obj/item/grenade/frag` -- code/game/objects/items/weapons/grenades/fragmentation.dm
  name: fragmentation grenade -- icon: icons/obj/grenade.dmi -- icon_state: `frag`
- **Serenity**: `/obj/item/weapon/grenade/frag` -- code/game/objects/items/weapons/grenades/explosive.dm
  name: fragmentation grenade -- icon: icons/obj/grenade.dmi -- icon_state: `frggrenade`
- Confidence: HIGH -- identical type path structure and identical name ("fragmentation grenade").

#### 4. handcuffs

- **Aurora**: `/obj/item/handcuffs` -- code/game/objects/items/weapons/handcuffs.dm
  name: handcuffs -- icon: icons/obj/handcuffs.dmi -- icon_state: `handcuff`
- **Serenity**: `/obj/item/weapon/handcuffs` -- code/game/objects/items/weapons/handcuffs.dm
  name: handcuffs -- icon: icons/obj/items.dmi -- icon_state: `handcuff`
- Confidence: HIGH -- identical type path structure and identical name ("handcuffs").

#### 5. cable restraints

- **Aurora**: `/obj/item/handcuffs/cable` -- code/game/objects/items/weapons/handcuffs.dm
  name: cable restraints -- icon: icons/obj/handcuffs.dmi -- icon_state: `cablecuff`
- **Serenity**: `/obj/item/weapon/handcuffs/cable` -- code/game/objects/items/weapons/handcuffs.dm
  name: cable restraints -- icon: icons/obj/items.dmi -- icon_state: `cuff_white`
- Confidence: HIGH -- identical type path structure and identical name ("cable restraints").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. `/obj/item/handcuffs/cable` and subtypes (7 types)

- **Aurora**: `/obj/item/handcuffs/cable` + subtypes -- code/game/objects/items/weapons/handcuffs.dm
  icon: icons/obj/handcuffs.dmi -- icon_state: `cablecuff`
- **Serenity**: equivalent family -- code/game/objects/items/weapons/handcuffs.dm
  icon: icons/obj/items.dmi -- icon_state: `cuff_white`
- Subtypes covered: `/blue`, `/cyan`, `/green`, `/orange`, `/pink`, `/white`, `/yellow`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 7. handcuffs

- **Aurora**: `/obj/item/handcuffs/cyborg` -- code/game/objects/items/weapons/handcuffs.dm
  name: handcuffs -- icon: icons/obj/handcuffs.dmi -- icon_state: `handcuff`
- **Serenity**: `/obj/item/weapon/handcuffs/cyborg` -- code/game/objects/items/weapons/handcuffs.dm
  name: handcuffs -- icon: icons/obj/items.dmi -- icon_state: `handcuff`
- Confidence: HIGH -- identical type path structure and identical name ("handcuffs").

#### 8. legcuffs

- **Aurora**: `/obj/item/handcuffs/legcuffs` -- code/game/objects/items/weapons/handcuffs.dm
  name: legcuffs -- icon: icons/obj/handcuffs.dmi -- icon_state: `legcuff`
- **Serenity**: `/obj/item/weapon/handcuffs/legcuffs` -- code/game/objects/items/weapons/legcuffs.dm
  name: legcuffs -- icon: icons/obj/items.dmi -- icon_state: `handcuff`
- Confidence: HIGH -- identical type path structure and identical name ("legcuffs").

#### 9. knife blade

- **Aurora**: `/obj/item/material/butterflyblade` -- code/game/objects/items/weapons/improvised_components.dm
  name: knife blade -- icon: icons/obj/weapons_build.dmi -- icon_state: `butterfly2`
- **Serenity**: `/obj/item/weapon/material/butterflyblade` -- code/game/objects/items/weapons/improvised_components.dm
  name: knife blade -- icon: icons/obj/buildingobject.dmi -- icon_state: `butterfly2`
- Confidence: HIGH -- identical type path structure and identical name ("knife blade").

#### 10. harpoon

- **Aurora**: `/obj/item/material/harpoon` -- code/game/objects/items/weapons/material/misc.dm
  name: harpoon -- icon: icons/obj/weapons.dmi -- icon_state: `harpoon`
- **Serenity**: `/obj/item/weapon/material/harpoon` -- code/game/objects/items/weapons/material/misc.dm
  name: harpoon -- icon: _(unset -- inherited/default)_ -- icon_state: `harpoon`
- Confidence: HIGH -- identical type path structure and identical name ("harpoon").

#### 11. machete

- **Aurora**: `/obj/item/material/hatchet/machete` -- code/game/objects/items/weapons/material/misc.dm
  name: machete -- icon: icons/obj/item/melee/machete.dmi -- icon_state: `machete`
- **Serenity**: `/obj/item/weapon/material/hatchet/machete` -- code/game/objects/items/weapons/material/misc.dm
  name: machete -- icon: icons/obj/weapons.dmi -- icon_state: `machete`
- Confidence: HIGH -- identical type path structure and identical name ("machete").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 12. deluxe machete

- **Aurora**: `/obj/item/material/hatchet/machete/deluxe` -- code/game/objects/items/weapons/material/misc.dm
  name: deluxe machete -- icon: icons/obj/item/melee/machete.dmi -- icon_state: `machetedx`
- **Serenity**: `/obj/item/weapon/material/hatchet/machete/deluxe` -- code/game/objects/items/weapons/material/misc.dm
  name: deluxe machete -- icon: icons/obj/weapons.dmi -- icon_state: `machetedx`
- Confidence: HIGH -- identical type path structure and identical name ("deluxe machete").

#### 13. boot knife

- **Aurora**: `/obj/item/material/kitchen/utensil/knife/boot` -- code/game/objects/items/weapons/material/kitchen.dm
  name: boot knife -- icon: icons/obj/weapons.dmi -- icon_state: `tacknife`
- **Serenity**: `/obj/item/weapon/material/kitchen/utensil/knife/boot` -- code/game/objects/items/weapons/material/kitchen.dm
  name: small knife -- icon: icons/obj/weapons.dmi -- icon_state: `pocketknife_open`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "boot knife" / Serenity: "small knife") -- verify these are truly the same item before swapping.

#### 14. knife

- **Aurora**: `/obj/item/material/kitchen/utensil/knife/plastic` -- code/game/objects/items/weapons/material/kitchen.dm
  name: knife -- icon: icons/obj/kitchen.dmi -- icon_state: `plastic_knife`
- **Serenity**: `/obj/item/weapon/material/kitchen/utensil/knife/plastic` -- code/game/objects/items/weapons/material/kitchen.dm
  name: knife -- icon: icons/obj/kitchen.dmi -- icon_state: `knife`
- Confidence: HIGH -- identical type path structure and identical name ("knife").

#### 15. ritual knife

- **Aurora**: `/obj/item/material/knife/ritual` -- code/game/objects/items/weapons/material/knives.dm
  name: ritual knife -- icon: icons/obj/item/material/knife/ritual.dmi -- icon_state: `render`
- **Serenity**: `/obj/item/weapon/material/knife/ritual` -- code/game/objects/items/weapons/material/knives.dm
  name: ritual knife -- icon: icons/obj/wizard.dmi -- icon_state: `render`
- Confidence: HIGH -- identical type path structure and identical name ("ritual knife").

#### 16. scythe

- **Aurora**: `/obj/item/material/scythe` -- code/game/objects/items/weapons/material/misc.dm
  name: scythe -- icon: icons/obj/weapons.dmi -- icon_state: `scythe`
- **Serenity**: `/obj/item/weapon/material/scythe` -- code/game/objects/items/weapons/material/misc.dm
  name: scythe -- icon: _(unset -- inherited/default)_ -- icon_state: `scythe0`
- Confidence: HIGH -- identical type path structure and identical name ("scythe").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 17. shuriken

- **Aurora**: `/obj/item/material/star` -- code/game/objects/items/weapons/material/thrown.dm
  name: shuriken -- icon: icons/obj/weapons.dmi -- icon_state: `star`
- **Serenity**: `/obj/item/weapon/material/star` -- code/game/objects/items/weapons/material/thrown.dm
  name: shuriken -- icon: _(unset -- inherited/default)_ -- icon_state: `star`
- Confidence: HIGH -- identical type path structure and identical name ("shuriken").

#### 18. claymore

- **Aurora**: `/obj/item/material/sword` -- code/game/objects/items/weapons/material/swords.dm
  name: claymore -- icon: icons/obj/sword.dmi -- icon_state: `claymore`
- **Serenity**: `/obj/item/weapon/material/sword` -- code/game/objects/items/weapons/material/swords.dm
  name: claymore -- icon: _(unset -- inherited/default)_ -- icon_state: `claymore`
- Confidence: HIGH -- identical type path structure and identical name ("claymore").

#### 19. katana

- **Aurora**: `/obj/item/material/sword/katana` -- code/game/objects/items/weapons/material/swords.dm
  name: katana -- icon: icons/obj/sword.dmi -- icon_state: `katana`
- **Serenity**: `/obj/item/weapon/material/sword/katana` -- code/game/objects/items/weapons/material/swords.dm
  name: katana -- icon: _(unset -- inherited/default)_ -- icon_state: `katana`
- Confidence: HIGH -- identical type path structure and identical name ("katana").

#### 20. longsword

- **Aurora**: `/obj/item/material/sword/longsword` -- code/game/objects/items/weapons/material/swords.dm
  name: longsword -- icon: icons/obj/sword.dmi -- icon_state: `longsword`
- **Serenity**: `/obj/item/weapon/material/sword/longsword` -- code/game/objects/items/weapons/material/swords.dm
  name: steel longsword -- icon: _(unset -- inherited/default)_ -- icon_state: `longsword`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 21. sabre

- **Aurora**: `/obj/item/material/sword/sabre` -- code/game/objects/items/weapons/material/swords.dm
  name: sabre -- icon: icons/obj/sword.dmi -- icon_state: `sabre`
- **Serenity**: `/obj/item/weapon/material/sword/sabre` -- code/game/objects/items/weapons/material/swords.dm
  name: sabre -- icon: _(unset -- inherited/default)_ -- icon_state: `sabre`
- Confidence: HIGH -- identical type path structure and identical name ("sabre").

#### 22. fire axe

- **Aurora**: `/obj/item/material/twohanded/fireaxe` -- code/game/objects/items/weapons/material/twohanded.dm
  name: fire axe -- icon: icons/obj/weapons.dmi -- icon_state: `fireaxe0`
- **Serenity**: `/obj/item/weapon/material/twohanded/fireaxe` -- code/game/objects/items/weapons/material/twohanded.dm
  name: fire axe -- icon: _(unset -- inherited/default)_ -- icon_state: `fireaxe0`
- Confidence: HIGH -- identical type path structure and identical name ("fire axe").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 23. spear

- **Aurora**: `/obj/item/material/twohanded/spear` -- code/game/objects/items/weapons/material/twohanded.dm
  name: spear -- icon: icons/obj/weapons.dmi -- icon_state: `spearglass0`
- **Serenity**: `/obj/item/weapon/material/twohanded/spear` -- code/game/objects/items/weapons/material/twohanded.dm
  name: spear -- icon: _(unset -- inherited/default)_ -- icon_state: `spearglass0`
- Confidence: HIGH -- identical type path structure and identical name ("spear").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 24. stunbaton

- **Aurora**: `/obj/item/melee/baton` -- code/game/objects/items/weapons/stunbaton.dm
  name: stunbaton -- icon: icons/obj/weapons.dmi -- icon_state: `stunbaton`
- **Serenity**: `/obj/item/weapon/melee/baton` -- code/game/objects/items/weapons/stunbaton.dm
  name: stunbaton -- icon: _(unset -- inherited/default)_ -- icon_state: `stunbaton`
- Confidence: HIGH -- identical type path structure and identical name ("stunbaton").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 25. stunprod

- **Aurora**: `/obj/item/melee/baton/cattleprod` -- code/game/objects/items/weapons/stunbaton.dm
  name: stunprod -- icon: icons/obj/weapons.dmi -- icon_state: `stunprod_nocell`
- **Serenity**: `/obj/item/weapon/melee/baton/cattleprod` -- code/game/objects/items/weapons/stunbaton.dm
  name: stunprod -- icon: _(unset -- inherited/default)_ -- icon_state: `stunprod_nocell`
- Confidence: HIGH -- identical type path structure and identical name ("stunprod").

#### 26. stunbaton

- **Aurora**: `/obj/item/melee/baton/robot` -- code/game/objects/items/weapons/stunbaton.dm
  name: stunbaton -- icon: icons/obj/weapons.dmi -- icon_state: `stunbaton`
- **Serenity**: `/obj/item/weapon/melee/baton/robot` -- code/game/objects/items/weapons/stunbaton.dm
  name: stunbaton -- icon: _(unset -- inherited/default)_ -- icon_state: `stunbaton`
- Confidence: HIGH -- identical type path structure and identical name ("stunbaton").

#### 27. energy axe

- **Aurora**: `/obj/item/melee/energy/axe` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy axe -- icon: icons/obj/weapons.dmi -- icon_state: `axe0`
- **Serenity**: `/obj/item/weapon/melee/energy/axe` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy axe -- icon: _(unset -- inherited/default)_ -- icon_state: `axe0`
- Confidence: HIGH -- identical type path structure and identical name ("energy axe").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 28. energy blade

- **Aurora**: `/obj/item/melee/energy/blade` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy blade -- icon: icons/obj/weapons.dmi -- icon_state: `blade`
- **Serenity**: `/obj/item/weapon/melee/energy/blade` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy blade -- icon: _(unset -- inherited/default)_ -- icon_state: `blade`
- Confidence: HIGH -- identical type path structure and identical name ("energy blade").

#### 29. energy sword

- **Aurora**: `/obj/item/melee/energy/sword` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy sword -- icon: icons/obj/weapons.dmi -- icon_state: `sword0`
- **Serenity**: `/obj/item/weapon/melee/energy/sword` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy sword -- icon: _(unset -- inherited/default)_ -- icon_state: `sword0`
- Confidence: HIGH -- identical type path structure and identical name ("energy sword").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 30. energy cutlass

- **Aurora**: `/obj/item/melee/energy/sword/pirate` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy cutlass -- icon: icons/obj/weapons.dmi -- icon_state: `cutlass0`
- **Serenity**: `/obj/item/weapon/melee/energy/sword/pirate` -- code/game/objects/items/weapons/melee/energy.dm
  name: energy cutlass -- icon: _(unset -- inherited/default)_ -- icon_state: `cutlass0`
- Confidence: HIGH -- identical type path structure and identical name ("energy cutlass").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 31. telescopic baton

- **Aurora**: `/obj/item/melee/telebaton` -- code/game/objects/items/weapons/swords_axes_etc.dm
  name: telescopic baton -- icon: icons/obj/item/melee/telebaton.dmi -- icon_state: `telebaton_0`
- **Serenity**: `/obj/item/weapon/melee/telebaton` -- code/game/objects/items/weapons/swords_axes_etc.dm
  name: telescopic baton -- icon: icons/obj/weapons.dmi -- icon_state: `telebaton_0`
- Confidence: HIGH -- identical type path structure and identical name ("telescopic baton").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 32. whip

- **Aurora**: `/obj/item/melee/whip` -- code/game/objects/items/weapons/melee/misc.dm
  name: whip -- icon: icons/obj/weapons.dmi -- icon_state: `whip`
- **Serenity**: `/obj/item/weapon/melee/whip` -- code/game/objects/items/weapons/melee/misc.dm
  name: whip -- icon: _(unset -- inherited/default)_ -- icon_state: `chain`
- Confidence: HIGH -- identical type path structure and identical name ("whip").

#### 33. null rod

- **Aurora**: `/obj/item/nullrod` -- code/game/objects/items/weapons/chaplain_items.dm
  name: null rod -- icon: icons/obj/weapons.dmi -- icon_state: `nullrod`
- **Serenity**: `/obj/item/weapon/nullrod` -- code/game/objects/items/weapons/weaponry.dm
  name: null rod -- icon: _(unset -- inherited/default)_ -- icon_state: `nullrod`
- Confidence: HIGH -- identical type path structure and identical name ("null rod").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 34. personal shield

- **Aurora**: `/obj/item/personal_shield` -- code/game/objects/items/devices/personal_shield.dm
  name: personal shield -- icon: icons/obj/personal_shield.dmi -- icon_state: `personal_shield`
- **Serenity**: `/obj/item/device/personal_shield` -- code/game/objects/items/devices/personal_shield.dm
  name: personal shield -- icon: icons/obj/device.dmi -- icon_state: `batterer`
- Confidence: HIGH -- identical type path structure and identical name ("personal shield").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 35. selfmade shield

- **Aurora**: `/obj/item/shield/buckler` -- code/game/objects/items/weapons/shields.dm
  name: selfmade shield -- icon: icons/obj/square_shield.dmi -- icon_state: `square_buckler`
- **Serenity**: `/obj/item/weapon/shield/buckler` -- code/game/objects/items/weapons/shields.dm
  name: buckler -- icon: icons/obj/weapons.dmi -- icon_state: `buckler`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "selfmade shield" / Serenity: "buckler") -- verify these are truly the same item before swapping.

#### 36. foam dart crossbow

- **Aurora**: `/obj/item/toy/crossbow` -- code/game/objects/items/toys.dm
  name: foam dart crossbow -- icon: icons/obj/guns/crossbow.dmi -- icon_state: `crossbow`
- **Serenity**: `/obj/item/toy/crossbow` -- code/game/objects/items/toys.dm
  name: foam dart crossbow -- icon: icons/obj/gun.dmi -- icon_state: `crossbow`
- Confidence: HIGH -- identical type path structure and identical name ("foam dart crossbow").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 37. foam sword

- **Aurora**: `/obj/item/toy/cultsword` -- code/game/objects/items/toys.dm
  name: foam sword -- icon: icons/obj/sword_64.dmi -- icon_state: `cultblade`
- **Serenity**: `/obj/item/toy/cultsword` -- code/game/objects/items/toys.dm
  name: foam sword -- icon: icons/obj/weapons.dmi -- icon_state: `cultblade`
- Confidence: HIGH -- identical type path structure and identical name ("foam sword").

#### 38. replica katana

- **Aurora**: `/obj/item/toy/katana` -- code/game/objects/items/toys.dm
  name: replica katana -- icon: icons/obj/sword.dmi -- icon_state: `katana`
- **Serenity**: `/obj/item/toy/katana` -- code/game/objects/items/toys.dm
  name: replica katana -- icon: icons/obj/weapons.dmi -- icon_state: `katana`
- Confidence: HIGH -- identical type path structure and identical name ("replica katana").

---

## Devices (53)

#### 1. intelliCard

- **Aurora**: `/obj/item/aicard` -- code/game/objects/items/devices/aicard.dm
  name: intelliCard -- icon: icons/obj/pai.dmi -- icon_state: `aicard`
- **Serenity**: `/obj/item/weapon/aicard` -- code/game/objects/items/devices/aicard.dm
  name: inteliCard -- icon: icons/obj/pda.dmi -- icon_state: `aicard`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. autopsy scanner

- **Aurora**: `/obj/item/autopsy_scanner` -- code/game/objects/items/weapons/autopsy.dm
  name: autopsy scanner -- icon: icons/obj/item/scanner.dmi -- icon_state: `autopsy`
- **Serenity**: `/obj/item/weapon/autopsy_scanner` -- code/game/objects/items/weapons/autopsy.dm
  name: autopsy scanner -- icon: icons/obj/autopsy_scanner.dmi -- icon_state: _(empty string)_
- Confidence: HIGH -- identical type path structure and identical name ("autopsy scanner").

#### 3. mind batterer

- **Aurora**: `/obj/item/batterer` -- code/game/objects/items/devices/traitordevices.dm
  name: mind batterer -- icon: icons/obj/item/batterer.dmi -- icon_state: `batterer`
- **Serenity**: `/obj/item/device/batterer` -- code/game/objects/items/devices/traitordevices.dm
  name: mind batterer -- icon: icons/obj/device.dmi -- icon_state: `batterer`
- Confidence: HIGH -- identical type path structure and identical name ("mind batterer").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 4. binoculars

- **Aurora**: `/obj/item/binoculars` -- code/game/objects/items/devices/binoculars.dm
  name: binoculars -- icon: icons/obj/item/binoculars.dmi -- icon_state: `binoculars`
- **Serenity**: `/obj/item/device/binoculars` -- code/game/objects/items/devices/binoculars.dm
  name: binoculars -- icon: icons/obj/device.dmi -- icon_state: `binoculars`
- Confidence: HIGH -- identical type path structure and identical name ("binoculars").

#### 5. chameleon projector

- **Aurora**: `/obj/item/chameleon` -- code/game/objects/items/devices/chameleonproj.dm
  name: chameleon projector -- icon: icons/obj/item/chameleon.dmi -- icon_state: `shield0`
- **Serenity**: `/obj/item/device/chameleon` -- code/game/objects/items/devices/chameleonproj.dm
  name: chameleon projector -- icon: icons/obj/device.dmi -- icon_state: `shield0`
- Confidence: HIGH -- identical type path structure and identical name ("chameleon projector").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 6. item

- **Aurora**: `/obj/item/device` -- code/game/objects/items.dm
  name: item -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/device` -- code/game/objects/items.dm
  name: item -- icon: icons/obj/device.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("item").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. dociler

- **Aurora**: `/obj/item/dociler` -- code/game/objects/items/devices/dociler.dm
  name: dociler -- icon: icons/obj/guns/decloner.dmi -- icon_state: `decloner`
- **Serenity**: `/obj/item/device/dociler` -- code/game/objects/items/devices/dociler.dm
  name: dociler -- icon: icons/obj/device.dmi -- icon_state: `animal_tagger1`
- Confidence: HIGH -- identical type path structure and identical name ("dociler").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 8. flash

- **Aurora**: `/obj/item/flash` -- code/game/objects/items/devices/flash.dm
  name: flash -- icon: icons/obj/item/flash.dmi -- icon_state: `flash`
- **Serenity**: `/obj/item/device/flash` -- code/game/objects/items/devices/flash.dm
  name: flash -- icon: icons/obj/device.dmi -- icon_state: `flash`
- Confidence: HIGH -- identical type path structure and identical name ("flash").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 9. synthetic flash

- **Aurora**: `/obj/item/flash/synthetic` -- code/game/objects/items/devices/flash.dm
  name: synthetic flash -- icon: icons/obj/item/flash.dmi -- icon_state: `sflash`
- **Serenity**: `/obj/item/device/flash/synthetic` -- code/game/objects/items/devices/flash.dm
  name: modified flash -- icon: icons/obj/device.dmi -- icon_state: `sflash`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "synthetic flash" / Serenity: "modified flash") -- verify these are truly the same item before swapping.

#### 10. glowing slime extract

- **Aurora**: `/obj/item/flashlight/slime` -- code/game/objects/items/devices/lighting/flashlight.dm
  name: glowing slime extract -- icon: icons/mob/npc/slimes.dmi -- icon_state: `yellow slime extract`
- **Serenity**: `/obj/item/device/flashlight/slime` -- code/game/objects/items/devices/flashlight.dm
  name: glowing slime extract -- icon: icons/obj/lighting.dmi -- icon_state: `floor1`
- Confidence: HIGH -- identical type path structure and identical name ("glowing slime extract").

#### 11. geiger counter

- **Aurora**: `/obj/item/geiger` -- code/game/objects/items/devices/geiger.dm
  name: geiger counter -- icon: icons/obj/item/scanner.dmi -- icon_state: `geiger_off`
- **Serenity**: `/obj/item/device/geiger` -- code/game/objects/items/devices/geiger.dm
  name: geiger counter -- icon: icons/obj/device.dmi -- icon_state: `geiger_off`
- Confidence: HIGH -- identical type path structure and identical name ("geiger counter").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 12. hailer

- **Aurora**: `/obj/item/hailer` -- code/game/objects/items/devices/whistle.dm
  name: hailer -- icon: icons/obj/item/hailer.dmi -- icon_state: `voice0`
- **Serenity**: `/obj/item/device/hailer` -- code/game/objects/items/devices/whistle.dm
  name: hailer -- icon: icons/obj/device.dmi -- icon_state: `voice0`
- Confidence: HIGH -- identical type path structure and identical name ("hailer").

#### 13. warrant projector

- **Aurora**: `/obj/item/holowarrant` -- code/game/objects/items/devices/holowarrant.dm
  name: warrant projector -- icon: icons/obj/holowarrant.dmi -- icon_state: `holowarrant`
- **Serenity**: `/obj/item/device/holowarrant` -- code/game/objects/items/devices/holowarrant.dm
  name: warrant projector -- icon: icons/obj/device.dmi -- icon_state: `holowarrant`
- Confidence: HIGH -- identical type path structure and identical name ("warrant projector").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 14. light replacer

- **Aurora**: `/obj/item/lightreplacer` -- code/game/objects/items/devices/lightreplacer.dm
  name: light replacer -- icon: icons/obj/janitor.dmi -- icon_state: `lightreplacer`
- **Serenity**: `/obj/item/device/lightreplacer` -- code/game/objects/items/devices/lightreplacer.dm
  name: light replacer -- icon: icons/obj/janitor.dmi -- icon_state: `lightreplacer0`
- Confidence: HIGH -- identical type path structure and identical name ("light replacer").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 15. locator

- **Aurora**: `/obj/item/locator` -- code/game/objects/items/weapons/teleportation.dm
  name: locator -- icon: icons/obj/item/pinpointer.dmi -- icon_state: `pinoff`
- **Serenity**: `/obj/item/weapon/locator` -- code/game/objects/items/weapons/teleportation.dm
  name: locator -- icon: icons/obj/device.dmi -- icon_state: `locator`
- Confidence: HIGH -- identical type path structure and identical name ("locator").

#### 16. mass spectrometer

- **Aurora**: `/obj/item/mass_spectrometer` -- code/game/objects/items/devices/scanners.dm
  name: mass spectrometer -- icon: icons/obj/item/scanner.dmi -- icon_state: `spectrometer`
- **Serenity**: `/obj/item/device/mass_spectrometer` -- code/game/objects/items/devices/scanners.dm
  name: mass spectrometer -- icon: icons/obj/device.dmi -- icon_state: `spectrometer`
- Confidence: HIGH -- identical type path structure and identical name ("mass spectrometer").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 17. advanced mass spectrometer

- **Aurora**: `/obj/item/mass_spectrometer/adv` -- code/game/objects/items/devices/scanners.dm
  name: advanced mass spectrometer -- icon: icons/obj/item/scanner.dmi -- icon_state: `spectrometer_adv`
- **Serenity**: `/obj/item/device/mass_spectrometer/adv` -- code/game/objects/items/devices/scanners.dm
  name: advanced mass spectrometer -- icon: icons/obj/device.dmi -- icon_state: `adv_spectrometer`
- Confidence: HIGH -- identical type path structure and identical name ("advanced mass spectrometer").

#### 18. megaphone

- **Aurora**: `/obj/item/megaphone` -- code/game/objects/items/devices/megaphone.dm
  name: megaphone -- icon: icons/obj/item/megaphone.dmi -- icon_state: `megaphone`
- **Serenity**: `/obj/item/device/megaphone` -- code/game/objects/items/devices/megaphone.dm
  name: megaphone -- icon: icons/obj/device.dmi -- icon_state: `megaphone`
- Confidence: HIGH -- identical type path structure and identical name ("megaphone").

#### 19. multitool

- **Aurora**: `/obj/item/multitool` -- code/game/objects/items/devices/multitool.dm
  name: multitool -- icon: icons/obj/item/multitool.dmi -- icon_state: `multitool`
- **Serenity**: `/obj/item/device/multitool` -- code/game/objects/items/devices/multitool.dm
  name: multitool -- icon: icons/obj/device.dmi -- icon_state: `multitool`
- Confidence: HIGH -- identical type path structure and identical name ("multitool").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 20. multitool

- **Aurora**: `/obj/item/multitool/hacktool` -- code/game/objects/items/devices/hacktool.dm
  name: multitool -- icon: icons/obj/item/multitool.dmi -- icon_state: `multitool`
- **Serenity**: `/obj/item/device/multitool/hacktool` -- code/game/objects/items/devices/hacktool.dm
  name: multitool -- icon: icons/obj/device.dmi -- icon_state: `multitool`
- Confidence: HIGH -- identical type path structure and identical name ("multitool").

#### 21. personal AI device

- **Aurora**: `/obj/item/paicard` -- code/game/objects/items/devices/paicard.dm
  name: personal AI device -- icon: icons/obj/pai.dmi -- icon_state: `pai`
- **Serenity**: `/obj/item/device/paicard` -- code/game/objects/items/devices/paicard.dm
  name: personal AI device -- icon: icons/obj/pda.dmi -- icon_state: `pai`
- Confidence: HIGH -- identical type path structure and identical name ("personal AI device").

#### 22. pipe painter

- **Aurora**: `/obj/item/pipe_painter` -- code/game/objects/items/devices/paint_sprayer.dm
  name: pipe painter -- icon: icons/obj/item/paint_sprayer.dmi -- icon_state: `pipe_painter`
- **Serenity**: `/obj/item/device/pipe_painter` -- code/game/objects/items/devices/pipe_painter.dm
  name: pipe painter -- icon: icons/obj/device.dmi -- icon_state: `pipainter`
- Confidence: HIGH -- identical type path structure and identical name ("pipe painter").

#### 23. power sink

- **Aurora**: `/obj/item/powersink` -- code/game/objects/items/devices/powersink.dm
  name: power sink -- icon: icons/obj/item/powersink.dmi -- icon_state: `powersink0`
- **Serenity**: `/obj/item/device/powersink` -- code/game/objects/items/devices/powersink.dm
  name: power sink -- icon: icons/obj/device.dmi -- icon_state: `powersink0`
- Confidence: HIGH -- identical type path structure and identical name ("power sink").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 24. price scanner

- **Aurora**: `/obj/item/price_scanner` -- code/game/objects/items/devices/scanners.dm
  name: price scanner -- icon: icons/obj/item/scanner.dmi -- icon_state: `price_scanner`
- **Serenity**: `/obj/item/device/price_scanner` -- code/game/objects/items/devices/scanners.dm
  name: price scanner -- icon: icons/obj/device.dmi -- icon_state: `price_scanner`
- Confidence: HIGH -- identical type path structure and identical name ("price scanner").

#### 25. radio headset

- **Aurora**: `/obj/item/radio/headset` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `headset`
- **Serenity**: `/obj/item/device/radio/headset` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/radio.dmi -- icon_state: `headset`
- Confidence: HIGH -- identical type path structure and identical name ("radio headset").

#### 26. radio headset

- **Aurora**: `/obj/item/radio/headset/binary` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `headset`
- **Serenity**: `/obj/item/device/radio/headset/binary` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/radio.dmi -- icon_state: `headset`
- Confidence: HIGH -- identical type path structure and identical name ("radio headset").

#### 27. emergency response team radio headset

- **Aurora**: `/obj/item/radio/headset/ert` -- code/game/objects/items/devices/radio/headset.dm
  name: emergency response team radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `com_headset`
- **Serenity**: `/obj/item/device/radio/headset/ert` -- code/game/objects/items/devices/radio/headset.dm
  name: emergency response team radio headset -- icon: icons/obj/radio.dmi -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("emergency response team radio headset").

#### 28. captain's headset

- **Aurora**: `/obj/item/radio/headset/heads/captain` -- code/game/objects/items/devices/radio/headset.dm
  name: captain's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `cap_headset`
- **Serenity**: `/obj/item/device/radio/headset/heads/captain` -- code/game/objects/items/devices/radio/headset.dm
  name: captain's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("captain's headset").

#### 29. chief engineer's headset

- **Aurora**: `/obj/item/radio/headset/heads/ce` -- code/game/objects/items/devices/radio/headset.dm
  name: chief engineer's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `ce_headset`
- **Serenity**: `/obj/item/device/radio/headset/heads/ce` -- code/game/objects/items/devices/radio/headset.dm
  name: chief engineer's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("chief engineer's headset").

#### 30. chief medical officer's headset

- **Aurora**: `/obj/item/radio/headset/heads/cmo` -- code/game/objects/items/devices/radio/headset.dm
  name: chief medical officer's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `cmo_headset`
- **Serenity**: `/obj/item/device/radio/headset/heads/cmo` -- code/game/objects/items/devices/radio/headset.dm
  name: chief medical officer's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("chief medical officer's headset").

#### 31. head of security's headset

- **Aurora**: `/obj/item/radio/headset/heads/hos` -- code/game/objects/items/devices/radio/headset.dm
  name: head of security's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `hos_headset`
- **Serenity**: `/obj/item/device/radio/headset/heads/hos` -- code/game/objects/items/devices/radio/headset.dm
  name: head of security's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("head of security's headset").

#### 32. research director's headset

- **Aurora**: `/obj/item/radio/headset/heads/rd` -- code/game/objects/items/devices/radio/headset.dm
  name: research director's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `rd_headset`
- **Serenity**: `/obj/item/device/radio/headset/heads/rd` -- code/game/objects/items/devices/radio/headset.dm
  name: research director's headset -- icon: _(unset -- inherited/default)_ -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("research director's headset").

#### 33. supply radio headset

- **Aurora**: `/obj/item/radio/headset/headset_cargo` -- code/game/objects/items/devices/radio/headset.dm
  name: supply radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `cargo_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_cargo` -- code/game/objects/items/devices/radio/headset.dm
  name: supply radio headset -- icon: icons/obj/radio.dmi -- icon_state: `cargo_headset`
- Confidence: HIGH -- identical type path structure and identical name ("supply radio headset").

#### 34. command radio headset

- **Aurora**: `/obj/item/radio/headset/headset_com` -- code/game/objects/items/devices/radio/headset.dm
  name: command radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `com_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_com` -- code/game/objects/items/devices/radio/headset.dm
  name: command radio headset -- icon: icons/obj/radio.dmi -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("command radio headset").

#### 35. engineering radio headset

- **Aurora**: `/obj/item/radio/headset/headset_eng` -- code/game/objects/items/devices/radio/headset.dm
  name: engineering radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `eng_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_eng` -- code/game/objects/items/devices/radio/headset.dm
  name: engineering radio headset -- icon: icons/obj/radio.dmi -- icon_state: `eng_headset`
- Confidence: HIGH -- identical type path structure and identical name ("engineering radio headset").

#### 36. medical radio headset

- **Aurora**: `/obj/item/radio/headset/headset_med` -- code/game/objects/items/devices/radio/headset.dm
  name: medical radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `med_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_med` -- code/game/objects/items/devices/radio/headset.dm
  name: medical radio headset -- icon: icons/obj/radio.dmi -- icon_state: `med_headset`
- Confidence: HIGH -- identical type path structure and identical name ("medical radio headset").

#### 37. medical research radio headset

- **Aurora**: `/obj/item/radio/headset/headset_medsci` -- code/game/objects/items/devices/radio/headset.dm
  name: medical research radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `medsci_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_medsci` -- code/game/objects/items/devices/radio/headset.dm
  name: medical research radio headset -- icon: icons/obj/radio.dmi -- icon_state: `med_headset`
- Confidence: HIGH -- identical type path structure and identical name ("medical research radio headset").

#### 38. robotics radio headset

- **Aurora**: `/obj/item/radio/headset/headset_rob` -- code/game/objects/items/devices/radio/headset.dm
  name: robotics radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `rob_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_rob` -- code/game/objects/items/devices/radio/headset.dm
  name: robotics radio headset -- icon: icons/obj/radio.dmi -- icon_state: `rob_headset`
- Confidence: HIGH -- identical type path structure and identical name ("robotics radio headset").

#### 39. science radio headset

- **Aurora**: `/obj/item/radio/headset/headset_sci` -- code/game/objects/items/devices/radio/headset.dm
  name: science radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `sci_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_sci` -- code/game/objects/items/devices/radio/headset.dm
  name: science radio headset -- icon: icons/obj/radio.dmi -- icon_state: `com_headset`
- Confidence: HIGH -- identical type path structure and identical name ("science radio headset").

#### 40. security radio headset

- **Aurora**: `/obj/item/radio/headset/headset_sec` -- code/game/objects/items/devices/radio/headset.dm
  name: security radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `sec_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_sec` -- code/game/objects/items/devices/radio/headset.dm
  name: security radio headset -- icon: icons/obj/radio.dmi -- icon_state: `sec_headset`
- Confidence: HIGH -- identical type path structure and identical name ("security radio headset").

#### 41. service radio headset

- **Aurora**: `/obj/item/radio/headset/headset_service` -- code/game/objects/items/devices/radio/headset.dm
  name: service radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `srv_headset`
- **Serenity**: `/obj/item/device/radio/headset/headset_service` -- code/game/objects/items/devices/radio/headset.dm
  name: service radio headset -- icon: icons/obj/radio.dmi -- icon_state: `srv_headset`
- Confidence: HIGH -- identical type path structure and identical name ("service radio headset").

#### 42. radio headset

- **Aurora**: `/obj/item/radio/headset/raider` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `syn_headset`
- **Serenity**: `/obj/item/device/radio/headset/raider` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/radio.dmi -- icon_state: `headset`
- Confidence: HIGH -- identical type path structure and identical name ("radio headset").

#### 43. military headset

- **Aurora**: `/obj/item/radio/headset/syndicate` -- code/game/objects/items/devices/radio/headset.dm
  name: military headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `syn_headset`
- **Serenity**: `/obj/item/device/radio/headset/syndicate` -- code/game/objects/items/devices/radio/headset.dm
  name: radio headset -- icon: icons/obj/radio.dmi -- icon_state: `headset`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 44. radio headset

- **Aurora**: `/obj/item/radio/headset/uplink` -- code/game/objects/items/devices/uplink.dm
  name: radio headset -- icon: icons/obj/item/radio/headset.dmi -- icon_state: `headset`
- **Serenity**: `/obj/item/device/radio/headset/uplink` -- code/game/objects/items/devices/uplink.dm
  name: radio headset -- icon: icons/obj/radio.dmi -- icon_state: `headset`
- Confidence: HIGH -- identical type path structure and identical name ("radio headset").

#### 45. phone

- **Aurora**: `/obj/item/radio/phone` -- code/game/objects/items/devices/radio/radio.dm
  name: phone -- icon: icons/obj/radio.dmi -- icon_state: `red_phone`
- **Serenity**: `/obj/item/device/radio/phone` -- code/game/objects/items/devices/radio/radio.dm
  name: phone -- icon: icons/obj/items.dmi -- icon_state: `red_phone`
- Confidence: HIGH -- identical type path structure and identical name ("phone").

#### 46. reagent scanner

- **Aurora**: `/obj/item/reagent_scanner` -- code/game/objects/items/devices/scanners.dm
  name: reagent scanner -- icon: icons/obj/item/scanner.dmi -- icon_state: `reagent_scanner`
- **Serenity**: `/obj/item/device/reagent_scanner` -- code/game/objects/items/devices/scanners.dm
  name: reagent scanner -- icon: icons/obj/device.dmi -- icon_state: `spectrometer`
- Confidence: HIGH -- identical type path structure and identical name ("reagent scanner").

#### 47. advanced reagent scanner

- **Aurora**: `/obj/item/reagent_scanner/adv` -- code/game/objects/items/devices/scanners.dm
  name: advanced reagent scanner -- icon: icons/obj/item/scanner.dmi -- icon_state: `reagent_scanner_adv`
- **Serenity**: `/obj/item/device/reagent_scanner/adv` -- code/game/objects/items/devices/scanners.dm
  name: advanced reagent scanner -- icon: icons/obj/device.dmi -- icon_state: `adv_spectrometer`
- Confidence: HIGH -- identical type path structure and identical name ("advanced reagent scanner").

#### 48. defibrillator paddles

- **Aurora**: `/obj/item/shockpaddles/standalone/traitor` -- code/game/objects/items/defib.dm
  name: defibrillator paddles -- icon: icons/obj/defibrillator.dmi -- icon_state: `defibpaddles0`
- **Serenity**: `/obj/item/weapon/shockpaddles/standalone/traitor` -- code/game/objects/items/weapons/defib.dm
  name: defibrillator paddles -- icon: icons/obj/weapons.dmi -- icon_state: `defibpaddles0`
- Confidence: HIGH -- identical type path structure and identical name ("defibrillator paddles").

#### 49. slime scanner

- **Aurora**: `/obj/item/slime_scanner` -- code/game/objects/items/devices/scanners.dm
  name: slime scanner -- icon: icons/obj/item/scanner.dmi -- icon_state: `slime_scanner`
- **Serenity**: `/obj/item/device/slime_scanner` -- code/game/objects/items/devices/scanners.dm
  name: xenolife scanner -- icon: icons/obj/device.dmi -- icon_state: `xenobio`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 50. \improper PDA

- **Aurora**: `/obj/item/spy_monitor` -- code/game/objects/items/devices/spy_bug.dm
  name: \improper PDA -- icon: icons/obj/modular_computers/pda.dmi -- icon_state: `pda`
- **Serenity**: `/obj/item/device/spy_monitor` -- code/game/objects/items/devices/spy_bug.dm
  name: \improper PDA -- icon: icons/obj/pda.dmi -- icon_state: `pda`
- Confidence: HIGH -- identical type path structure and identical name ("\improper PDA").

#### 51. \improper T-ray scanner

- **Aurora**: `/obj/item/t_scanner` -- code/game/objects/items/devices/t_scanner.dm
  name: \improper T-ray scanner -- icon: icons/obj/item/scanner.dmi -- icon_state: `t-ray0`
- **Serenity**: `/obj/item/device/t_scanner` -- code/game/objects/items/devices/t_scanner.dm
  name: \improper T-ray scanner -- icon: icons/obj/device.dmi -- icon_state: `t-ray0`
- Confidence: HIGH -- identical type path structure and identical name ("\improper T-ray scanner").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 52. universal recorder

- **Aurora**: `/obj/item/taperecorder` -- code/game/objects/items/devices/taperecorder.dm
  name: universal recorder -- icon: icons/obj/item/taperecorder.dmi -- icon_state: `taperecorder_idle`
- **Serenity**: `/obj/item/device/taperecorder` -- code/game/objects/items/devices/taperecorder.dm
  name: universal recorder -- icon: icons/obj/device.dmi -- icon_state: `taperecorder`
- Confidence: HIGH -- identical type path structure and identical name ("universal recorder").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 53. press camera drone

- **Aurora**: `/obj/item/tvcamera` -- code/game/objects/items/devices/tvcamera.dm
  name: press camera drone -- icon: icons/obj/item/tvcamera.dmi -- icon_state: `camcorder`
- **Serenity**: `/obj/item/device/tvcamera` -- code/game/objects/items/devices/tvcamera.dm
  name: press camera drone -- icon: icons/obj/device.dmi -- icon_state: `camcorder`
- Confidence: HIGH -- identical type path structure and identical name ("press camera drone").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

---

## Storage & Containers (79)

#### 1. backpack

- **Aurora**: `/obj/item/storage/backpack` -- code/game/objects/items/weapons/storage/backpack.dm
  name: backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `backpack`
- **Serenity**: `/obj/item/weapon/storage/backpack` -- code/game/objects/items/weapons/storage/backpack.dm
  name: backpack -- icon: icons/obj/storage.dmi -- icon_state: `backpack`
- Confidence: HIGH -- identical type path structure and identical name ("backpack").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. captain's backpack

- **Aurora**: `/obj/item/storage/backpack/captain` -- code/game/objects/items/weapons/storage/backpack.dm
  name: captain's backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `captainpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/captain` -- code/game/objects/items/weapons/storage/backpack.dm
  name: captain's backpack -- icon: icons/obj/storage.dmi -- icon_state: `captainpack`
- Confidence: HIGH -- identical type path structure and identical name ("captain's backpack").

#### 3. backpack

- **Aurora**: `/obj/item/storage/backpack/chameleon` -- code/modules/clothing/chameleon.dm
  name: backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `backpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/chameleon` -- code/modules/clothing/chameleon.dm
  name: backpack -- icon: icons/obj/storage.dmi -- icon_state: `backpack`
- Confidence: HIGH -- identical type path structure and identical name ("backpack").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 4. trophy rack

- **Aurora**: `/obj/item/storage/backpack/cultpack` -- code/game/objects/items/weapons/storage/backpack.dm
  name: trophy rack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `cultpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/cultpack` -- code/game/objects/items/weapons/storage/backpack.dm
  name: trophy rack -- icon: icons/obj/storage.dmi -- icon_state: `cultpack`
- Confidence: HIGH -- identical type path structure and identical name ("trophy rack").

#### 5. emergency response team backpack

- **Aurora**: `/obj/item/storage/backpack/ert` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `ert_commander`
- **Serenity**: `/obj/item/weapon/storage/backpack/ert` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team backpack -- icon: icons/obj/storage.dmi -- icon_state: `ert_commander`
- Confidence: HIGH -- identical type path structure and identical name ("emergency response team backpack").

#### 6. emergency response team commander backpack

- **Aurora**: `/obj/item/storage/backpack/ert/commander` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team commander backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `ert_commander`
- **Serenity**: `/obj/item/weapon/storage/backpack/ert/commander` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team commander backpack -- icon: icons/obj/storage.dmi -- icon_state: `ert_commander`
- Confidence: HIGH -- identical type path structure and identical name ("emergency response team commander backpack").

#### 7. emergency response team engineer backpack

- **Aurora**: `/obj/item/storage/backpack/ert/engineer` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team engineer backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `ert_engineering`
- **Serenity**: `/obj/item/weapon/storage/backpack/ert/engineer` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team engineer backpack -- icon: icons/obj/storage.dmi -- icon_state: `ert_engineering`
- Confidence: HIGH -- identical type path structure and identical name ("emergency response team engineer backpack").

#### 8. emergency response team medical backpack

- **Aurora**: `/obj/item/storage/backpack/ert/medical` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team medical backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `ert_medical`
- **Serenity**: `/obj/item/weapon/storage/backpack/ert/medical` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team medical backpack -- icon: icons/obj/storage.dmi -- icon_state: `ert_medical`
- Confidence: HIGH -- identical type path structure and identical name ("emergency response team medical backpack").

#### 9. emergency response team security backpack

- **Aurora**: `/obj/item/storage/backpack/ert/security` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team security backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `ert_security`
- **Serenity**: `/obj/item/weapon/storage/backpack/ert/security` -- code/game/objects/items/weapons/storage/backpack.dm
  name: emergency response team security backpack -- icon: icons/obj/storage.dmi -- icon_state: `ert_security`
- Confidence: HIGH -- identical type path structure and identical name ("emergency response team security backpack").

#### 10. portable bluespace pocket

- **Aurora**: `/obj/item/storage/backpack/holding` -- code/game/objects/items/weapons/storage/backpack.dm
  name: portable bluespace pocket -- icon: icons/obj/storage/backpack.dmi -- icon_state: `holdingpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/holding` -- code/game/objects/items/weapons/storage/backpack.dm
  name: bag of holding -- icon: icons/obj/storage.dmi -- icon_state: `holdingpack`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "portable bluespace pocket" / Serenity: "bag of holding") -- verify these are truly the same item before swapping.

#### 11. herbalist's backpack

- **Aurora**: `/obj/item/storage/backpack/hydroponics` -- code/game/objects/items/weapons/storage/backpack.dm
  name: herbalist's backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `hydpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/hydroponics` -- code/game/objects/items/weapons/storage/backpack.dm
  name: herbalist's backpack -- icon: icons/obj/storage.dmi -- icon_state: `hydpack`
- Confidence: HIGH -- identical type path structure and identical name ("herbalist's backpack").

#### 12. industrial backpack

- **Aurora**: `/obj/item/storage/backpack/industrial` -- code/game/objects/items/weapons/storage/backpack.dm
  name: industrial backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `engiepack`
- **Serenity**: `/obj/item/weapon/storage/backpack/industrial` -- code/game/objects/items/weapons/storage/backpack.dm
  name: industrial backpack -- icon: icons/obj/storage.dmi -- icon_state: `engiepack`
- Confidence: HIGH -- identical type path structure and identical name ("industrial backpack").

#### 13. medical backpack

- **Aurora**: `/obj/item/storage/backpack/medic` -- code/game/objects/items/weapons/storage/backpack.dm
  name: medical backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `medicalpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/medic` -- code/game/objects/items/weapons/storage/backpack.dm
  name: medical backpack -- icon: icons/obj/storage.dmi -- icon_state: `medicalpack`
- Confidence: HIGH -- identical type path structure and identical name ("medical backpack").

#### 14. messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger` -- code/game/objects/items/weapons/storage/backpack.dm
  name: messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbag`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger` -- code/game/objects/items/weapons/storage/backpack.dm
  name: messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbag`
- Confidence: HIGH -- identical type path structure and identical name ("messenger bag").

#### 15. captain's messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger/com` -- code/game/objects/items/weapons/storage/backpack.dm
  name: captain's messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbagcom`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger/com` -- code/game/objects/items/weapons/storage/backpack.dm
  name: captain's messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbagcom`
- Confidence: HIGH -- identical type path structure and identical name ("captain's messenger bag").

#### 16. engineering messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger/engi` -- code/game/objects/items/weapons/storage/backpack.dm
  name: engineering messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbagengi`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger/engi` -- code/game/objects/items/weapons/storage/backpack.dm
  name: engineering messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbagengi`
- Confidence: HIGH -- identical type path structure and identical name ("engineering messenger bag").

#### 17. hydroponics messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger/hyd` -- code/game/objects/items/weapons/storage/backpack.dm
  name: hydroponics messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbaghyd`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger/hyd` -- code/game/objects/items/weapons/storage/backpack.dm
  name: hydroponics messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbaghyd`
- Confidence: HIGH -- identical type path structure and identical name ("hydroponics messenger bag").

#### 18. medical messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger/med` -- code/game/objects/items/weapons/storage/backpack.dm
  name: medical messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbagmed`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger/med` -- code/game/objects/items/weapons/storage/backpack.dm
  name: medical messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbagmed`
- Confidence: HIGH -- identical type path structure and identical name ("medical messenger bag").

#### 19. security messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger/sec` -- code/game/objects/items/weapons/storage/backpack.dm
  name: security messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbagsec`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger/sec` -- code/game/objects/items/weapons/storage/backpack.dm
  name: security messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbagsec`
- Confidence: HIGH -- identical type path structure and identical name ("security messenger bag").

#### 20. research messenger bag

- **Aurora**: `/obj/item/storage/backpack/messenger/tox` -- code/game/objects/items/weapons/storage/backpack.dm
  name: research messenger bag -- icon: icons/obj/storage/courierbag.dmi -- icon_state: `courierbagtox`
- **Serenity**: `/obj/item/weapon/storage/backpack/messenger/tox` -- code/game/objects/items/weapons/storage/backpack.dm
  name: \improper NanoTrasen messenger bag -- icon: icons/obj/storage.dmi -- icon_state: `courierbagnt`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 21. black rucksack

- **Aurora**: `/obj/item/storage/backpack/rucksack` -- code/game/objects/items/weapons/storage/backpack.dm
  name: black rucksack -- icon: icons/obj/storage/rucksack.dmi -- icon_state: `rucksack_black`
- **Serenity**: `/obj/item/weapon/storage/backpack/rucksack` -- code/game/objects/items/weapons/storage/backpack.dm
  name: black rucksack -- icon: icons/obj/storage.dmi -- icon_state: `rucksack_black`
- Confidence: HIGH -- identical type path structure and identical name ("black rucksack").

#### 22. green rucksack

- **Aurora**: `/obj/item/storage/backpack/rucksack/green` -- code/game/objects/items/weapons/storage/backpack.dm
  name: green rucksack -- icon: icons/obj/storage/rucksack.dmi -- icon_state: `rucksack_green`
- **Serenity**: `/obj/item/weapon/storage/backpack/rucksack/green` -- code/game/objects/items/weapons/storage/backpack.dm
  name: green rucksack -- icon: icons/obj/storage.dmi -- icon_state: `rucksack_green`
- Confidence: HIGH -- identical type path structure and identical name ("green rucksack").

#### 23. navy rucksack

- **Aurora**: `/obj/item/storage/backpack/rucksack/navy` -- code/game/objects/items/weapons/storage/backpack.dm
  name: navy rucksack -- icon: icons/obj/storage/rucksack.dmi -- icon_state: `rucksack_navy`
- **Serenity**: `/obj/item/weapon/storage/backpack/rucksack/navy` -- code/game/objects/items/weapons/storage/backpack.dm
  name: navy rucksack -- icon: icons/obj/storage.dmi -- icon_state: `rucksack_navy`
- Confidence: HIGH -- identical type path structure and identical name ("navy rucksack").

#### 24. tan rucksack

- **Aurora**: `/obj/item/storage/backpack/rucksack/tan` -- code/game/objects/items/weapons/storage/backpack.dm
  name: tan rucksack -- icon: icons/obj/storage/rucksack.dmi -- icon_state: `rucksack_tan`
- **Serenity**: `/obj/item/weapon/storage/backpack/rucksack/tan` -- code/game/objects/items/weapons/storage/backpack.dm
  name: tan rucksack -- icon: icons/obj/storage.dmi -- icon_state: `rucksack_tan`
- Confidence: HIGH -- identical type path structure and identical name ("tan rucksack").

#### 25. \improper Santa's gift bag

- **Aurora**: `/obj/item/storage/backpack/santabag` -- code/game/objects/items/weapons/storage/backpack.dm
  name: \improper Santa's gift bag -- icon: icons/obj/storage/backpack.dmi -- icon_state: `giftbag0`
- **Serenity**: `/obj/item/weapon/storage/backpack/santabag` -- code/game/objects/items/weapons/storage/backpack.dm
  name: \improper Santa's gift bag -- icon: icons/obj/storage.dmi -- icon_state: `giftbag0`
- Confidence: HIGH -- identical type path structure and identical name ("\improper Santa's gift bag").

#### 26. satchel

- **Aurora**: `/obj/item/storage/backpack/satchel` -- code/game/objects/items/weapons/storage/backpack.dm
  name: satchel -- icon: icons/obj/storage/satchel.dmi -- icon_state: `satchel`
- **Serenity**: `/obj/item/weapon/storage/backpack/satchel` -- code/game/objects/items/weapons/storage/backpack.dm
  name: satchel -- icon: icons/obj/storage.dmi -- icon_state: `satchel-norm`
- Confidence: HIGH -- identical type path structure and identical name ("satchel").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 27. leather satchel

- **Aurora**: `/obj/item/storage/backpack/satchel/leather` -- code/game/objects/items/weapons/storage/backpack.dm
  name: leather satchel -- icon: icons/obj/storage/satchel.dmi -- icon_state: `satchel_leather`
- **Serenity**: `/obj/item/weapon/storage/backpack/satchel/leather` -- code/game/objects/items/weapons/storage/backpack.dm
  name: brown leather satchel -- icon: icons/obj/storage.dmi -- icon_state: `satchel`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 28. leather pocketbook

- **Aurora**: `/obj/item/storage/backpack/satchel/pocketbook` -- code/game/objects/items/weapons/storage/backpack.dm
  name: leather pocketbook -- icon: icons/obj/storage/satchel.dmi -- icon_state: `pocketbook_leather`
- **Serenity**: `/obj/item/weapon/storage/backpack/satchel/pocketbook` -- code/game/objects/items/weapons/storage/backpack.dm
  name: black pocketbook -- icon: icons/obj/storage.dmi -- icon_state: `pocketbook`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 29. security backpack

- **Aurora**: `/obj/item/storage/backpack/security` -- code/game/objects/items/weapons/storage/backpack.dm
  name: security backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `securitypack`
- **Serenity**: `/obj/item/weapon/storage/backpack/security` -- code/game/objects/items/weapons/storage/backpack.dm
  name: security backpack -- icon: icons/obj/storage.dmi -- icon_state: `securitypack`
- Confidence: HIGH -- identical type path structure and identical name ("security backpack").

#### 30. laboratory backpack

- **Aurora**: `/obj/item/storage/backpack/toxins` -- code/game/objects/items/weapons/storage/backpack.dm
  name: laboratory backpack -- icon: icons/obj/storage/backpack.dmi -- icon_state: `toxpack`
- **Serenity**: `/obj/item/weapon/storage/backpack/toxins` -- code/game/objects/items/weapons/storage/backpack.dm
  name: \improper toxins backpack -- icon: icons/obj/storage.dmi -- icon_state: `ntpack`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "laboratory backpack" / Serenity: "\improper toxins backpack") -- verify these are truly the same item before swapping.

#### 31. storage

- **Aurora**: `/obj/item/storage/bag` -- code/game/objects/items/weapons/storage/bags.dm
  name: storage -- icon: icons/obj/storage/bags.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/weapon/storage/bag` -- code/game/objects/items/weapons/storage/bags.dm
  name: storage -- icon: icons/obj/storage.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("storage").

#### 32. plastic bag

- **Aurora**: `/obj/item/storage/bag/plasticbag` -- code/game/objects/items/weapons/storage/bags.dm
  name: plastic bag -- icon: icons/obj/storage/bags.dmi -- icon_state: `plasticbag`
- **Serenity**: `/obj/item/weapon/storage/bag/plasticbag` -- code/game/objects/items/weapons/storage/bags.dm
  name: plastic bag -- icon: icons/obj/trash.dmi -- icon_state: `plasticbag`
- Confidence: HIGH -- identical type path structure and identical name ("plastic bag").

#### 33. trash bag

- **Aurora**: `/obj/item/storage/bag/trash` -- code/game/objects/items/weapons/storage/bags.dm
  name: trash bag -- icon: icons/obj/storage/bags.dmi -- icon_state: `trashbag0`
- **Serenity**: `/obj/item/weapon/storage/bag/trash` -- code/game/objects/items/weapons/storage/bags.dm
  name: trash bag -- icon: icons/obj/janitor.dmi -- icon_state: `trashbag0`
- Confidence: HIGH -- identical type path structure and identical name ("trash bag").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 34. bible

- **Aurora**: `/obj/item/storage/bible` -- code/game/objects/items/weapons/storage/bible.dm
  name: bible -- icon: icons/obj/library.dmi -- icon_state: `bible`
- **Serenity**: `/obj/item/weapon/storage/bible` -- code/game/objects/items/weapons/storage/bible.dm
  name: bible -- icon: icons/obj/storage.dmi -- icon_state: `bible`
- Confidence: HIGH -- identical type path structure and identical name ("bible").

#### 35. bible

- **Aurora**: `/obj/item/storage/bible/booze` -- code/game/objects/items/weapons/storage/bible.dm
  name: bible -- icon: icons/obj/library.dmi -- icon_state: `bible`
- **Serenity**: `/obj/item/weapon/storage/bible/booze` -- code/game/objects/items/weapons/storage/bible.dm
  name: bible -- icon: icons/obj/storage.dmi -- icon_state: `bible`
- Confidence: HIGH -- identical type path structure and identical name ("bible").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 36. `/obj/item/storage/box` and subtypes (4 types)

- **Aurora**: `/obj/item/storage/box` + subtypes -- code/game/objects/items/weapons/storage/boxes.dm
  icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: equivalent family -- code/game/objects/items/weapons/storage/boxes.dm
  icon: icons/obj/storage.dmi -- icon_state: `box`
- Subtypes covered: `(base)`, `/cups`, `/holobadge`, `/pillbottles`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 37. box of empty injectors

- **Aurora**: `/obj/item/storage/box/autoinjectors` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of empty injectors -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/autoinjectors` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of injectors -- icon: icons/obj/storage.dmi -- icon_state: `syringe`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 38. box of beakers

- **Aurora**: `/obj/item/storage/box/beakers` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of beakers -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/beakers` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of beakers -- icon: icons/obj/storage.dmi -- icon_state: `beaker`
- Confidence: HIGH -- identical type path structure and identical name ("box of beakers").

#### 39. body bags

- **Aurora**: `/obj/item/storage/box/bodybags` -- code/game/objects/items/bodybag.dm
  name: body bags -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/bodybags` -- code/game/objects/items/bodybag.dm
  name: body bags -- icon: icons/obj/storage.dmi -- icon_state: `bodybags`
- Confidence: HIGH -- identical type path structure and identical name ("body bags").

#### 40. death alarm kit

- **Aurora**: `/obj/item/storage/box/cdeathalarm_kit` -- code/game/objects/items/weapons/storage/boxes.dm
  name: death alarm kit -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/cdeathalarm_kit` -- code/game/objects/items/weapons/storage/boxes.dm
  name: death alarm kit -- icon: icons/obj/storage.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("death alarm kit").

#### 41. boxed chemical implant kit

- **Aurora**: `/obj/item/storage/box/chemimp` -- code/game/objects/items/weapons/storage/boxes.dm
  name: boxed chemical implant kit -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/chemimp` -- code/game/objects/items/weapons/storage/boxes.dm
  name: boxed chemical implant kit -- icon: icons/obj/storage.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("boxed chemical implant kit").

#### 42. box of sterile gloves

- **Aurora**: `/obj/item/storage/box/gloves` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of sterile gloves -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/gloves` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of sterile gloves -- icon: icons/obj/storage.dmi -- icon_state: `latex`
- Confidence: HIGH -- identical type path structure and identical name ("box of sterile gloves").

#### 43. box of spare handcuffs

- **Aurora**: `/obj/item/storage/box/handcuffs` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of spare handcuffs -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/handcuffs` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of spare handcuffs -- icon: icons/obj/storage.dmi -- icon_state: `handcuff`
- Confidence: HIGH -- identical type path structure and identical name ("box of spare handcuffs").

#### 44. box of spare IDs

- **Aurora**: `/obj/item/storage/box/ids` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of spare IDs -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/ids` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of spare IDs -- icon: icons/obj/storage.dmi -- icon_state: `id`
- Confidence: HIGH -- identical type path structure and identical name ("box of spare IDs").

#### 45. large box

- **Aurora**: `/obj/item/storage/box/large` -- code/game/objects/items/weapons/storage/boxes.dm
  name: large box -- icon: icons/obj/storage/boxes.dmi -- icon_state: `largebox`
- **Serenity**: `/obj/item/weapon/storage/box/large` -- code/game/objects/items/weapons/storage/boxes.dm
  name: large box -- icon: icons/obj/storage.dmi -- icon_state: `largebox`
- Confidence: HIGH -- identical type path structure and identical name ("large box").

#### 46. box of replacement bulbs

- **Aurora**: `/obj/item/storage/box/lights` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement bulbs -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/lights` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement bulbs -- icon: icons/obj/storage.dmi -- icon_state: `light`
- Confidence: HIGH -- identical type path structure and identical name ("box of replacement bulbs").

#### 47. box of replacement bulbs

- **Aurora**: `/obj/item/storage/box/lights/bulbs` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement bulbs -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/lights/bulbs` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement bulbs -- icon: icons/obj/storage.dmi -- icon_state: `light`
- Confidence: HIGH -- identical type path structure and identical name ("box of replacement bulbs").

#### 48. box of replacement lights

- **Aurora**: `/obj/item/storage/box/lights/mixed` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement lights -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/lights/mixed` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement lights -- icon: icons/obj/storage.dmi -- icon_state: `lightmixed`
- Confidence: HIGH -- identical type path structure and identical name ("box of replacement lights").

#### 49. box of replacement tubes

- **Aurora**: `/obj/item/storage/box/lights/tubes` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement tubes -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/lights/tubes` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of replacement tubes -- icon: icons/obj/storage.dmi -- icon_state: `lighttube`
- Confidence: HIGH -- identical type path structure and identical name ("box of replacement tubes").

#### 50. box of surgical masks

- **Aurora**: `/obj/item/storage/box/masks` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of surgical masks -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/masks` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of sterile masks -- icon: icons/obj/storage.dmi -- icon_state: `sterile`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 51. box of Pest-B-Gon mousetraps

- **Aurora**: `/obj/item/storage/box/mousetraps` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of Pest-B-Gon mousetraps -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/mousetraps` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of Pest-B-Gon mousetraps -- icon: icons/obj/storage.dmi -- icon_state: `mousetraps`
- Confidence: HIGH -- identical type path structure and identical name ("box of Pest-B-Gon mousetraps").

#### 52. box of prescription glasses

- **Aurora**: `/obj/item/storage/box/rxglasses` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of prescription glasses -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/rxglasses` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of prescription glasses -- icon: icons/obj/storage.dmi -- icon_state: `glasses`
- Confidence: HIGH -- identical type path structure and identical name ("box of prescription glasses").

#### 53. `/obj/item/storage/box/syndie_kit` and subtypes (9 types)

- **Aurora**: `/obj/item/storage/box/syndie_kit` + subtypes -- code/game/objects/items/weapons/storage/uplink_kits.dm
  icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: equivalent family -- code/game/objects/items/weapons/storage/uplink_kits.dm
  icon: icons/obj/storage.dmi -- icon_state: `box_of_doom`
- Subtypes covered: `(base)`, `/chameleon`, `/cigarette`, `/imp_compress`, `/imp_explosive`, `/imp_freedom`, `/imp_uplink`, `/spy`, `/toxin`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 54. box of syringe gun cartridges

- **Aurora**: `/obj/item/storage/box/syringegun` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of syringe gun cartridges -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/syringegun` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of syringe gun cartridges -- icon: icons/obj/storage.dmi -- icon_state: `syringe`
- Confidence: HIGH -- identical type path structure and identical name ("box of syringe gun cartridges").

#### 55. box of syringes

- **Aurora**: `/obj/item/storage/box/syringes` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of syringes -- icon: icons/obj/storage/boxes.dmi -- icon_state: `box`
- **Serenity**: `/obj/item/weapon/storage/box/syringes` -- code/game/objects/items/weapons/storage/boxes.dm
  name: box of syringes -- icon: icons/obj/storage.dmi -- icon_state: `syringe`
- Confidence: HIGH -- identical type path structure and identical name ("box of syringes").

#### 56. briefcase

- **Aurora**: `/obj/item/storage/briefcase` -- code/game/objects/items/weapons/storage/briefcase.dm
  name: briefcase -- icon: icons/obj/storage/briefcase.dmi -- icon_state: `briefcase`
- **Serenity**: `/obj/item/weapon/storage/briefcase` -- code/game/objects/items/weapons/storage/briefcase.dm
  name: briefcase -- icon: icons/obj/storage.dmi -- icon_state: `briefcase`
- Confidence: HIGH -- identical type path structure and identical name ("briefcase").

#### 57. first-aid kit

- **Aurora**: `/obj/item/storage/firstaid` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: first-aid kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `firstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: first-aid kit -- icon: icons/obj/storage.dmi -- icon_state: `firstaid`
- Confidence: HIGH -- identical type path structure and identical name ("first-aid kit").

#### 58. advanced first-aid kit

- **Aurora**: `/obj/item/storage/firstaid/adv` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: advanced first-aid kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `advfirstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/adv` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: advanced first-aid kit -- icon: icons/obj/storage.dmi -- icon_state: `advfirstaid`
- Confidence: HIGH -- identical type path structure and identical name ("advanced first-aid kit").

#### 59. combat medical kit

- **Aurora**: `/obj/item/storage/firstaid/combat` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: combat medical kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `bezerk`
- **Serenity**: `/obj/item/weapon/storage/firstaid/combat` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: combat medical kit -- icon: icons/obj/storage.dmi -- icon_state: `bezerk`
- Confidence: HIGH -- identical type path structure and identical name ("combat medical kit").

#### 60. first-aid kit

- **Aurora**: `/obj/item/storage/firstaid/empty` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: first-aid kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `firstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/empty` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: First-Aid (empty) -- icon: icons/obj/storage.dmi -- icon_state: `firstaid`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 61. fire first-aid kit

- **Aurora**: `/obj/item/storage/firstaid/fire` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: fire first-aid kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `firefirstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/fire` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: fire first-aid kit -- icon: icons/obj/storage.dmi -- icon_state: `ointment`
- Confidence: HIGH -- identical type path structure and identical name ("fire first-aid kit").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 62. oxygen deprivation kit

- **Aurora**: `/obj/item/storage/firstaid/o2` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: oxygen deprivation kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `o2firstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/o2` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: oxygen deprivation first aid -- icon: icons/obj/storage.dmi -- icon_state: `o2`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 63. first-aid kit

- **Aurora**: `/obj/item/storage/firstaid/regular` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: first-aid kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `firstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/regular` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: first-aid kit -- icon: icons/obj/storage.dmi -- icon_state: `firstaid`
- Confidence: HIGH -- identical type path structure and identical name ("first-aid kit").

#### 64. surgery kit

- **Aurora**: `/obj/item/storage/firstaid/surgery` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: surgery kit -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `purplefirstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/surgery` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: surgery kit -- icon: icons/obj/storage.dmi -- icon_state: `surgerykit`
- Confidence: HIGH -- identical type path structure and identical name ("surgery kit").

#### 65. toxin first-aid

- **Aurora**: `/obj/item/storage/firstaid/toxin` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: toxin first-aid -- icon: icons/obj/storage/firstaid.dmi -- icon_state: `antitoxfirstaid`
- **Serenity**: `/obj/item/weapon/storage/firstaid/toxin` -- code/game/objects/items/weapons/storage/firstaid.dm
  name: toxin first aid -- icon: icons/obj/storage.dmi -- icon_state: `antitoxin`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 66. storage

- **Aurora**: `/obj/item/storage/internal` -- code/game/objects/items/weapons/storage/internal.dm
  name: storage -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/weapon/storage/internal` -- code/game/objects/items/weapons/storage/internal.dm
  name: storage -- icon: icons/obj/storage.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("storage").

#### 67. lockbox

- **Aurora**: `/obj/item/storage/lockbox` -- code/game/objects/items/weapons/storage/lockbox.dm
  name: lockbox -- icon: icons/obj/storage/briefcase.dmi -- icon_state: `lockbox+l`
- **Serenity**: `/obj/item/weapon/storage/lockbox` -- code/game/objects/items/weapons/storage/lockbox.dm
  name: lockbox -- icon: icons/obj/storage.dmi -- icon_state: `lockbox+l`
- Confidence: HIGH -- identical type path structure and identical name ("lockbox").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 68. lockbox of clusterbangs

- **Aurora**: `/obj/item/storage/lockbox/clusterbang` -- code/game/objects/items/weapons/storage/lockbox.dm
  name: lockbox of clusterbangs -- icon: icons/obj/storage/briefcase.dmi -- icon_state: `lockbox+l`
- **Serenity**: `/obj/item/weapon/storage/lockbox/clusterbang` -- code/game/objects/items/weapons/storage/lockbox.dm
  name: lockbox of clusterbangs -- icon: icons/obj/storage.dmi -- icon_state: `lockbox+l`
- Confidence: HIGH -- identical type path structure and identical name ("lockbox of clusterbangs").

#### 69. lockbox of mind shield implants

- **Aurora**: `/obj/item/storage/lockbox/loyalty` -- code/game/objects/items/weapons/storage/lockbox.dm
  name: lockbox of mind shield implants -- icon: icons/obj/storage/briefcase.dmi -- icon_state: `lockbox+l`
- **Serenity**: `/obj/item/weapon/storage/lockbox/loyalty` -- code/game/objects/items/weapons/storage/lockbox.dm
  name: lockbox of loyalty implants -- icon: icons/obj/storage.dmi -- icon_state: `lockbox+l`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 70. secure vial storage box

- **Aurora**: `/obj/item/storage/lockbox/vials` -- code/game/objects/items/weapons/storage/fancy.dm
  name: secure vial storage box -- icon: icons/obj/storage/fancy/vialbox.dmi -- icon_state: `vialbox0`
- **Serenity**: `/obj/item/weapon/storage/lockbox/vials` -- code/game/objects/items/weapons/storage/fancy.dm
  name: secure vial storage box -- icon: icons/obj/vialbox.dmi -- icon_state: `vialbox0`
- Confidence: HIGH -- identical type path structure and identical name ("secure vial storage box").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 71. secure briefcase

- **Aurora**: `/obj/item/storage/secure/briefcase` -- code/game/objects/items/weapons/storage/secure.dm
  name: secure briefcase -- icon: icons/obj/storage/briefcase.dmi -- icon_state: `secure`
- **Serenity**: `/obj/item/weapon/storage/secure/briefcase` -- code/game/objects/items/weapons/storage/secure.dm
  name: secure briefcase -- icon: icons/obj/storage.dmi -- icon_state: `secure`
- Confidence: HIGH -- identical type path structure and identical name ("secure briefcase").

#### 72. secure briefcase

- **Aurora**: `/obj/item/storage/secure/briefcase/money` -- code/game/objects/items/weapons/storage/uplink_kits.dm
  name: secure briefcase -- icon: icons/obj/storage/briefcase.dmi -- icon_state: `secure`
- **Serenity**: `/obj/item/weapon/storage/secure/briefcase/money` -- code/game/objects/items/weapons/storage/uplink_kits.dm
  name: secure briefcase -- icon: icons/obj/storage.dmi -- icon_state: `secure`
- Confidence: HIGH -- identical type path structure and identical name ("secure briefcase").

#### 73. secure safe

- **Aurora**: `/obj/item/storage/secure/safe` -- code/game/objects/items/weapons/storage/secure.dm
  name: secure safe -- icon: icons/obj/storage/misc.dmi -- icon_state: `safe`
- **Serenity**: `/obj/item/weapon/storage/secure/safe` -- code/game/objects/items/weapons/storage/secure.dm
  name: secure safe -- icon: icons/obj/storage.dmi -- icon_state: `safe`
- Confidence: HIGH -- identical type path structure and identical name ("secure safe").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 74. toolbox

- **Aurora**: `/obj/item/storage/toolbox` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: toolbox -- icon: icons/obj/storage/toolbox.dmi -- icon_state: `red`
- **Serenity**: `/obj/item/weapon/storage/toolbox` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: toolbox -- icon: icons/obj/storage.dmi -- icon_state: `red`
- Confidence: HIGH -- identical type path structure and identical name ("toolbox").

#### 75. electrical toolbox

- **Aurora**: `/obj/item/storage/toolbox/electrical` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: electrical toolbox -- icon: icons/obj/storage/toolbox.dmi -- icon_state: `yellow`
- **Serenity**: `/obj/item/weapon/storage/toolbox/electrical` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: electrical toolbox -- icon: icons/obj/storage.dmi -- icon_state: `yellow`
- Confidence: HIGH -- identical type path structure and identical name ("electrical toolbox").

#### 76. emergency toolbox

- **Aurora**: `/obj/item/storage/toolbox/emergency` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: emergency toolbox -- icon: icons/obj/storage/toolbox.dmi -- icon_state: `red`
- **Serenity**: `/obj/item/weapon/storage/toolbox/emergency` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: emergency toolbox -- icon: icons/obj/storage.dmi -- icon_state: `red`
- Confidence: HIGH -- identical type path structure and identical name ("emergency toolbox").

#### 77. mechanical toolbox

- **Aurora**: `/obj/item/storage/toolbox/mechanical` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: mechanical toolbox -- icon: icons/obj/storage/toolbox.dmi -- icon_state: `blue`
- **Serenity**: `/obj/item/weapon/storage/toolbox/mechanical` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: mechanical toolbox -- icon: icons/obj/storage.dmi -- icon_state: `blue`
- Confidence: HIGH -- identical type path structure and identical name ("mechanical toolbox").

#### 78. suspicious looking toolbox

- **Aurora**: `/obj/item/storage/toolbox/syndicate` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: suspicious looking toolbox -- icon: icons/obj/storage/toolbox.dmi -- icon_state: `syndicate`
- **Serenity**: `/obj/item/weapon/storage/toolbox/syndicate` -- code/game/objects/items/weapons/storage/toolbox.dm
  name: black and red toolbox -- icon: icons/obj/storage.dmi -- icon_state: `syndicate`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "suspicious looking toolbox" / Serenity: "black and red toolbox") -- verify these are truly the same item before swapping.

#### 79. wallet

- **Aurora**: `/obj/item/storage/wallet` -- code/game/objects/items/weapons/storage/wallets.dm
  name: wallet -- icon: icons/obj/storage/wallet.dmi -- icon_state: `wallet_leather`
- **Serenity**: `/obj/item/weapon/storage/wallet` -- code/game/objects/items/weapons/storage/wallets.dm
  name: wallet -- icon: icons/obj/wallet.dmi -- icon_state: `wallet-white`
- Confidence: HIGH -- identical type path structure and identical name ("wallet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

---

## Stacks & Materials (19)

#### 1. medical pack

- **Aurora**: `/obj/item/stack/medical` -- code/game/objects/items/stacks/medical.dm
  name: medical pack -- icon: icons/obj/item/stacks/medical.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/stack/medical` -- code/game/objects/items/stacks/medical.dm
  name: medical pack -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("medical pack").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 2. roll of gauze

- **Aurora**: `/obj/item/stack/medical/bruise_pack` -- code/game/objects/items/stacks/medical.dm
  name: roll of gauze -- icon: icons/obj/item/stacks/medical.dmi -- icon_state: `brutepack`
- **Serenity**: `/obj/item/stack/medical/bruise_pack` -- code/game/objects/items/stacks/medical.dm
  name: roll of gauze -- icon: icons/obj/items.dmi -- icon_state: `brutepack`
- Confidence: HIGH -- identical type path structure and identical name ("roll of gauze").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 3. ointment

- **Aurora**: `/obj/item/stack/medical/ointment` -- code/game/objects/items/stacks/medical.dm
  name: ointment -- icon: icons/obj/item/stacks/medical.dmi -- icon_state: `ointment`
- **Serenity**: `/obj/item/stack/medical/ointment` -- code/game/objects/items/stacks/medical.dm
  name: ointment -- icon: icons/obj/items.dmi -- icon_state: `ointment`
- Confidence: HIGH -- identical type path structure and identical name ("ointment").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 4. medical splints

- **Aurora**: `/obj/item/stack/medical/splint` -- code/game/objects/items/stacks/medical.dm
  name: medical splints -- icon: icons/obj/item/stacks/medical.dmi -- icon_state: `splint`
- **Serenity**: `/obj/item/stack/medical/splint` -- code/game/objects/items/stacks/medical.dm
  name: medical splints -- icon: icons/obj/items.dmi -- icon_state: `splint`
- Confidence: HIGH -- identical type path structure and identical name ("medical splints").

#### 5. nanopaste

- **Aurora**: `/obj/item/stack/nanopaste` -- code/game/objects/items/stacks/nanopaste.dm
  name: nanopaste -- icon: icons/obj/item/stacks/nanopaste.dmi -- icon_state: `tube`
- **Serenity**: `/obj/item/stack/nanopaste` -- code/game/objects/items/stacks/nanopaste.dm
  name: nanopaste -- icon: icons/obj/nanopaste.dmi -- icon_state: `tube`
- Confidence: HIGH -- identical type path structure and identical name ("nanopaste").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. metal rod

- **Aurora**: `/obj/item/stack/rods` -- code/game/objects/items/stacks/rods.dm
  name: metal rod -- icon: icons/obj/item/stacks/materials.dmi -- icon_state: `rods`
- **Serenity**: `/obj/item/stack/rods` -- code/game/objects/items/stacks/rods.dm
  name: metal rod -- icon: icons/obj/items.dmi -- icon_state: `rods`
- Confidence: HIGH -- identical type path structure and identical name ("metal rod").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. metal rod synthesizer

- **Aurora**: `/obj/item/stack/rods/cyborg` -- code/game/objects/items/stacks/rods.dm
  name: metal rod synthesizer -- icon: icons/obj/item/stacks/materials.dmi -- icon_state: `rods`
- **Serenity**: `/obj/item/stack/rods/cyborg` -- code/game/objects/items/stacks/rods.dm
  name: metal rod synthesizer -- icon: icons/obj/items.dmi -- icon_state: `rods`
- Confidence: HIGH -- identical type path structure and identical name ("metal rod synthesizer").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 8. telecrystal

- **Aurora**: `/obj/item/stack/telecrystal` -- code/game/objects/items/stacks/telecrystal.dm
  name: telecrystal -- icon: icons/obj/item/stacks/materials.dmi -- icon_state: `telecrystal`
- **Serenity**: `/obj/item/stack/telecrystal` -- code/game/objects/items/stacks/telecrystal.dm
  name: telecrystal -- icon: icons/obj/telescience.dmi -- icon_state: `telecrystal`
- Confidence: HIGH -- identical type path structure and identical name ("telecrystal").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 9. tile

- **Aurora**: `/obj/item/stack/tile` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: tile -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/stack/tile` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: tile -- icon: icons/obj/tiles.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("tile").

#### 10. carpet

- **Aurora**: `/obj/item/stack/tile/carpet` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: carpet -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_carpet`
- **Serenity**: `/obj/item/stack/tile/carpet` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: brown carpet -- icon: icons/obj/tiles.dmi -- icon_state: `tile_carpetbrown`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 11. steel tiles

- **Aurora**: `/obj/item/stack/tile/floor` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: steel tiles -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile`
- **Serenity**: `/obj/item/stack/tile/floor` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: steel floor tile -- icon: icons/obj/tiles.dmi -- icon_state: `tile`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 12. floor tile synthesizer

- **Aurora**: `/obj/item/stack/tile/floor/cyborg` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: floor tile synthesizer -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile`
- **Serenity**: `/obj/item/stack/tile/floor/cyborg` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: floor tile synthesizer -- icon: icons/obj/tiles.dmi -- icon_state: `tile`
- Confidence: HIGH -- identical type path structure and identical name ("floor tile synthesizer").

#### 13. plasteel tiles

- **Aurora**: `/obj/item/stack/tile/floor_dark` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: plasteel tiles -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `fr_tile`
- **Serenity**: `/obj/item/stack/tile/floor_dark` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: dark floor tile -- icon: icons/obj/tiles.dmi -- icon_state: `fr_tile`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "plasteel tiles" / Serenity: "dark floor tile") -- verify these are truly the same item before swapping.

#### 14. freezer floor tile

- **Aurora**: `/obj/item/stack/tile/floor_freezer` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: freezer floor tile -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_freezer`
- **Serenity**: `/obj/item/stack/tile/floor_freezer` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: freezer floor tile -- icon: icons/obj/tiles.dmi -- icon_state: `tile_freezer`
- Confidence: HIGH -- identical type path structure and identical name ("freezer floor tile").

#### 15. white floor tile

- **Aurora**: `/obj/item/stack/tile/floor_white` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: white floor tile -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_white`
- **Serenity**: `/obj/item/stack/tile/floor_white` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: white floor tile -- icon: icons/obj/tiles.dmi -- icon_state: `tile_white`
- Confidence: HIGH -- identical type path structure and identical name ("white floor tile").

#### 16. synthetic grass tile

- **Aurora**: `/obj/item/stack/tile/grass` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: synthetic grass tile -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_grass`
- **Serenity**: `/obj/item/stack/tile/grass` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: grass tile -- icon: icons/obj/tiles.dmi -- icon_state: `tile_grass`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 17. full steel tiles

- **Aurora**: `/obj/item/stack/tile/mono` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: full steel tiles -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_full`
- **Serenity**: `/obj/item/stack/tile/mono` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: grey mono tile -- icon: icons/obj/tiles.dmi -- icon_state: `tile`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "full steel tiles" / Serenity: "grey mono tile") -- verify these are truly the same item before swapping.

#### 18. wood floor tile

- **Aurora**: `/obj/item/stack/tile/wood` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: wood floor tile -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_wood`
- **Serenity**: `/obj/item/stack/tile/wood` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: wood floor tile -- icon: icons/obj/tiles.dmi -- icon_state: `tile-wood`
- Confidence: HIGH -- identical type path structure and identical name ("wood floor tile").

#### 19. wood floor tile synthesizer

- **Aurora**: `/obj/item/stack/tile/wood/cyborg` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: wood floor tile synthesizer -- icon: icons/obj/item/stacks/tiles.dmi -- icon_state: `tile_wood`
- **Serenity**: `/obj/item/stack/tile/wood/cyborg` -- code/game/objects/items/stacks/tiles/tile_types.dm
  name: wood floor tile synthesizer -- icon: icons/obj/tiles.dmi -- icon_state: `tile-wood`
- Confidence: HIGH -- identical type path structure and identical name ("wood floor tile synthesizer").

---

## Chemistry / Reagent Containers (8)

#### 1. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_neutral`
- Confidence: HIGH -- identical type path structure and identical name ("paint bucket").

#### 2. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/black` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/black` -- code/game/objects/items/weapons/paint.dm
  name: black paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_black`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 3. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/blue` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/blue` -- code/game/objects/items/weapons/paint.dm
  name: blue paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_blue`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 4. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/green` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/green` -- code/game/objects/items/weapons/paint.dm
  name: green paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_green`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 5. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/purple` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/purple` -- code/game/objects/items/weapons/paint.dm
  name: purple paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_violet`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 6. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/red` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/red` -- code/game/objects/items/weapons/paint.dm
  name: red paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_red`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 7. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/white` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/white` -- code/game/objects/items/weapons/paint.dm
  name: white paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_white`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 8. paint bucket

- **Aurora**: `/obj/item/reagent_containers/glass/paint/yellow` -- code/game/objects/items/weapons/paint.dm
  name: paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_empty`
- **Serenity**: `/obj/item/weapon/reagent_containers/glass/paint/yellow` -- code/game/objects/items/weapons/paint.dm
  name: yellow paint bucket -- icon: icons/obj/items.dmi -- icon_state: `paint_yellow`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

---

## Clothing - Head (39)

#### 1. bandana

- **Aurora**: `/obj/item/clothing/head/bandana` -- code/modules/clothing/head/bandanas.dm
  name: bandana -- icon: icons/obj/clothing/hats/bandanas.dmi -- icon_state: `bandana`
- **Serenity**: `/obj/item/clothing/head/bandana` -- code/modules/clothing/head/misc.dm
  name: pirate bandana -- icon: icons/obj/clothing/hats.dmi -- icon_state: `bandana`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 2. beret

- **Aurora**: `/obj/item/clothing/head/beret` -- code/modules/clothing/head/berets.dm
  name: beret -- icon: icons/obj/clothing/hats/berets.dmi -- icon_state: `beret`
- **Serenity**: `/obj/item/clothing/head/beret` -- code/modules/clothing/head/jobs.dm
  name: beret -- icon: icons/obj/clothing/hats.dmi -- icon_state: `beret`
- Confidence: HIGH -- identical type path structure and identical name ("beret").

#### 3. captain's beret

- **Aurora**: `/obj/item/clothing/head/beret/centcom/captain` -- code/modules/clothing/head/berets.dm
  name: captain's beret -- icon: _(unset -- inherited/default)_ -- icon_state: `centcomcaptain`
- **Serenity**: `/obj/item/clothing/head/beret/centcom/captain` -- code/modules/clothing/head/jobs.dm
  name: asset protection command beret -- icon: _(unset -- inherited/default)_ -- icon_state: `beret_corporate_white`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "captain's beret" / Serenity: "asset protection command beret") -- verify these are truly the same item before swapping.

#### 4. officers beret

- **Aurora**: `/obj/item/clothing/head/beret/centcom/officer` -- code/modules/clothing/head/berets.dm
  name: officers beret -- icon: _(unset -- inherited/default)_ -- icon_state: `centcomofficer`
- **Serenity**: `/obj/item/clothing/head/beret/centcom/officer` -- code/modules/clothing/head/jobs.dm
  name: asset protection beret -- icon: _(unset -- inherited/default)_ -- icon_state: `beret_corporate_navy`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "officers beret" / Serenity: "asset protection beret") -- verify these are truly the same item before swapping.

#### 5. engineering beret

- **Aurora**: `/obj/item/clothing/head/beret/engineering` -- code/modules/clothing/head/berets.dm
  name: engineering beret -- icon: icons/obj/clothing/hats/berets.dmi -- icon_state: `beret_engi`
- **Serenity**: `/obj/item/clothing/head/beret/engineering` -- code/modules/clothing/head/jobs.dm
  name: corporate engineering beret -- icon: icons/obj/clothing/hats.dmi -- icon_state: `beret_orange`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 6. captain's cap

- **Aurora**: `/obj/item/clothing/head/caphat/cap` -- code/modules/clothing/sets/captain.dm
  name: captain's cap -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `captain_cap`
- **Serenity**: `/obj/item/clothing/head/caphat/cap` -- code/modules/clothing/head/jobs.dm
  name: captain's cap -- icon: icons/obj/clothing/hats.dmi -- icon_state: `capcap`
- Confidence: HIGH -- identical type path structure and identical name ("captain's cap").

#### 7. grey cap

- **Aurora**: `/obj/item/clothing/head/chameleon` -- code/modules/clothing/chameleon.dm
  name: grey cap -- icon: icons/obj/clothing/hats/soft_caps.dmi -- icon_state: `softcap`
- **Serenity**: `/obj/item/clothing/head/chameleon` -- code/modules/clothing/chameleon.dm
  name: grey cap -- icon: icons/obj/clothing/hats.dmi -- icon_state: `greysoft`
- Confidence: HIGH -- identical type path structure and identical name ("grey cap").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 8. collectable beret

- **Aurora**: `/obj/item/clothing/head/collectable/beret` -- code/modules/clothing/head/collectable.dm
  name: collectable beret -- icon: icons/obj/clothing/hats/berets.dmi -- icon_state: `beret_red`
- **Serenity**: `/obj/item/clothing/head/collectable/beret` -- code/modules/clothing/head/collectable.dm
  name: collectable beret -- icon: icons/obj/clothing/hats.dmi -- icon_state: `beret`
- Confidence: HIGH -- identical type path structure and identical name ("collectable beret").

#### 9. collectable hard hat

- **Aurora**: `/obj/item/clothing/head/collectable/hardhat` -- code/modules/clothing/head/collectable.dm
  name: collectable hard hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat_yellow`
- **Serenity**: `/obj/item/clothing/head/collectable/hardhat` -- code/modules/clothing/head/collectable.dm
  name: collectable hard hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat0_yellow`
- Confidence: HIGH -- identical type path structure and identical name ("collectable hard hat").

#### 10. collectable xenomorph helmet!

- **Aurora**: `/obj/item/clothing/head/collectable/xenom` -- code/modules/clothing/head/collectable.dm
  name: collectable xenomorph helmet! -- icon: icons/obj/clothing/hats.dmi -- icon_state: `xenos`
- **Serenity**: `/obj/item/clothing/head/collectable/xenom` -- code/modules/clothing/head/collectable.dm
  name: collectable alien monster helmet! -- icon: icons/obj/clothing/hats.dmi -- icon_state: `xenom`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 11. feather trilby

- **Aurora**: `/obj/item/clothing/head/feathertrilby` -- code/modules/clothing/head/misc.dm
  name: feather trilby -- icon: icons/obj/item/clothing/head/feather_trilby.dmi -- icon_state: `feather_trilby`
- **Serenity**: `/obj/item/clothing/head/feathertrilby` -- code/modules/clothing/head/misc.dm
  name: feather trilby -- icon: icons/obj/clothing/hats.dmi -- icon_state: `feather_trilby`
- Confidence: HIGH -- identical type path structure and identical name ("feather trilby").

#### 12. fedora

- **Aurora**: `/obj/item/clothing/head/fedora` -- code/modules/clothing/head/wide_hats.dm
  name: fedora -- icon: icons/obj/item/clothing/head/bucket_hat.dmi -- icon_state: `fedora`
- **Serenity**: `/obj/item/clothing/head/fedora` -- code/modules/clothing/head/misc.dm
  name: fedora -- icon: icons/obj/clothing/hats.dmi -- icon_state: `fedora`
- Confidence: HIGH -- identical type path structure and identical name ("fedora").

#### 13. flat cap

- **Aurora**: `/obj/item/clothing/head/flatcap` -- code/modules/clothing/head/misc.dm
  name: flat cap -- icon: icons/obj/item/clothing/head/flat_cap.dmi -- icon_state: `flat_cap_brown`
- **Serenity**: `/obj/item/clothing/head/flatcap` -- code/modules/clothing/head/misc.dm
  name: flat cap -- icon: icons/obj/clothing/hats.dmi -- icon_state: `flat_cap`
- Confidence: HIGH -- identical type path structure and identical name ("flat cap").

#### 14. hard hat

- **Aurora**: `/obj/item/clothing/head/hardhat` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats/hardhats.dmi -- icon_state: `hardhat_yellow`
- **Serenity**: `/obj/item/clothing/head/hardhat` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat0_yellow`
- Confidence: HIGH -- identical type path structure and identical name ("hard hat").

#### 15. hard hat

- **Aurora**: `/obj/item/clothing/head/hardhat/dblue` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats/hardhats.dmi -- icon_state: `hardhat_dblue`
- **Serenity**: `/obj/item/clothing/head/hardhat/dblue` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat0_dblue`
- Confidence: HIGH -- identical type path structure and identical name ("hard hat").

#### 16. hard hat

- **Aurora**: `/obj/item/clothing/head/hardhat/orange` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats/hardhats.dmi -- icon_state: `hardhat_orange`
- **Serenity**: `/obj/item/clothing/head/hardhat/orange` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat0_orange`
- Confidence: HIGH -- identical type path structure and identical name ("hard hat").

#### 17. hard hat

- **Aurora**: `/obj/item/clothing/head/hardhat/red` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats/hardhats.dmi -- icon_state: `hardhat_red`
- **Serenity**: `/obj/item/clothing/head/hardhat/red` -- code/modules/clothing/head/hardhat.dm
  name: firefighter helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat0_red`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "hard hat" / Serenity: "firefighter helmet") -- verify these are truly the same item before swapping.

#### 18. hard hat

- **Aurora**: `/obj/item/clothing/head/hardhat/white` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats/hardhats.dmi -- icon_state: `hardhat_white`
- **Serenity**: `/obj/item/clothing/head/hardhat/white` -- code/modules/clothing/head/hardhat.dm
  name: hard hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hardhat0_white`
- Confidence: HIGH -- identical type path structure and identical name ("hard hat").

#### 19. ablative helmet

- **Aurora**: `/obj/item/clothing/head/helmet/ablative` -- code/modules/clothing/head/helmet.dm
  name: ablative helmet -- icon: icons/obj/item/clothing/head/modular_armor_helmets.dmi -- icon_state: `helm_ablative`
- **Serenity**: `/obj/item/clothing/head/helmet/ablative` -- code/modules/clothing/head/helmet.dm
  name: ablative helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `helmet_reflect`
- Confidence: HIGH -- identical type path structure and identical name ("ablative helmet").

#### 20. ballistic helmet

- **Aurora**: `/obj/item/clothing/head/helmet/ballistic` -- code/modules/clothing/head/helmet.dm
  name: ballistic helmet -- icon: icons/obj/item/clothing/head/modular_armor_helmets.dmi -- icon_state: `helm_ballistic`
- **Serenity**: `/obj/item/clothing/head/helmet/ballistic` -- code/modules/clothing/head/helmet.dm
  name: ballistic helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `helmet_bulletproof`
- Confidence: HIGH -- identical type path structure and identical name ("ballistic helmet").

#### 21. combat helmet

- **Aurora**: `/obj/item/clothing/head/helmet/merc` -- code/modules/clothing/head/helmet.dm
  name: combat helmet -- icon: icons/obj/item/clothing/head/modular_armor_helmets.dmi -- icon_state: `helm_heavy`
- **Serenity**: `/obj/item/clothing/head/helmet/merc` -- code/modules/clothing/head/helmet.dm
  name: combat helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `helmet_merc`
- Confidence: HIGH -- identical type path structure and identical name ("combat helmet").

#### 22. riot helmet

- **Aurora**: `/obj/item/clothing/head/helmet/riot` -- code/modules/clothing/head/helmet.dm
  name: riot helmet -- icon: icons/obj/item/clothing/head/modular_armor_helmets.dmi -- icon_state: `helm_riot`
- **Serenity**: `/obj/item/clothing/head/helmet/riot` -- code/modules/clothing/head/helmet.dm
  name: riot helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `helmet_riot`
- Confidence: HIGH -- identical type path structure and identical name ("riot helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 23. softsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space` -- code/modules/clothing/spacesuits/spacesuits.dm
  name: softsuit helmet -- icon: icons/obj/item/clothing/softsuits/softsuit.dmi -- icon_state: `softsuit_helmet`
- **Serenity**: `/obj/item/clothing/head/helmet/space` -- code/modules/clothing/spacesuits/spacesuits.dm
  name: Space helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `space`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "softsuit helmet" / Serenity: "Space helmet") -- verify these are truly the same item before swapping.

#### 24. emergency softsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/emergency` -- code/modules/clothing/spacesuits/spacesuits.dm
  name: emergency softsuit helmet -- icon: icons/obj/item/clothing/softsuits/softsuit_emergency.dmi -- icon_state: `softsuit_emergency_helmet`
- **Serenity**: `/obj/item/clothing/head/helmet/space/emergency` -- code/modules/clothing/spacesuits/miscellaneous.dm
  name: Emergency Space Helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `emergencyhelm`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 25. `/obj/item/clothing/head/helmet/space/rig` and subtypes (12 types)

- **Aurora**: `/obj/item/clothing/head/helmet/space/rig` + subtypes -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  icon: icons/obj/clothing/hats.dmi -- icon_state: `softsuit_helmet`
- **Serenity**: equivalent family -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  icon: icons/obj/clothing/hats.dmi -- icon_state: `space`
- Subtypes covered: `(base)`, `/ce`, `/combat`, `/ert`, `/eva`, `/hazard`, `/hazmat`, `/industrial`, `/light`, `/medical`, `/merc`, `/military`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 26. atmospherics voidsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/void/atmos` -- code/modules/clothing/spacesuits/void/station.dm
  name: atmospherics voidsuit helmet -- icon: icons/obj/clothing/voidsuit/station/engineering.dmi -- icon_state: `atmos_helm`
- **Serenity**: `/obj/item/clothing/head/helmet/space/void/atmos` -- code/modules/clothing/spacesuits/void/station.dm
  name: atmospherics voidsuit helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rig0-atmos`
- Confidence: HIGH -- identical type path structure and identical name ("atmospherics voidsuit helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 27. engineering voidsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/void/engineering` -- code/modules/clothing/spacesuits/void/station.dm
  name: engineering voidsuit helmet -- icon: icons/obj/clothing/voidsuit/station/engineering.dmi -- icon_state: `engineering_helm`
- **Serenity**: `/obj/item/clothing/head/helmet/space/void/engineering` -- code/modules/clothing/spacesuits/void/station.dm
  name: engineering voidsuit helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rig0-engineering`
- Confidence: HIGH -- identical type path structure and identical name ("engineering voidsuit helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 28. medical voidsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/void/medical` -- code/modules/clothing/spacesuits/void/station.dm
  name: medical voidsuit helmet -- icon: icons/obj/clothing/voidsuit/station/medical.dmi -- icon_state: `medical_helm`
- **Serenity**: `/obj/item/clothing/head/helmet/space/void/medical` -- code/modules/clothing/spacesuits/void/station.dm
  name: medical voidsuit helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rig0-medical`
- Confidence: HIGH -- identical type path structure and identical name ("medical voidsuit helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 29. blood-red voidsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/void/merc` -- code/modules/clothing/spacesuits/void/merc.dm
  name: blood-red voidsuit helmet -- icon: icons/obj/clothing/voidsuit/mercenary.dmi -- icon_state: `syndie_helm`
- **Serenity**: `/obj/item/clothing/head/helmet/space/void/merc` -- code/modules/clothing/spacesuits/void/merc.dm
  name: blood-red voidsuit helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rig0-syndie`
- Confidence: HIGH -- identical type path structure and identical name ("blood-red voidsuit helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 30. mining voidsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/void/mining` -- code/modules/clothing/spacesuits/void/station.dm
  name: mining voidsuit helmet -- icon: icons/obj/clothing/voidsuit/station/mining.dmi -- icon_state: `mining_helm`
- **Serenity**: `/obj/item/clothing/head/helmet/space/void/mining` -- code/modules/clothing/spacesuits/void/station.dm
  name: mining voidsuit helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rig0-mining`
- Confidence: HIGH -- identical type path structure and identical name ("mining voidsuit helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 31. security voidsuit helmet

- **Aurora**: `/obj/item/clothing/head/helmet/space/void/security` -- code/modules/clothing/spacesuits/void/station.dm
  name: security voidsuit helmet -- icon: icons/obj/clothing/voidsuit/station/security.dmi -- icon_state: `security_helm`
- **Serenity**: `/obj/item/clothing/head/helmet/space/void/security` -- code/modules/clothing/spacesuits/void/station.dm
  name: security voidsuit helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rig0-sec`
- Confidence: HIGH -- identical type path structure and identical name ("security voidsuit helmet").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 32. \improper SWAT helmet

- **Aurora**: `/obj/item/clothing/head/helmet/swat` -- code/modules/clothing/head/helmet.dm
  name: \improper SWAT helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `swat`
- **Serenity**: `/obj/item/clothing/head/helmet/swat` -- code/modules/clothing/head/helmet.dm
  name: \improper SWAT helmet -- icon: icons/obj/clothing/hats.dmi -- icon_state: `helmet_merc`
- Confidence: HIGH -- identical type path structure and identical name ("\improper SWAT helmet").

#### 33. hijab

- **Aurora**: `/obj/item/clothing/head/hijab` -- code/modules/clothing/head/misc.dm
  name: hijab -- icon: icons/obj/clothing/hijabs.dmi -- icon_state: `hijab`
- **Serenity**: `/obj/item/clothing/head/hijab` -- code/modules/clothing/head/misc.dm
  name: hijab -- icon: icons/obj/clothing/hats.dmi -- icon_state: `hijab`
- Confidence: HIGH -- identical type path structure and identical name ("hijab").

#### 34. radiation hood

- **Aurora**: `/obj/item/clothing/head/radiation` -- code/modules/clothing/suits/utility.dm
  name: radiation hood -- icon: icons/obj/item/clothing/head/radsuit.dmi -- icon_state: `radhood`
- **Serenity**: `/obj/item/clothing/head/radiation` -- code/modules/clothing/suits/utility.dm
  name: Radiation Hood -- icon: icons/obj/clothing/hats.dmi -- icon_state: `rad`
- Confidence: HIGH -- identical type path structure and identical name ("radiation hood").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 35. surgical cap

- **Aurora**: `/obj/item/clothing/head/surgery` -- code/modules/clothing/head/jobs.dm
  name: surgical cap -- icon: icons/obj/item/clothing/department_uniforms/medical.dmi -- icon_state: `surgcap_nt`
- **Serenity**: `/obj/item/clothing/head/surgery` -- code/modules/clothing/head/jobs.dm
  name: surgical cap -- icon: icons/obj/clothing/hats.dmi -- icon_state: `surgcap`
- Confidence: HIGH -- identical type path structure and identical name ("surgical cap").

#### 36. turban

- **Aurora**: `/obj/item/clothing/head/turban` -- code/modules/clothing/head/misc.dm
  name: turban -- icon: icons/obj/item/clothing/head/turban.dmi -- icon_state: `turban`
- **Serenity**: `/obj/item/clothing/head/turban` -- code/modules/clothing/head/misc.dm
  name: turban -- icon: icons/obj/clothing/hats.dmi -- icon_state: `turban`
- Confidence: HIGH -- identical type path structure and identical name ("turban").

#### 37. ushanka

- **Aurora**: `/obj/item/clothing/head/ushanka` -- code/modules/clothing/head/winter_hats.dm
  name: ushanka -- icon: icons/obj/item/clothing/head/ushanka.dmi -- icon_state: `ushanka`
- **Serenity**: `/obj/item/clothing/head/ushanka` -- code/modules/clothing/head/misc_special.dm
  name: ushanka -- icon: icons/obj/clothing/hats.dmi -- icon_state: `ushankadown`
- Confidence: HIGH -- identical type path structure and identical name ("ushanka").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 38. warden hat

- **Aurora**: `/obj/item/clothing/head/warden` -- code/modules/clothing/head/jobs.dm
  name: warden hat -- icon: icons/obj/item/clothing/department_uniforms/security.dmi -- icon_state: `nt_warden_hat`
- **Serenity**: `/obj/item/clothing/head/warden` -- code/modules/clothing/under/jobs/security.dm
  name: warden's hat -- icon: icons/obj/clothing/hats.dmi -- icon_state: `policehelm`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 39. winter hood

- **Aurora**: `/obj/item/clothing/head/winterhood` -- code/modules/clothing/suits/hoodies.dm
  name: winter hood -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatwinter_hood`
- **Serenity**: `/obj/item/clothing/head/winterhood` -- code/modules/clothing/suits/toggles.dm
  name: winter hood -- icon: icons/obj/clothing/hats.dmi -- icon_state: `generic_hood`
- Confidence: HIGH -- identical type path structure and identical name ("winter hood").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

---

## Clothing - Masks (12)

#### 1. balaclava

- **Aurora**: `/obj/item/clothing/mask/balaclava` -- code/modules/clothing/masks/boxing.dm
  name: balaclava -- icon: icons/obj/clothing/masks.dmi -- icon_state: `balaclava_black`
- **Serenity**: `/obj/item/clothing/mask/balaclava` -- code/modules/clothing/masks/boxing.dm
  name: balaclava -- icon: icons/obj/clothing/masks.dmi -- icon_state: `balaclava`
- Confidence: HIGH -- identical type path structure and identical name ("balaclava").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. gas mask

- **Aurora**: `/obj/item/clothing/mask/chameleon` -- code/modules/clothing/chameleon.dm
  name: gas mask -- icon: icons/obj/clothing/masks.dmi -- icon_state: `gas_alt`
- **Serenity**: `/obj/item/clothing/mask/chameleon` -- code/modules/clothing/chameleon.dm
  name: gas mask -- icon: icons/obj/clothing/masks.dmi -- icon_state: `fullgas`
- Confidence: HIGH -- identical type path structure and identical name ("gas mask").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 3. gas mask

- **Aurora**: `/obj/item/clothing/mask/gas` -- code/modules/clothing/masks/gasmask.dm
  name: gas mask -- icon: icons/obj/clothing/masks.dmi -- icon_state: `gas_alt`
- **Serenity**: `/obj/item/clothing/mask/gas` -- code/modules/clothing/masks/gasmask.dm
  name: gas mask -- icon: icons/obj/clothing/masks.dmi -- icon_state: `fullgas`
- Confidence: HIGH -- identical type path structure and identical name ("gas mask").

#### 4. cigarette

- **Aurora**: `/obj/item/clothing/mask/smokable/cigarette` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigarette -- icon: _(unset -- inherited/default)_ -- icon_state: `cigoff`
- **Serenity**: `/obj/item/clothing/mask/smokable/cigarette` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigarette -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigoff`
- Confidence: HIGH -- identical type path structure and identical name ("cigarette").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 5. premium cigar

- **Aurora**: `/obj/item/clothing/mask/smokable/cigarette/cigar` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: premium cigar -- icon: _(unset -- inherited/default)_ -- icon_state: `cigaroff`
- **Serenity**: `/obj/item/clothing/mask/smokable/cigarette/cigar` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: premium cigar -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigar2off`
- Confidence: HIGH -- identical type path structure and identical name ("premium cigar").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 6. \improper Cohiba robusto cigar

- **Aurora**: `/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: \improper Cohiba robusto cigar -- icon: _(unset -- inherited/default)_ -- icon_state: `cigar2off`
- **Serenity**: `/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: \improper Cohiba Robusto cigar -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigar2off`
- Confidence: HIGH -- identical type path structure and identical name ("\improper Cohiba robusto cigar").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 7. premium Havanian cigar

- **Aurora**: `/obj/item/clothing/mask/smokable/cigarette/cigar/havana` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: premium Havanian cigar -- icon: _(unset -- inherited/default)_ -- icon_state: `cigar2off`
- **Serenity**: `/obj/item/clothing/mask/smokable/cigarette/cigar/havana` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: premium Havanian cigar -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigar2off`
- Confidence: HIGH -- identical type path structure and identical name ("premium Havanian cigar").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 8. cigarette

- **Aurora**: `/obj/item/clothing/mask/smokable/cigarette/dromedaryco` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigarette -- icon: _(unset -- inherited/default)_ -- icon_state: `cigoff`
- **Serenity**: `/obj/item/clothing/mask/smokable/cigarette/dromedaryco` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigarette -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigoff`
- Confidence: HIGH -- identical type path structure and identical name ("cigarette").

#### 9. rolled cigarette

- **Aurora**: `/obj/item/clothing/mask/smokable/cigarette/rolled` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: rolled cigarette -- icon: _(unset -- inherited/default)_ -- icon_state: `cigrolloff`
- **Serenity**: `/obj/item/clothing/mask/smokable/cigarette/rolled` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: rolled cigarette -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigroll`
- Confidence: HIGH -- identical type path structure and identical name ("rolled cigarette").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 10. smoking pipe

- **Aurora**: `/obj/item/clothing/mask/smokable/pipe` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: smoking pipe -- icon: _(unset -- inherited/default)_ -- icon_state: `pipeoff`
- **Serenity**: `/obj/item/clothing/mask/smokable/pipe` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: smoking pipe -- icon: icons/obj/clothing/masks.dmi -- icon_state: `pipeoff`
- Confidence: HIGH -- identical type path structure and identical name ("smoking pipe").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 11. corn cob pipe

- **Aurora**: `/obj/item/clothing/mask/smokable/pipe/cobpipe` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: corn cob pipe -- icon: _(unset -- inherited/default)_ -- icon_state: `cobpipeoff`
- **Serenity**: `/obj/item/clothing/mask/smokable/pipe/cobpipe` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: corn cob pipe -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cobpipeoff`
- Confidence: HIGH -- identical type path structure and identical name ("corn cob pipe").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 12. surgical mask

- **Aurora**: `/obj/item/clothing/mask/surgical` -- code/modules/clothing/masks/miscellaneous.dm
  name: surgical mask -- icon: icons/obj/clothing/masks.dmi -- icon_state: `surgical`
- **Serenity**: `/obj/item/clothing/mask/surgical` -- code/modules/clothing/masks/miscellaneous.dm
  name: sterile mask -- icon: icons/obj/clothing/masks.dmi -- icon_state: `sterile`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

---

## Clothing - Glasses (8)

#### 1. health scanner HUD

- **Aurora**: `/obj/item/clothing/glasses/hud/health` -- code/modules/clothing/glasses/hud.dm
  name: health scanner HUD -- icon: icons/obj/item/clothing/eyes/med_hud.dmi -- icon_state: `healthhud`
- **Serenity**: `/obj/item/clothing/glasses/hud/health` -- code/modules/clothing/glasses/hud.dm
  name: health scanner HUD -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `healthhud`
- Confidence: HIGH -- identical type path structure and identical name ("health scanner HUD").

#### 2. prescription glasses/HUD assembly

- **Aurora**: `/obj/item/clothing/glasses/hud/health/prescription` -- code/modules/clothing/glasses/hud.dm
  name: prescription glasses/HUD assembly -- icon: icons/obj/item/clothing/eyes/med_hud.dmi -- icon_state: `healthhudpresc`
- **Serenity**: `/obj/item/clothing/glasses/hud/health/prescription` -- code/modules/clothing/glasses/hud.dm
  name: prescription health scanner HUD -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `healthhudpresc`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "prescription glasses/HUD assembly" / Serenity: "prescription health scanner HUD") -- verify these are truly the same item before swapping.

#### 3. security HUD

- **Aurora**: `/obj/item/clothing/glasses/hud/security` -- code/modules/clothing/glasses/hud.dm
  name: security HUD -- icon: icons/obj/item/clothing/eyes/sec_hud.dmi -- icon_state: `securityhud`
- **Serenity**: `/obj/item/clothing/glasses/hud/security` -- code/modules/clothing/glasses/hud.dm
  name: security HUD -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `securityhud`
- Confidence: HIGH -- identical type path structure and identical name ("security HUD").

#### 4. augmented shades

- **Aurora**: `/obj/item/clothing/glasses/hud/security/jensenshades` -- code/modules/clothing/glasses/hud.dm
  name: augmented shades -- icon: icons/obj/item/clothing/eyes/sec_hud.dmi -- icon_state: `jensenshades`
- **Serenity**: `/obj/item/clothing/glasses/hud/security/jensenshades` -- code/modules/clothing/glasses/hud.dm
  name: augmented shades -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `jensenshades`
- Confidence: HIGH -- identical type path structure and identical name ("augmented shades").

#### 5. prescription glasses/HUD assembly

- **Aurora**: `/obj/item/clothing/glasses/hud/security/prescription` -- code/modules/clothing/glasses/hud.dm
  name: prescription glasses/HUD assembly -- icon: icons/obj/item/clothing/eyes/sec_hud.dmi -- icon_state: `sechudpresc`
- **Serenity**: `/obj/item/clothing/glasses/hud/security/prescription` -- code/modules/clothing/glasses/hud.dm
  name: prescription security HUD -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `sechudpresc`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 6. scanning goggles

- **Aurora**: `/obj/item/clothing/glasses/regular/scanners` -- code/modules/clothing/glasses/glasses.dm
  name: scanning goggles -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `scanning`
- **Serenity**: `/obj/item/clothing/glasses/regular/scanners` -- code/modules/clothing/glasses/glasses.dm
  name: scanning goggles -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `uzenwa_sissra_1`
- Confidence: HIGH -- identical type path structure and identical name ("scanning goggles").

#### 7. HUDsunglasses

- **Aurora**: `/obj/item/clothing/glasses/sunglasses/sechud` -- code/modules/clothing/glasses/glasses.dm
  name: HUDsunglasses -- icon: icons/obj/item/clothing/eyes/sec_hud.dmi -- icon_state: `sunhud`
- **Serenity**: `/obj/item/clothing/glasses/sunglasses/sechud` -- code/modules/clothing/glasses/glasses.dm
  name: HUD sunglasses -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `sunhud`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 8. thermonocle

- **Aurora**: `/obj/item/clothing/glasses/thermal/plain/monocle` -- code/modules/clothing/glasses/glasses.dm
  name: thermonocle -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `thermonocle`
- **Serenity**: `/obj/item/clothing/glasses/thermal/plain/monocle` -- code/modules/clothing/glasses/glasses.dm
  name: thermoncle -- icon: icons/obj/clothing/glasses.dmi -- icon_state: `thermoncle`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

---

## Clothing - Ears (15)

#### 1. ears

- **Aurora**: `/obj/item/clothing/ears` -- code/modules/clothing/clothing.dm
  name: ears -- icon: icons/obj/clothing/ears.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/clothing/ears` -- code/modules/clothing/clothing.dm
  name: ears -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("ears").

#### 2. earmuffs

- **Aurora**: `/obj/item/clothing/ears/earmuffs` -- code/modules/clothing/ears/earmuffs.dm
  name: earmuffs -- icon: icons/obj/clothing/ears/earmuffs.dmi -- icon_state: `earmuffs`
- **Serenity**: `/obj/item/clothing/ears/earmuffs` -- code/modules/clothing/clothing.dm
  name: earmuffs -- icon: icons/obj/items.dmi -- icon_state: `earmuffs`
- Confidence: HIGH -- identical type path structure and identical name ("earmuffs").

#### 3. stud earrings

- **Aurora**: `/obj/item/clothing/ears/earring` -- code/modules/clothing/ears/earrings.dm
  name: stud earrings -- icon: icons/obj/item/clothing/ears/earrings.dmi -- icon_state: `stud`
- **Serenity**: `/obj/item/clothing/ears/earring` -- code/modules/clothing/ears/earrings.dm
  name: earring -- icon: icons/obj/clothing/ears.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 4. dangle earrings

- **Aurora**: `/obj/item/clothing/ears/earring/dangle` -- code/modules/clothing/ears/earrings.dm
  name: dangle earrings -- icon: icons/obj/item/clothing/ears/earrings.dmi -- icon_state: `dangle`
- **Serenity**: `/obj/item/clothing/ears/earring/dangle` -- code/modules/clothing/ears/earrings.dm
  name: earring -- icon: icons/obj/clothing/ears.dmi -- icon_state: `ear_dangle`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 5. skrell tentacle wear

- **Aurora**: `/obj/item/clothing/ears/skrell` -- code/modules/clothing/ears/xeno/skrell.dm
  name: skrell tentacle wear -- icon: icons/obj/item/clothing/ears/skrell/chains.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/clothing/ears/skrell` -- code/modules/clothing/ears/skrell.dm
  name: skrell headtail wear -- icon: icons/obj/clothing/ears.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 6. gold headtail bands

- **Aurora**: `/obj/item/clothing/ears/skrell/band` -- code/modules/clothing/ears/xeno/skrell.dm
  name: gold headtail bands -- icon: icons/obj/item/clothing/ears/skrell/bands.dmi -- icon_state: `skrell_band`
- **Serenity**: `/obj/item/clothing/ears/skrell/band` -- code/modules/clothing/ears/skrell.dm
  name: gold headtail bands -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_band`
- Confidence: HIGH -- identical type path structure and identical name ("gold headtail bands").

#### 7. blue jeweled golden headtail bands

- **Aurora**: `/obj/item/clothing/ears/skrell/band/bluejewels` -- code/modules/clothing/ears/xeno/skrell.dm
  name: blue jeweled golden headtail bands -- icon: icons/obj/item/clothing/ears/skrell/bands.dmi -- icon_state: `skrell_band_bjewel`
- **Serenity**: `/obj/item/clothing/ears/skrell/band/bluejewels` -- code/modules/clothing/ears/skrell.dm
  name: blue jeweled golden headtail bands -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_band_bjewel`
- Confidence: HIGH -- identical type path structure and identical name ("blue jeweled golden headtail bands").

#### 8. ebony headtail bands

- **Aurora**: `/obj/item/clothing/ears/skrell/band/ebony` -- code/modules/clothing/ears/xeno/skrell.dm
  name: ebony headtail bands -- icon: icons/obj/item/clothing/ears/skrell/bands.dmi -- icon_state: `skrell_band_ebony`
- **Serenity**: `/obj/item/clothing/ears/skrell/band/ebony` -- code/modules/clothing/ears/skrell.dm
  name: ebony headtail bands -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_band_ebony`
- Confidence: HIGH -- identical type path structure and identical name ("ebony headtail bands").

#### 9. red jeweled golden headtail bands

- **Aurora**: `/obj/item/clothing/ears/skrell/band/redjewels` -- code/modules/clothing/ears/xeno/skrell.dm
  name: red jeweled golden headtail bands -- icon: icons/obj/item/clothing/ears/skrell/bands.dmi -- icon_state: `skrell_band_rjewel`
- **Serenity**: `/obj/item/clothing/ears/skrell/band/redjewels` -- code/modules/clothing/ears/skrell.dm
  name: red jeweled golden headtail bands -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_band_rjewel`
- Confidence: HIGH -- identical type path structure and identical name ("red jeweled golden headtail bands").

#### 10. silver headtail bands

- **Aurora**: `/obj/item/clothing/ears/skrell/band/silver` -- code/modules/clothing/ears/xeno/skrell.dm
  name: silver headtail bands -- icon: icons/obj/item/clothing/ears/skrell/bands.dmi -- icon_state: `skrell_band_sil`
- **Serenity**: `/obj/item/clothing/ears/skrell/band/silver` -- code/modules/clothing/ears/skrell.dm
  name: silver headtail bands -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_band_sil`
- Confidence: HIGH -- identical type path structure and identical name ("silver headtail bands").

#### 11. gold headtail chains

- **Aurora**: `/obj/item/clothing/ears/skrell/chain` -- code/modules/clothing/ears/xeno/skrell.dm
  name: gold headtail chains -- icon: icons/obj/item/clothing/ears/skrell/chains.dmi -- icon_state: `skrell_chain`
- **Serenity**: `/obj/item/clothing/ears/skrell/chain` -- code/modules/clothing/ears/skrell.dm
  name: gold headtail chains -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_chain`
- Confidence: HIGH -- identical type path structure and identical name ("gold headtail chains").

#### 12. blue jeweled golden headtail chains

- **Aurora**: `/obj/item/clothing/ears/skrell/chain/bluejewels` -- code/modules/clothing/ears/xeno/skrell.dm
  name: blue jeweled golden headtail chains -- icon: icons/obj/item/clothing/ears/skrell/chains.dmi -- icon_state: `skrell_chain_bjewel`
- **Serenity**: `/obj/item/clothing/ears/skrell/chain/bluejewels` -- code/modules/clothing/ears/skrell.dm
  name: blue jeweled golden headtail chains -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_chain_bjewel`
- Confidence: HIGH -- identical type path structure and identical name ("blue jeweled golden headtail chains").

#### 13. ebony headtail chains

- **Aurora**: `/obj/item/clothing/ears/skrell/chain/ebony` -- code/modules/clothing/ears/xeno/skrell.dm
  name: ebony headtail chains -- icon: icons/obj/item/clothing/ears/skrell/chains.dmi -- icon_state: `skrell_chain_ebony`
- **Serenity**: `/obj/item/clothing/ears/skrell/chain/ebony` -- code/modules/clothing/ears/skrell.dm
  name: ebony headtail chains -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_chain_ebony`
- Confidence: HIGH -- identical type path structure and identical name ("ebony headtail chains").

#### 14. red jeweled golden headtail chains

- **Aurora**: `/obj/item/clothing/ears/skrell/chain/redjewels` -- code/modules/clothing/ears/xeno/skrell.dm
  name: red jeweled golden headtail chains -- icon: icons/obj/item/clothing/ears/skrell/chains.dmi -- icon_state: `skrell_chain_rjewel`
- **Serenity**: `/obj/item/clothing/ears/skrell/chain/redjewels` -- code/modules/clothing/ears/skrell.dm
  name: red jeweled golden headtail chains -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_chain_rjewel`
- Confidence: HIGH -- identical type path structure and identical name ("red jeweled golden headtail chains").

#### 15. silver headtail chains

- **Aurora**: `/obj/item/clothing/ears/skrell/chain/silver` -- code/modules/clothing/ears/xeno/skrell.dm
  name: silver headtail chains -- icon: icons/obj/item/clothing/ears/skrell/chains.dmi -- icon_state: `skrell_chain_sil`
- **Serenity**: `/obj/item/clothing/ears/skrell/chain/silver` -- code/modules/clothing/ears/skrell.dm
  name: silver headtail chains -- icon: icons/obj/clothing/ears.dmi -- icon_state: `skrell_chain_sil`
- Confidence: HIGH -- identical type path structure and identical name ("silver headtail chains").

---

## Clothing - Gloves (1)

#### 1. captain's gloves

- **Aurora**: `/obj/item/clothing/gloves/captain` -- code/modules/clothing/sets/captain.dm
  name: captain's gloves -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `captain_gloves`
- **Serenity**: `/obj/item/clothing/gloves/captain` -- code/modules/clothing/gloves/miscellaneous.dm
  name: captain's gloves -- icon: icons/obj/clothing/gloves.dmi -- icon_state: `captain`
- Confidence: HIGH -- identical type path structure and identical name ("captain's gloves").

---

## Clothing - Shoes (17)

#### 1. shoes

- **Aurora**: `/obj/item/clothing/shoes` -- code/modules/clothing/clothing.dm
  name: shoes -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/clothing/shoes` -- code/modules/clothing/clothing.dm
  name: shoes -- icon: icons/obj/clothing/shoes.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("shoes").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. black shoes

- **Aurora**: `/obj/item/clothing/shoes/chameleon` -- code/modules/clothing/chameleon.dm
  name: black shoes -- icon: icons/obj/item/clothing/shoes/sneakers.dmi -- icon_state: `black`
- **Serenity**: `/obj/item/clothing/shoes/chameleon` -- code/modules/clothing/chameleon.dm
  name: black shoes -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `black`
- Confidence: HIGH -- identical type path structure and identical name ("black shoes").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 3. combat boots

- **Aurora**: `/obj/item/clothing/shoes/combat` -- code/modules/clothing/shoes/boots.dm
  name: combat boots -- icon: icons/obj/item/clothing/shoes/boots.dmi -- icon_state: `combat`
- **Serenity**: `/obj/item/clothing/shoes/combat` -- code/modules/clothing/shoes/miscellaneous.dm
  name: combat boots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `jungle`
- Confidence: HIGH -- identical type path structure and identical name ("combat boots").

#### 4. cyborg boots

- **Aurora**: `/obj/item/clothing/shoes/cyborg` -- code/modules/clothing/shoes/miscellaneous.dm
  name: cyborg boots -- icon: icons/obj/items.dmi -- icon_state: `jackboots`
- **Serenity**: `/obj/item/clothing/shoes/cyborg` -- code/modules/clothing/shoes/miscellaneous.dm
  name: cyborg boots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `boots`
- Confidence: HIGH -- identical type path structure and identical name ("cyborg boots").

#### 5. black dress flats

- **Aurora**: `/obj/item/clothing/shoes/flats` -- code/modules/clothing/shoes/sneakers.dm
  name: black dress flats -- icon: icons/obj/item/clothing/shoes/flats.dmi -- icon_state: `blackdf`
- **Serenity**: `/obj/item/clothing/shoes/flats` -- code/modules/clothing/shoes/colour.dm
  name: flats -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `flatswhite`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "black dress flats" / Serenity: "flats") -- verify these are truly the same item before swapping.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. galoshes

- **Aurora**: `/obj/item/clothing/shoes/galoshes` -- code/modules/clothing/shoes/miscellaneous.dm
  name: galoshes -- icon: icons/obj/item/clothing/shoes/miscellaneous.dmi -- icon_state: `galoshes`
- **Serenity**: `/obj/item/clothing/shoes/galoshes` -- code/modules/clothing/shoes/jobs.dm
  name: galoshes -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `galoshes`
- Confidence: HIGH -- identical type path structure and identical name ("galoshes").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. jackboots

- **Aurora**: `/obj/item/clothing/shoes/jackboots` -- code/modules/clothing/shoes/boots.dm
  name: jackboots -- icon: icons/obj/item/clothing/shoes/boots.dmi -- icon_state: `jackboots`
- **Serenity**: `/obj/item/clothing/shoes/jackboots` -- code/modules/clothing/shoes/jobs.dm
  name: jackboots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `jackboots`
- Confidence: HIGH -- identical type path structure and identical name ("jackboots").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 8. black oxford shoes

- **Aurora**: `/obj/item/clothing/shoes/laceup` -- code/modules/clothing/shoes/oxfords.dm
  name: black oxford shoes -- icon: icons/obj/item/clothing/shoes/oxford.dmi -- icon_state: `oxford_black`
- **Serenity**: `/obj/item/clothing/shoes/laceup` -- code/modules/clothing/shoes/miscellaneous.dm
  name: laceup shoes -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `laceups`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 9. boots

- **Aurora**: `/obj/item/clothing/shoes/lightrig` -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  name: boots -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/clothing/shoes/lightrig` -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  name: boots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("boots").

#### 10. boots

- **Aurora**: `/obj/item/clothing/shoes/lightrig/hacker` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: boots -- icon: icons/obj/items.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/clothing/shoes/lightrig/hacker` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: boots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("boots").

#### 11. magboots

- **Aurora**: `/obj/item/clothing/shoes/magboots` -- code/modules/clothing/shoes/magboots.dm
  name: magboots -- icon: icons/obj/item/clothing/shoes/magboots.dmi -- icon_state: `magboots0`
- **Serenity**: `/obj/item/clothing/shoes/magboots` -- code/modules/clothing/shoes/magboots.dm
  name: magboots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `magboots0`
- Confidence: HIGH -- identical type path structure and identical name ("magboots").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 12. boots

- **Aurora**: `/obj/item/clothing/shoes/magboots/rig` -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  name: boots -- icon: icons/obj/item/clothing/shoes/magboots.dmi -- icon_state: `magboots0`
- **Serenity**: `/obj/item/clothing/shoes/magboots/rig` -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  name: boots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `magboots0`
- Confidence: HIGH -- identical type path structure and identical name ("boots").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 13. shoes

- **Aurora**: `/obj/item/clothing/shoes/magboots/rig/light` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: shoes -- icon: icons/obj/item/clothing/shoes/magboots.dmi -- icon_state: `magboots0`
- **Serenity**: `/obj/item/clothing/shoes/magboots/rig/light` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: shoes -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `magboots0`
- Confidence: HIGH -- identical type path structure and identical name ("shoes").

#### 14. bunny slippers

- **Aurora**: `/obj/item/clothing/shoes/slippers` -- code/modules/clothing/shoes/slippers.dm
  name: bunny slippers -- icon: icons/obj/item/clothing/shoes/slippers.dmi -- icon_state: `slippers`
- **Serenity**: `/obj/item/clothing/shoes/slippers` -- code/modules/clothing/shoes/miscellaneous.dm
  name: bunny slippers -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `slippers`
- Confidence: HIGH -- identical type path structure and identical name ("bunny slippers").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 15. swimming fins

- **Aurora**: `/obj/item/clothing/shoes/swimmingfins` -- code/modules/clothing/shoes/miscellaneous.dm
  name: swimming fins -- icon: icons/obj/item/clothing/shoes/miscellaneous.dmi -- icon_state: `flippers`
- **Serenity**: `/obj/item/clothing/shoes/swimmingfins` -- code/modules/clothing/shoes/miscellaneous.dm
  name: swimming fins -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `flippers`
- Confidence: HIGH -- identical type path structure and identical name ("swimming fins").

#### 16. workboots

- **Aurora**: `/obj/item/clothing/shoes/workboots` -- code/modules/clothing/shoes/boots.dm
  name: workboots -- icon: icons/obj/item/clothing/shoes/boots.dmi -- icon_state: `workboots`
- **Serenity**: `/obj/item/clothing/shoes/workboots` -- code/modules/clothing/shoes/jobs.dm
  name: workboots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `workboots`
- Confidence: HIGH -- identical type path structure and identical name ("workboots").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 17. toe-less workboots

- **Aurora**: `/obj/item/clothing/shoes/workboots/toeless` -- code/modules/clothing/shoes/boots.dm
  name: toe-less workboots -- icon: icons/obj/item/clothing/shoes/boots.dmi -- icon_state: `workboots_toeless`
- **Serenity**: `/obj/item/clothing/shoes/workboots/toeless` -- code/modules/clothing/shoes/jobs.dm
  name: toe-less workboots -- icon: icons/obj/clothing/shoes.dmi -- icon_state: `workbootstoeless`
- Confidence: HIGH -- identical type path structure and identical name ("toe-less workboots").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

---

## Clothing - Suits (38)

#### 1. officer jacket

- **Aurora**: `/obj/item/clothing/suit/armor/swat/officer` -- code/modules/clothing/suits/armor.dm
  name: officer jacket -- icon: icons/obj/clothing/suits.dmi -- icon_state: `detective`
- **Serenity**: `/obj/item/clothing/suit/armor/swat/officer` -- code/modules/clothing/suits/armor.dm
  name: officer jacket -- icon: _(unset -- inherited/default)_ -- icon_state: `detective`
- Confidence: HIGH -- identical type path structure and identical name ("officer jacket").

#### 2. armored vest

- **Aurora**: `/obj/item/clothing/suit/armor/vest` -- code/modules/clothing/suits/armor.dm
  name: armored vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `armor`
- **Serenity**: `/obj/item/clothing/suit/armor/vest` -- code/modules/clothing/suits/armor.dm
  name: armored vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `kvest`
- Confidence: HIGH -- identical type path structure and identical name ("armored vest").

#### 3. captain's uniform jacket

- **Aurora**: `/obj/item/clothing/suit/captunic/capjacket` -- code/modules/clothing/sets/captain.dm
  name: captain's uniform jacket -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `captain_alt_jacket`
- **Serenity**: `/obj/item/clothing/suit/captunic/capjacket` -- code/modules/clothing/suits/jobs.dm
  name: captain's uniform jacket -- icon: _(unset -- inherited/default)_ -- icon_state: `capjacket`
- Confidence: HIGH -- identical type path structure and identical name ("captain's uniform jacket").

#### 4. firesuit

- **Aurora**: `/obj/item/clothing/suit/fire` -- code/modules/clothing/suits/utility.dm
  name: firesuit -- icon: icons/obj/item/clothing/suit/firefighter.dmi -- icon_state: `firesuit`
- **Serenity**: `/obj/item/clothing/suit/fire` -- code/modules/clothing/suits/utility.dm
  name: firesuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `fire`
- Confidence: HIGH -- identical type path structure and identical name ("firesuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 5. radiation suit

- **Aurora**: `/obj/item/clothing/suit/radiation` -- code/modules/clothing/suits/utility.dm
  name: radiation suit -- icon: icons/obj/item/clothing/suit/radsuit.dmi -- icon_state: `radsuit`
- **Serenity**: `/obj/item/clothing/suit/radiation` -- code/modules/clothing/suits/utility.dm
  name: Radiation suit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rad`
- Confidence: HIGH -- identical type path structure and identical name ("radiation suit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. softsuit

- **Aurora**: `/obj/item/clothing/suit/space` -- code/modules/clothing/spacesuits/breaches.dm
  name: softsuit -- icon: icons/obj/item/clothing/softsuits/softsuit.dmi -- icon_state: `softsuit`
- **Serenity**: `/obj/item/clothing/suit/space` -- code/modules/clothing/spacesuits/breaches.dm
  name: Space suit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `space`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "softsuit" / Serenity: "Space suit") -- verify these are truly the same item before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 7. emergency softsuit

- **Aurora**: `/obj/item/clothing/suit/space/emergency` -- code/modules/clothing/spacesuits/spacesuits.dm
  name: emergency softsuit -- icon: icons/obj/item/clothing/softsuits/softsuit_emergency.dmi -- icon_state: `softsuit_emergency`
- **Serenity**: `/obj/item/clothing/suit/space/emergency` -- code/modules/clothing/spacesuits/miscellaneous.dm
  name: Emergency Softsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `syndicate-orange`
- Confidence: HIGH -- identical type path structure and identical name ("emergency softsuit").

#### 8. `/obj/item/clothing/suit/space/rig` and subtypes (4 types)

- **Aurora**: `/obj/item/clothing/suit/space/rig` + subtypes -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  icon: icons/obj/clothing/suits.dmi -- icon_state: `softsuit`
- **Serenity**: equivalent family -- code/modules/clothing/spacesuits/rig/rig_pieces.dm
  icon: icons/obj/clothing/suits.dmi -- icon_state: `space`
- Subtypes covered: `(base)`, `/industrial`, `/light`, `/light/ninja`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 9. atmos voidsuit

- **Aurora**: `/obj/item/clothing/suit/space/void/atmos` -- code/modules/clothing/spacesuits/void/station.dm
  name: atmos voidsuit -- icon: icons/obj/clothing/voidsuit/station/engineering.dmi -- icon_state: `atmos`
- **Serenity**: `/obj/item/clothing/suit/space/void/atmos` -- code/modules/clothing/spacesuits/void/station.dm
  name: atmos voidsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rig-atmos`
- Confidence: HIGH -- identical type path structure and identical name ("atmos voidsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 10. engineering voidsuit

- **Aurora**: `/obj/item/clothing/suit/space/void/engineering` -- code/modules/clothing/spacesuits/void/station.dm
  name: engineering voidsuit -- icon: icons/obj/clothing/voidsuit/station/engineering.dmi -- icon_state: `engineering`
- **Serenity**: `/obj/item/clothing/suit/space/void/engineering` -- code/modules/clothing/spacesuits/void/station.dm
  name: engineering voidsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rig-engineering`
- Confidence: HIGH -- identical type path structure and identical name ("engineering voidsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 11. medical voidsuit

- **Aurora**: `/obj/item/clothing/suit/space/void/medical` -- code/modules/clothing/spacesuits/void/station.dm
  name: medical voidsuit -- icon: icons/obj/clothing/voidsuit/station/medical.dmi -- icon_state: `medical`
- **Serenity**: `/obj/item/clothing/suit/space/void/medical` -- code/modules/clothing/spacesuits/void/station.dm
  name: medical voidsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rig-medical`
- Confidence: HIGH -- identical type path structure and identical name ("medical voidsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 12. blood-red voidsuit

- **Aurora**: `/obj/item/clothing/suit/space/void/merc` -- code/modules/clothing/spacesuits/void/merc.dm
  name: blood-red voidsuit -- icon: icons/obj/clothing/voidsuit/mercenary.dmi -- icon_state: `syndie`
- **Serenity**: `/obj/item/clothing/suit/space/void/merc` -- code/modules/clothing/spacesuits/void/merc.dm
  name: blood-red voidsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rig-syndie`
- Confidence: HIGH -- identical type path structure and identical name ("blood-red voidsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 13. mining voidsuit

- **Aurora**: `/obj/item/clothing/suit/space/void/mining` -- code/modules/clothing/spacesuits/void/station.dm
  name: mining voidsuit -- icon: icons/obj/clothing/voidsuit/station/mining.dmi -- icon_state: `mining`
- **Serenity**: `/obj/item/clothing/suit/space/void/mining` -- code/modules/clothing/spacesuits/void/station.dm
  name: mining voidsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rig-mining`
- Confidence: HIGH -- identical type path structure and identical name ("mining voidsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 14. security voidsuit

- **Aurora**: `/obj/item/clothing/suit/space/void/security` -- code/modules/clothing/spacesuits/void/station.dm
  name: security voidsuit -- icon: icons/obj/clothing/voidsuit/station/security.dmi -- icon_state: `security`
- **Serenity**: `/obj/item/clothing/suit/space/void/security` -- code/modules/clothing/spacesuits/void/station.dm
  name: security voidsuit -- icon: icons/obj/clothing/suits.dmi -- icon_state: `rig-sec`
- Confidence: HIGH -- identical type path structure and identical name ("security voidsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 15. hazard vest

- **Aurora**: `/obj/item/clothing/suit/storage/hazardvest` -- code/modules/clothing/suits/hazardvests.dm
  name: hazard vest -- icon: icons/mob/clothing/suit/hazardvest.dmi -- icon_state: `hazard`
- **Serenity**: `/obj/item/clothing/suit/storage/hazardvest` -- code/modules/clothing/suits/jobs.dm
  name: hazard vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `hazard`
- Confidence: HIGH -- identical type path structure and identical name ("hazard vest").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 16. blue hazard vest

- **Aurora**: `/obj/item/clothing/suit/storage/hazardvest/blue` -- code/modules/clothing/suits/hazardvests.dm
  name: blue hazard vest -- icon: icons/mob/clothing/suit/hazardvest.dmi -- icon_state: `hazard_b`
- **Serenity**: `/obj/item/clothing/suit/storage/hazardvest/blue` -- code/modules/clothing/suits/jobs.dm
  name: blue hazard vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `hazard_b`
- Confidence: HIGH -- identical type path structure and identical name ("blue hazard vest").

#### 17. green hazard vest

- **Aurora**: `/obj/item/clothing/suit/storage/hazardvest/green` -- code/modules/clothing/suits/hazardvests.dm
  name: green hazard vest -- icon: icons/mob/clothing/suit/hazardvest.dmi -- icon_state: `hazard_g`
- **Serenity**: `/obj/item/clothing/suit/storage/hazardvest/green` -- code/modules/clothing/suits/jobs.dm
  name: green hazard vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `hazard_g`
- Confidence: HIGH -- identical type path structure and identical name ("green hazard vest").

#### 18. white hazard vest

- **Aurora**: `/obj/item/clothing/suit/storage/hazardvest/white` -- code/modules/clothing/suits/hazardvests.dm
  name: white hazard vest -- icon: icons/mob/clothing/suit/hazardvest.dmi -- icon_state: `hazard_w`
- **Serenity**: `/obj/item/clothing/suit/storage/hazardvest/white` -- code/modules/clothing/suits/jobs.dm
  name: white hazard vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `hazard_w`
- Confidence: HIGH -- identical type path structure and identical name ("white hazard vest").

#### 19. winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat` -- code/modules/clothing/suits/hoodies.dm
  name: winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatwinter`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat` -- code/modules/clothing/suits/toggles.dm
  name: winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatwinter`
- Confidence: HIGH -- identical type path structure and identical name ("winter coat").

#### 20. captain's winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/captain` -- code/modules/clothing/suits/hoodies.dm
  name: captain's winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatcaptain`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/captain` -- code/modules/clothing/suits/toggles.dm
  name: captain's winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatcaptain`
- Confidence: HIGH -- identical type path structure and identical name ("captain's winter coat").

#### 21. operations winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/cargo` -- code/modules/clothing/suits/hoodies.dm
  name: operations winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatcargo`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/cargo` -- code/modules/clothing/suits/toggles.dm
  name: cargo winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatcargo`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 22. engineering winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/engineering` -- code/modules/clothing/suits/hoodies.dm
  name: engineering winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatengineer`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/engineering` -- code/modules/clothing/suits/toggles.dm
  name: engineering winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatengineer`
- Confidence: HIGH -- identical type path structure and identical name ("engineering winter coat").

#### 23. atmospherics winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/engineering/atmos` -- code/modules/clothing/suits/hoodies.dm
  name: atmospherics winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatatmos`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/engineering/atmos` -- code/modules/clothing/suits/toggles.dm
  name: atmospherics winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatatmos`
- Confidence: HIGH -- identical type path structure and identical name ("atmospherics winter coat").

#### 24. hydroponics winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/hydro` -- code/modules/clothing/suits/hoodies.dm
  name: hydroponics winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coathydro`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/hydro` -- code/modules/clothing/suits/toggles.dm
  name: hydroponics winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coathydro`
- Confidence: HIGH -- identical type path structure and identical name ("hydroponics winter coat").

#### 25. medical winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/medical` -- code/modules/clothing/suits/hoodies.dm
  name: medical winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatmedical`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/medical` -- code/modules/clothing/suits/toggles.dm
  name: medical winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatmedical`
- Confidence: HIGH -- identical type path structure and identical name ("medical winter coat").

#### 26. mining winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/miner` -- code/modules/clothing/suits/hoodies.dm
  name: mining winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatminer`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/miner` -- code/modules/clothing/suits/toggles.dm
  name: mining winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatminer`
- Confidence: HIGH -- identical type path structure and identical name ("mining winter coat").

#### 27. science winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/science` -- code/modules/clothing/suits/hoodies.dm
  name: science winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatscience`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/science` -- code/modules/clothing/suits/toggles.dm
  name: science winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatscience`
- Confidence: HIGH -- identical type path structure and identical name ("science winter coat").

#### 28. security winter coat

- **Aurora**: `/obj/item/clothing/suit/storage/hooded/wintercoat/security` -- code/modules/clothing/suits/hoodies.dm
  name: security winter coat -- icon: icons/obj/item/clothing/suit/storage/toggle/hoodies.dmi -- icon_state: `coatsecurity`
- **Serenity**: `/obj/item/clothing/suit/storage/hooded/wintercoat/security` -- code/modules/clothing/suits/toggles.dm
  name: security winter coat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `coatsecurity`
- Confidence: HIGH -- identical type path structure and identical name ("security winter coat").

#### 29. labcoat

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/labcoat` -- code/modules/clothing/suits/labcoat.dm
  name: labcoat -- icon: icons/obj/item/clothing/suit/storage/toggle/labcoat.dmi -- icon_state: `labcoat`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/labcoat` -- code/modules/clothing/suits/labcoat.dm
  name: labcoat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `labcoat_open`
- Confidence: HIGH -- identical type path structure and identical name ("labcoat").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 30. chief medical officer's labcoat

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/labcoat/cmo` -- code/modules/clothing/suits/labcoat.dm
  name: chief medical officer's labcoat -- icon: icons/obj/item/clothing/suit/storage/toggle/labcoat.dmi -- icon_state: `labcoat_cmo`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/labcoat/cmo` -- code/modules/clothing/suits/labcoat.dm
  name: chief medical officer's labcoat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `labcoat_cmo_open`
- Confidence: HIGH -- identical type path structure and identical name ("chief medical officer's labcoat").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 31. chief medical officer labcoat

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/labcoat/cmoalt` -- code/modules/clothing/suits/labcoat.dm
  name: chief medical officer labcoat -- icon: icons/obj/item/clothing/suit/storage/toggle/labcoat.dmi -- icon_state: `labcoat_cmoalt`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/labcoat/cmoalt` -- code/modules/clothing/suits/labcoat.dm
  name: chief medical officer labcoat -- icon: icons/obj/clothing/suits.dmi -- icon_state: `labcoat_cmoalt_open`
- Confidence: HIGH -- identical type path structure and identical name ("chief medical officer labcoat").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 32. track jacket

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/track` -- code/modules/clothing/suits/miscellaneous.dm
  name: track jacket -- icon: icons/obj/tracksuit.dmi -- icon_state: `trackjacket`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/track` -- code/modules/clothing/suits/miscellaneous.dm
  name: track jacket -- icon: icons/obj/clothing/suits.dmi -- icon_state: `trackjacket`
- Confidence: HIGH -- identical type path structure and identical name ("track jacket").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 33. blue track jacket

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/track/blue` -- code/modules/clothing/suits/miscellaneous.dm
  name: blue track jacket -- icon: icons/obj/tracksuit.dmi -- icon_state: `trackjacketblue`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/track/blue` -- code/modules/clothing/suits/miscellaneous.dm
  name: blue track jacket -- icon: icons/obj/clothing/suits.dmi -- icon_state: `trackjacketblue`
- Confidence: HIGH -- identical type path structure and identical name ("blue track jacket").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 34. green track jacket

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/track/green` -- code/modules/clothing/suits/miscellaneous.dm
  name: green track jacket -- icon: icons/obj/tracksuit.dmi -- icon_state: `trackjacketgreen`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/track/green` -- code/modules/clothing/suits/miscellaneous.dm
  name: green track jacket -- icon: icons/obj/clothing/suits.dmi -- icon_state: `trackjacketgreen`
- Confidence: HIGH -- identical type path structure and identical name ("green track jacket").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 35. red track jacket

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/track/red` -- code/modules/clothing/suits/miscellaneous.dm
  name: red track jacket -- icon: icons/obj/tracksuit.dmi -- icon_state: `trackjacketred`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/track/red` -- code/modules/clothing/suits/miscellaneous.dm
  name: red track jacket -- icon: icons/obj/clothing/suits.dmi -- icon_state: `trackjacketred`
- Confidence: HIGH -- identical type path structure and identical name ("red track jacket").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 36. white track jacket

- **Aurora**: `/obj/item/clothing/suit/storage/toggle/track/white` -- code/modules/clothing/suits/miscellaneous.dm
  name: white track jacket -- icon: icons/obj/tracksuit.dmi -- icon_state: `trackjacketwhite`
- **Serenity**: `/obj/item/clothing/suit/storage/toggle/track/white` -- code/modules/clothing/suits/miscellaneous.dm
  name: white track jacket -- icon: icons/obj/clothing/suits.dmi -- icon_state: `trackjacketwhite`
- Confidence: HIGH -- identical type path structure and identical name ("white track jacket").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 37. armor vest

- **Aurora**: `/obj/item/clothing/suit/storage/vest` -- code/modules/clothing/suits/armor.dm
  name: armor vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `kvest`
- **Serenity**: `/obj/item/clothing/suit/storage/vest` -- code/modules/clothing/suits/armor.dm
  name: webbed armor vest -- icon: icons/obj/clothing/suits.dmi -- icon_state: `webvest`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 38. roughspun robes

- **Aurora**: `/obj/item/clothing/suit/unathi/robe` -- code/modules/clothing/suits/xeno/unathi.dm
  name: roughspun robes -- icon: icons/obj/unathi_items.dmi -- icon_state: `roughspun_robe`
- **Serenity**: `/obj/item/clothing/suit/unathi/robe` -- code/modules/clothing/suits/alien.dm
  name: roughspun robes -- icon: _(unset -- inherited/default)_ -- icon_state: `robe-unathi`
- Confidence: HIGH -- identical type path structure and identical name ("roughspun robes").

---

## Clothing - Under (Uniforms) (40)

#### 1. captain's formal uniform

- **Aurora**: `/obj/item/clothing/under/captainformal` -- code/modules/clothing/sets/captain.dm
  name: captain's formal uniform -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `captain_formal`
- **Serenity**: `/obj/item/clothing/under/captainformal` -- code/modules/clothing/under/miscellaneous.dm
  name: captain's formal uniform -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `captain_formal`
- Confidence: HIGH -- identical type path structure and identical name ("captain's formal uniform").

#### 2. black jumpsuit

- **Aurora**: `/obj/item/clothing/under/chameleon` -- code/modules/clothing/chameleon.dm
  name: black jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `ninja`
- **Serenity**: `/obj/item/clothing/under/chameleon` -- code/modules/clothing/chameleon.dm
  name: black jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `black`
- Confidence: HIGH -- identical type path structure and identical name ("black jumpsuit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 3. white cheongsam

- **Aurora**: `/obj/item/clothing/under/cheongsam` -- code/modules/clothing/under/miscellaneous.dm
  name: white cheongsam -- icon: icons/obj/clothing/cheongsams.dmi -- icon_state: `cheongsamwhite`
- **Serenity**: `/obj/item/clothing/under/cheongsam` -- code/modules/clothing/under/miscellaneous.dm
  name: cheongsam -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `mai_yang`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 4. grey jumpsuit

- **Aurora**: `/obj/item/clothing/under/color` -- code/modules/clothing/under/color.dm
  name: grey jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `grey`
- **Serenity**: `/obj/item/clothing/under/color` -- code/modules/clothing/under/color.dm
  name: jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `jumpsuit`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 5. black jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/black` -- code/modules/clothing/under/color.dm
  name: black jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `black`
- **Serenity**: `/obj/item/clothing/under/color/black` -- code/modules/clothing/under/color.dm
  name: black jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `black`
- Confidence: HIGH -- identical type path structure and identical name ("black jumpsuit").

#### 6. blue jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/blue` -- code/modules/clothing/under/color.dm
  name: blue jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `blue`
- **Serenity**: `/obj/item/clothing/under/color/blue` -- code/modules/clothing/under/color.dm
  name: blue jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `blue`
- Confidence: HIGH -- identical type path structure and identical name ("blue jumpsuit").

#### 7. brown jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/brown` -- code/modules/clothing/under/color.dm
  name: brown jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `brown`
- **Serenity**: `/obj/item/clothing/under/color/brown` -- code/modules/clothing/under/color.dm
  name: brown jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `brown`
- Confidence: HIGH -- identical type path structure and identical name ("brown jumpsuit").

#### 8. green jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/green` -- code/modules/clothing/under/color.dm
  name: green jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `green`
- **Serenity**: `/obj/item/clothing/under/color/green` -- code/modules/clothing/under/color.dm
  name: green jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `green`
- Confidence: HIGH -- identical type path structure and identical name ("green jumpsuit").

#### 9. grey jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/grey` -- code/modules/clothing/under/color.dm
  name: grey jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `grey`
- **Serenity**: `/obj/item/clothing/under/color/grey` -- code/modules/clothing/under/color.dm
  name: grey jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `grey`
- Confidence: HIGH -- identical type path structure and identical name ("grey jumpsuit").

#### 10. lightpurple jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/lightpurple` -- code/modules/clothing/under/color.dm
  name: lightpurple jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `lightpurple`
- **Serenity**: `/obj/item/clothing/under/color/lightpurple` -- code/modules/clothing/under/color.dm
  name: purple jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `lightpurple`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 11. orange jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/orange` -- code/modules/clothing/under/color.dm
  name: orange jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `orange`
- **Serenity**: `/obj/item/clothing/under/color/orange` -- code/modules/clothing/under/color.dm
  name: orange jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `orange`
- Confidence: HIGH -- identical type path structure and identical name ("orange jumpsuit").

#### 12. pink jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/pink` -- code/modules/clothing/under/color.dm
  name: pink jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `pink`
- **Serenity**: `/obj/item/clothing/under/color/pink` -- code/modules/clothing/under/color.dm
  name: pink jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `pink`
- Confidence: HIGH -- identical type path structure and identical name ("pink jumpsuit").

#### 13. red jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/red` -- code/modules/clothing/under/color.dm
  name: red jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `red`
- **Serenity**: `/obj/item/clothing/under/color/red` -- code/modules/clothing/under/color.dm
  name: red jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `red`
- Confidence: HIGH -- identical type path structure and identical name ("red jumpsuit").

#### 14. white jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/white` -- code/modules/clothing/under/color.dm
  name: white jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `white`
- **Serenity**: `/obj/item/clothing/under/color/white` -- code/modules/clothing/under/color.dm
  name: white jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `white`
- Confidence: HIGH -- identical type path structure and identical name ("white jumpsuit").

#### 15. yellow jumpsuit

- **Aurora**: `/obj/item/clothing/under/color/yellow` -- code/modules/clothing/under/color.dm
  name: yellow jumpsuit -- icon: icons/obj/item/clothing/under/jumpsuits.dmi -- icon_state: `yellow`
- **Serenity**: `/obj/item/clothing/under/color/yellow` -- code/modules/clothing/under/color.dm
  name: yellow jumpsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `yellow`
- Confidence: HIGH -- identical type path structure and identical name ("yellow jumpsuit").

#### 16. investigator's uniform

- **Aurora**: `/obj/item/clothing/under/det` -- code/modules/clothing/under/jobs/security.dm
  name: investigator's uniform -- icon: icons/obj/item/clothing/department_uniforms/security.dmi -- icon_state: `nt_invest`
- **Serenity**: `/obj/item/clothing/under/det` -- code/modules/clothing/under/jobs/security.dm
  name: detective's suit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `detective`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "investigator's uniform" / Serenity: "detective's suit") -- verify these are truly the same item before swapping.

#### 17. under

- **Aurora**: `/obj/item/clothing/under/dress` -- code/modules/clothing/under/miscellaneous.dm
  name: under -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/clothing/under/dress` -- code/modules/clothing/under/miscellaneous.dm
  name: dress -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `dress_fire`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "under" / Serenity: "dress") -- verify these are truly the same item before swapping.

#### 18. captain's dress uniform

- **Aurora**: `/obj/item/clothing/under/dress/dress_cap` -- code/modules/clothing/sets/captain.dm
  name: captain's dress uniform -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `captain_alt_skirt`
- **Serenity**: `/obj/item/clothing/under/dress/dress_cap` -- code/modules/clothing/under/miscellaneous.dm
  name: captain's dress uniform -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `dress_cap`
- Confidence: HIGH -- identical type path structure and identical name ("captain's dress uniform").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 19. sensible suit

- **Aurora**: `/obj/item/clothing/under/librarian` -- code/modules/clothing/under/jobs/civilian.dm
  name: sensible suit -- icon: icons/obj/item/clothing/department_uniforms/service.dmi -- icon_state: `nt_librarian`
- **Serenity**: `/obj/item/clothing/under/librarian` -- code/modules/clothing/under/jobs/civilian.dm
  name: sensible suit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `red_suit`
- Confidence: HIGH -- identical type path structure and identical name ("sensible suit").

#### 20. atmospheric technician's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/atmospheric_technician` -- code/modules/clothing/under/jobs/engineering.dm
  name: atmospheric technician's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/engineering.dmi -- icon_state: `nt_atmos`
- **Serenity**: `/obj/item/clothing/under/rank/atmospheric_technician` -- code/modules/clothing/under/jobs/engineering.dm
  name: atmospheric technician's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `atmos`
- Confidence: HIGH -- identical type path structure and identical name ("atmospheric technician's jumpsuit").

#### 21. bartender's uniform

- **Aurora**: `/obj/item/clothing/under/rank/bartender` -- code/modules/clothing/under/jobs/civilian.dm
  name: bartender's uniform -- icon: icons/obj/item/clothing/department_uniforms/service.dmi -- icon_state: `nt_bartender`
- **Serenity**: `/obj/item/clothing/under/rank/bartender` -- code/modules/clothing/under/jobs/civilian.dm
  name: bartender's uniform -- icon: _(unset -- inherited/default)_ -- icon_state: `ba_suit`
- Confidence: HIGH -- identical type path structure and identical name ("bartender's uniform").

#### 22. chef's uniform

- **Aurora**: `/obj/item/clothing/under/rank/chef` -- code/modules/clothing/under/jobs/civilian.dm
  name: chef's uniform -- icon: icons/obj/item/clothing/department_uniforms/service.dmi -- icon_state: `nt_chef`
- **Serenity**: `/obj/item/clothing/under/rank/chef` -- code/modules/clothing/under/jobs/civilian.dm
  name: chef's uniform -- icon: _(unset -- inherited/default)_ -- icon_state: `chef`
- Confidence: HIGH -- identical type path structure and identical name ("chef's uniform").

#### 23. chief engineer's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/chief_engineer` -- code/modules/clothing/under/jobs/engineering.dm
  name: chief engineer's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `chief_engineer`
- **Serenity**: `/obj/item/clothing/under/rank/chief_engineer` -- code/modules/clothing/under/jobs/engineering.dm
  name: chief engineer's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `chiefengineer`
- Confidence: HIGH -- identical type path structure and identical name ("chief engineer's jumpsuit").

#### 24. chief medical officer's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/chief_medical_officer` -- code/modules/clothing/under/jobs/medsci.dm
  name: chief medical officer's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `chief_medical_officer`
- **Serenity**: `/obj/item/clothing/under/rank/chief_medical_officer` -- code/modules/clothing/under/jobs/medsci.dm
  name: chief medical officer's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `cmo`
- Confidence: HIGH -- identical type path structure and identical name ("chief medical officer's jumpsuit").

#### 25. engineer's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/engineer` -- code/modules/clothing/under/jobs/engineering.dm
  name: engineer's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/engineering.dmi -- icon_state: `nt_engineer`
- **Serenity**: `/obj/item/clothing/under/rank/engineer` -- code/modules/clothing/under/jobs/engineering.dm
  name: engineer's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `engine`
- Confidence: HIGH -- identical type path structure and identical name ("engineer's jumpsuit").

#### 26. head of security's uniform

- **Aurora**: `/obj/item/clothing/under/rank/head_of_security` -- code/modules/clothing/under/jobs/security.dm
  name: head of security's uniform -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `head_of_security`
- **Serenity**: `/obj/item/clothing/under/rank/head_of_security` -- code/modules/clothing/under/jobs/security.dm
  name: head of security's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `hos`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 27. botanist's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/hydroponics` -- code/modules/clothing/under/jobs/civilian.dm
  name: botanist's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/service.dmi -- icon_state: `nt_gardener`
- **Serenity**: `/obj/item/clothing/under/rank/hydroponics` -- code/modules/clothing/under/jobs/civilian.dm
  name: botanist's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `hydroponics`
- Confidence: HIGH -- identical type path structure and identical name ("botanist's jumpsuit").

#### 28. janitor's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/janitor` -- code/modules/clothing/under/jobs/civilian.dm
  name: janitor's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/service.dmi -- icon_state: `nt_janitor`
- **Serenity**: `/obj/item/clothing/under/rank/janitor` -- code/modules/clothing/under/jobs/civilian.dm
  name: janitor's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `janitor`
- Confidence: HIGH -- identical type path structure and identical name ("janitor's jumpsuit").

#### 29. physician's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/medical` -- code/modules/clothing/under/jobs/medsci.dm
  name: physician's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/medical.dmi -- icon_state: `nt_phys`
- **Serenity**: `/obj/item/clothing/under/rank/medical` -- code/modules/clothing/under/jobs/medsci.dm
  name: medical doctor's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `medical`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 30. paramedic jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/medical/paramedic` -- code/modules/clothing/under/jobs/medsci.dm
  name: paramedic jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/medical.dmi -- icon_state: `nt_emt`
- **Serenity**: `/obj/item/clothing/under/rank/medical/paramedic` -- code/modules/clothing/under/jobs/medsci.dm
  name: short sleeve medical jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `medical`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 31. miner's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/miner` -- code/modules/clothing/under/jobs/civilian.dm
  name: miner's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/operations.dmi -- icon_state: `nt_miner`
- **Serenity**: `/obj/item/clothing/under/rank/miner` -- code/modules/clothing/under/jobs/civilian.dm
  name: shaft miner's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `miner`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 32. research director's jumpsuit

- **Aurora**: `/obj/item/clothing/under/rank/research_director` -- code/modules/clothing/under/jobs/medsci.dm
  name: research director's jumpsuit -- icon: icons/obj/item/clothing/department_uniforms/command.dmi -- icon_state: `research_director`
- **Serenity**: `/obj/item/clothing/under/rank/research_director` -- code/modules/clothing/under/jobs/medsci.dm
  name: research director's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `director`
- Confidence: HIGH -- identical type path structure and identical name ("research director's jumpsuit").

#### 33. security officer's uniform

- **Aurora**: `/obj/item/clothing/under/rank/security` -- code/modules/clothing/under/jobs/security.dm
  name: security officer's uniform -- icon: icons/obj/item/clothing/department_uniforms/security.dmi -- icon_state: `nt_officer`
- **Serenity**: `/obj/item/clothing/under/rank/security` -- code/modules/clothing/under/jobs/security.dm
  name: security officer's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `security`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 34. warden's uniform

- **Aurora**: `/obj/item/clothing/under/rank/warden` -- code/modules/clothing/under/jobs/security.dm
  name: warden's uniform -- icon: icons/obj/item/clothing/department_uniforms/security.dmi -- icon_state: `nt_warden`
- **Serenity**: `/obj/item/clothing/under/rank/warden` -- code/modules/clothing/under/jobs/security.dm
  name: warden's jumpsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `warden`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 35. black swimsuit

- **Aurora**: `/obj/item/clothing/under/swimsuit/black` -- code/modules/clothing/under/miscellaneous.dm
  name: black swimsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `swim_black`
- **Serenity**: `/obj/item/clothing/under/swimsuit/black` -- code/modules/clothing/suits/miscellaneous.dm
  name: black swimsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `swim_black`
- Confidence: HIGH -- identical type path structure and identical name ("black swimsuit").

#### 36. blue swimsuit

- **Aurora**: `/obj/item/clothing/under/swimsuit/blue` -- code/modules/clothing/under/miscellaneous.dm
  name: blue swimsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `swim_blue`
- **Serenity**: `/obj/item/clothing/under/swimsuit/blue` -- code/modules/clothing/suits/miscellaneous.dm
  name: blue swimsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `swim_blue`
- Confidence: HIGH -- identical type path structure and identical name ("blue swimsuit").

#### 37. green swimsuit

- **Aurora**: `/obj/item/clothing/under/swimsuit/green` -- code/modules/clothing/under/miscellaneous.dm
  name: green swimsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `swim_green`
- **Serenity**: `/obj/item/clothing/under/swimsuit/green` -- code/modules/clothing/suits/miscellaneous.dm
  name: green swimsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `swim_green`
- Confidence: HIGH -- identical type path structure and identical name ("green swimsuit").

#### 38. purple swimsuit

- **Aurora**: `/obj/item/clothing/under/swimsuit/purple` -- code/modules/clothing/under/miscellaneous.dm
  name: purple swimsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `swim_purp`
- **Serenity**: `/obj/item/clothing/under/swimsuit/purple` -- code/modules/clothing/suits/miscellaneous.dm
  name: purple swimsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `swim_purp`
- Confidence: HIGH -- identical type path structure and identical name ("purple swimsuit").

#### 39. red swimsuit

- **Aurora**: `/obj/item/clothing/under/swimsuit/red` -- code/modules/clothing/under/miscellaneous.dm
  name: red swimsuit -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `swim_red`
- **Serenity**: `/obj/item/clothing/under/swimsuit/red` -- code/modules/clothing/suits/miscellaneous.dm
  name: red swimsuit -- icon: _(unset -- inherited/default)_ -- icon_state: `swim_red`
- Confidence: HIGH -- identical type path structure and identical name ("red swimsuit").

#### 40. combat turtleneck

- **Aurora**: `/obj/item/clothing/under/syndicate/combat` -- code/modules/clothing/under/syndicate.dm
  name: combat turtleneck -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `syndicate`
- **Serenity**: `/obj/item/clothing/under/syndicate/combat` -- code/modules/clothing/under/syndicate.dm
  name: combat turtleneck -- icon: icons/obj/clothing/uniforms.dmi -- icon_state: `combat`
- Confidence: HIGH -- identical type path structure and identical name ("combat turtleneck").

---

## Clothing - Accessories (22)

#### 1. tie

- **Aurora**: `/obj/item/clothing/accessory` -- code/modules/clothing/under/accessories/accessory.dm
  name: tie -- icon: icons/obj/clothing/ties.dmi -- icon_state: `bluetie`
- **Serenity**: `/obj/item/clothing/accessory` -- code/modules/clothing/under/accessories/accessory.dm
  name: tie -- icon: icons/obj/clothing/ties.dmi -- icon_state: `tie`
- Confidence: HIGH -- identical type path structure and identical name ("tie").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. engineering armband

- **Aurora**: `/obj/item/clothing/accessory/armband/engine` -- code/modules/clothing/under/accessories/armband.dm
  name: engineering armband -- icon: _(unset -- inherited/default)_ -- icon_state: `armband_engineering`
- **Serenity**: `/obj/item/clothing/accessory/armband/engine` -- code/modules/clothing/under/accessories/armband.dm
  name: engineering armband -- icon: icons/obj/clothing/ties.dmi -- icon_state: `engie`
- Confidence: HIGH -- identical type path structure and identical name ("engineering armband").

#### 3. hydroponics armband

- **Aurora**: `/obj/item/clothing/accessory/armband/hydro` -- code/modules/clothing/under/accessories/armband.dm
  name: hydroponics armband -- icon: _(unset -- inherited/default)_ -- icon_state: `armband_hydroponics`
- **Serenity**: `/obj/item/clothing/accessory/armband/hydro` -- code/modules/clothing/under/accessories/armband.dm
  name: hydroponics armband -- icon: icons/obj/clothing/ties.dmi -- icon_state: `hydro`
- Confidence: HIGH -- identical type path structure and identical name ("hydroponics armband").

#### 4. medical armband

- **Aurora**: `/obj/item/clothing/accessory/armband/med` -- code/modules/clothing/under/accessories/armband.dm
  name: medical armband -- icon: _(unset -- inherited/default)_ -- icon_state: `armband_medical`
- **Serenity**: `/obj/item/clothing/accessory/armband/med` -- code/modules/clothing/under/accessories/armband.dm
  name: medical armband -- icon: icons/obj/clothing/ties.dmi -- icon_state: `med`
- Confidence: HIGH -- identical type path structure and identical name ("medical armband").

#### 5. blue tie

- **Aurora**: `/obj/item/clothing/accessory/blue` -- code/modules/clothing/under/accessories/accessory.dm
  name: blue tie -- icon: icons/obj/clothing/ties.dmi -- icon_state: `bluetie`
- **Serenity**: `/obj/item/clothing/accessory/blue` -- code/modules/clothing/under/accessories/ties.dm
  name: blue tie -- icon: icons/obj/clothing/ties.dmi -- icon_state: `tie`
- Confidence: HIGH -- identical type path structure and identical name ("blue tie").

#### 6. shoulder holster

- **Aurora**: `/obj/item/clothing/accessory/holster` -- code/modules/clothing/under/accessories/holster.dm
  name: shoulder holster -- icon: icons/obj/item/clothing/accessory/holster.dmi -- icon_state: `holster`
- **Serenity**: `/obj/item/clothing/accessory/holster` -- code/modules/clothing/under/accessories/holster.dm
  name: shoulder holster -- icon: icons/obj/clothing/ties.dmi -- icon_state: `holster`
- Confidence: HIGH -- identical type path structure and identical name ("shoulder holster").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. black armpit holster

- **Aurora**: `/obj/item/clothing/accessory/holster/armpit` -- code/modules/clothing/under/accessories/holster.dm
  name: black armpit holster -- icon: icons/obj/item/clothing/accessory/holster.dmi -- icon_state: `holster`
- **Serenity**: `/obj/item/clothing/accessory/holster/armpit` -- code/modules/clothing/under/accessories/holster.dm
  name: armpit holster -- icon: icons/obj/clothing/ties.dmi -- icon_state: `holster`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 8. black hip holster

- **Aurora**: `/obj/item/clothing/accessory/holster/hip` -- code/modules/clothing/under/accessories/holster.dm
  name: black hip holster -- icon: icons/obj/item/clothing/accessory/holster.dmi -- icon_state: `holster_hip`
- **Serenity**: `/obj/item/clothing/accessory/holster/hip` -- code/modules/clothing/under/accessories/holster.dm
  name: hip holster -- icon: icons/obj/clothing/ties.dmi -- icon_state: `holster_hip`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 9. black thigh holster

- **Aurora**: `/obj/item/clothing/accessory/holster/thigh` -- code/modules/clothing/under/accessories/holster.dm
  name: black thigh holster -- icon: icons/obj/item/clothing/accessory/holster.dmi -- icon_state: `holster_thigh`
- **Serenity**: `/obj/item/clothing/accessory/holster/thigh` -- code/modules/clothing/under/accessories/holster.dm
  name: thigh holster -- icon: icons/obj/clothing/ties.dmi -- icon_state: `holster_thigh`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 10. black waist holster

- **Aurora**: `/obj/item/clothing/accessory/holster/waist` -- code/modules/clothing/under/accessories/holster.dm
  name: black waist holster -- icon: icons/obj/item/clothing/accessory/holster.dmi -- icon_state: `holster_low`
- **Serenity**: `/obj/item/clothing/accessory/holster/waist` -- code/modules/clothing/under/accessories/holster.dm
  name: waist holster -- icon: icons/obj/clothing/ties.dmi -- icon_state: `holster`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 11. kneepads

- **Aurora**: `/obj/item/clothing/accessory/kneepads` -- code/modules/clothing/under/accessories/accessory.dm
  name: kneepads -- icon: icons/obj/item/clothing/accessory/kneepads.dmi -- icon_state: `kneepads`
- **Serenity**: `/obj/item/clothing/accessory/kneepads` -- code/modules/clothing/under/accessories/accessory.dm
  name: kneepads -- icon: icons/obj/clothing/ties.dmi -- icon_state: `kneepads`
- Confidence: HIGH -- identical type path structure and identical name ("kneepads").

#### 12. necklace

- **Aurora**: `/obj/item/clothing/accessory/necklace` -- code/modules/clothing/under/accessories/accessory.dm
  name: necklace -- icon: icons/obj/item/clothing/accessory/necklace.dmi -- icon_state: `necklace`
- **Serenity**: `/obj/item/clothing/accessory/necklace` -- code/modules/clothing/under/accessories/accessory.dm
  name: necklace -- icon: icons/obj/clothing/ties.dmi -- icon_state: `necklace`
- Confidence: HIGH -- identical type path structure and identical name ("necklace").

#### 13. red tie

- **Aurora**: `/obj/item/clothing/accessory/red` -- code/modules/clothing/under/accessories/accessory.dm
  name: red tie -- icon: icons/obj/clothing/ties.dmi -- icon_state: `redtie`
- **Serenity**: `/obj/item/clothing/accessory/red` -- code/modules/clothing/under/accessories/ties.dm
  name: red tie -- icon: icons/obj/clothing/ties.dmi -- icon_state: `tie`
- Confidence: HIGH -- identical type path structure and identical name ("red tie").

#### 14. scarf

- **Aurora**: `/obj/item/clothing/accessory/scarf` -- code/modules/clothing/under/accessories/accessory.dm
  name: scarf -- icon: icons/obj/item/clothing/accessory/scarves.dmi -- icon_state: `scarf0`
- **Serenity**: `/obj/item/clothing/accessory/scarf` -- code/modules/clothing/under/accessories/accessory.dm
  name: scarf -- icon: icons/obj/clothing/ties.dmi -- icon_state: `whitescarf`
- Confidence: HIGH -- identical type path structure and identical name ("scarf").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 15. stethoscope

- **Aurora**: `/obj/item/clothing/accessory/stethoscope` -- code/modules/clothing/under/accessories/accessory.dm
  name: stethoscope -- icon: icons/obj/item/clothing/accessory/stethoscope.dmi -- icon_state: `stethoscope`
- **Serenity**: `/obj/item/clothing/accessory/stethoscope` -- code/modules/clothing/under/accessories/stethoscope.dm
  name: stethoscope -- icon: icons/obj/clothing/ties.dmi -- icon_state: `stethoscope`
- Confidence: HIGH -- identical type path structure and identical name ("stethoscope").

#### 16. black webbing vest

- **Aurora**: `/obj/item/clothing/accessory/storage/black_vest` -- code/modules/clothing/under/accessories/storage.dm
  name: black webbing vest -- icon: icons/obj/item/clothing/accessory/webbing.dmi -- icon_state: `vest_black`
- **Serenity**: `/obj/item/clothing/accessory/storage/black_vest` -- code/modules/clothing/under/accessories/storage.dm
  name: black webbing vest -- icon: icons/obj/clothing/ties.dmi -- icon_state: `vest_black`
- Confidence: HIGH -- identical type path structure and identical name ("black webbing vest").

#### 17. brown webbing vest

- **Aurora**: `/obj/item/clothing/accessory/storage/brown_vest` -- code/modules/clothing/under/accessories/storage.dm
  name: brown webbing vest -- icon: icons/obj/item/clothing/accessory/webbing.dmi -- icon_state: `vest_brown`
- **Serenity**: `/obj/item/clothing/accessory/storage/brown_vest` -- code/modules/clothing/under/accessories/storage.dm
  name: brown webbing vest -- icon: icons/obj/clothing/ties.dmi -- icon_state: `vest_brown`
- Confidence: HIGH -- identical type path structure and identical name ("brown webbing vest").

#### 18. drop pouches

- **Aurora**: `/obj/item/clothing/accessory/storage/pouches` -- code/modules/clothing/under/accessories/storage.dm
  name: drop pouches -- icon: icons/obj/item/clothing/accessory/holster.dmi -- icon_state: `thigh_brown`
- **Serenity**: `/obj/item/clothing/accessory/storage/pouches` -- code/modules/clothing/under/accessories/armor.dm
  name: storage pouches -- icon: icons/obj/clothing/modular_armor.dmi -- icon_state: `pouches`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 19. webbing

- **Aurora**: `/obj/item/clothing/accessory/storage/webbing` -- code/modules/clothing/under/accessories/storage.dm
  name: webbing -- icon: icons/obj/item/clothing/accessory/webbing.dmi -- icon_state: `webbing`
- **Serenity**: `/obj/item/clothing/accessory/storage/webbing` -- code/modules/clothing/under/accessories/storage.dm
  name: webbing -- icon: icons/obj/clothing/ties.dmi -- icon_state: `webbing`
- Confidence: HIGH -- identical type path structure and identical name ("webbing").

#### 20. white webbing vest

- **Aurora**: `/obj/item/clothing/accessory/storage/white_vest` -- code/modules/clothing/under/accessories/storage.dm
  name: white webbing vest -- icon: icons/obj/item/clothing/accessory/webbing.dmi -- icon_state: `vest_white`
- **Serenity**: `/obj/item/clothing/accessory/storage/white_vest` -- code/modules/clothing/under/accessories/storage.dm
  name: white webbing vest -- icon: icons/obj/clothing/ties.dmi -- icon_state: `vest_white`
- Confidence: HIGH -- identical type path structure and identical name ("white webbing vest").

#### 21. sweater

- **Aurora**: `/obj/item/clothing/accessory/sweater` -- code/modules/clothing/under/accessories/shirts.dm
  name: sweater -- icon: icons/obj/item/clothing/accessory/sweaters.dmi -- icon_state: `sweater`
- **Serenity**: `/obj/item/clothing/accessory/sweater` -- code/modules/clothing/under/accessories/clothing.dm
  name: turtleneck sweater -- icon: icons/obj/clothing/ties.dmi -- icon_state: `sweater`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "sweater" / Serenity: "turtleneck sweater") -- verify these are truly the same item before swapping.

#### 22. waistcoat

- **Aurora**: `/obj/item/clothing/accessory/wcoat` -- code/modules/clothing/under/accessories/shirts.dm
  name: waistcoat -- icon: icons/obj/clothing/ties.dmi -- icon_state: `wcoat`
- **Serenity**: `/obj/item/clothing/accessory/wcoat` -- code/modules/clothing/under/accessories/clothing.dm
  name: waistcoat -- icon: icons/obj/clothing/ties.dmi -- icon_state: `vest`
- Confidence: HIGH -- identical type path structure and identical name ("waistcoat").

---

## Clothing - Other (3)

#### 1. ring

- **Aurora**: `/obj/item/clothing/ring/reagent` -- code/modules/clothing/rings/rings.dm
  name: ring -- icon: icons/obj/clothing/rings.dmi -- icon_state: `material`
- **Serenity**: `/obj/item/clothing/ring/reagent` -- code/modules/clothing/rings/rings.dm
  name: ring -- icon: icons/obj/clothing/rings.dmi -- icon_state: _(unset -- inherited/default)_
- Confidence: HIGH -- identical type path structure and identical name ("ring").

#### 2. masonic ring

- **Aurora**: `/obj/item/clothing/ring/seal/mason` -- code/modules/clothing/rings/rings.dm
  name: masonic ring -- icon: _(unset -- inherited/default)_ -- icon_state: `seal-masonic`
- **Serenity**: `/obj/item/clothing/ring/seal/mason` -- code/modules/clothing/rings/rings.dm
  name: masonic ring -- icon: icons/obj/clothing/rings.dmi -- icon_state: `seal-masonic`
- Confidence: HIGH -- identical type path structure and identical name ("masonic ring").

#### 3. signet ring

- **Aurora**: `/obj/item/clothing/ring/seal/signet` -- code/modules/clothing/rings/rings.dm
  name: signet ring -- icon: _(unset -- inherited/default)_ -- icon_state: `seal-signet`
- **Serenity**: `/obj/item/clothing/ring/seal/signet` -- code/modules/clothing/rings/rings.dm
  name: signet ring -- icon: icons/obj/clothing/rings.dmi -- icon_state: `seal-signet`
- Confidence: HIGH -- identical type path structure and identical name ("signet ring").

---

## Hardsuit / RIG Control Modules (35)

#### 1. advanced voidsuit control module

- **Aurora**: `/obj/item/rig/ce` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: advanced voidsuit control module -- icon: icons/obj/item/clothing/rig/ce.dmi -- icon_state: `ce_rig`
- **Serenity**: `/obj/item/weapon/rig/ce` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: advanced engineering hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ce_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 2. advanced voidsuit control module

- **Aurora**: `/obj/item/rig/ce/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: advanced voidsuit control module -- icon: icons/obj/item/clothing/rig/ce.dmi -- icon_state: `ce_rig`
- **Serenity**: `/obj/item/weapon/rig/ce/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: advanced engineering hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ce_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 3. combat hardsuit control module

- **Aurora**: `/obj/item/rig/combat` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: combat hardsuit control module -- icon: icons/obj/item/clothing/rig/combat.dmi -- icon_state: `combat_rig`
- **Serenity**: `/obj/item/weapon/rig/combat` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: combat hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `security_rig`
- Confidence: HIGH -- identical type path structure and identical name ("combat hardsuit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 4. combat hardsuit control module

- **Aurora**: `/obj/item/rig/combat/equipped` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: combat hardsuit control module -- icon: icons/obj/item/clothing/rig/combat.dmi -- icon_state: `combat_rig`
- **Serenity**: `/obj/item/weapon/rig/combat/equipped` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: combat hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `security_rig`
- Confidence: HIGH -- identical type path structure and identical name ("combat hardsuit control module").

#### 5. ERT-C hardsuit control module

- **Aurora**: `/obj/item/rig/ert` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: ERT-C hardsuit control module -- icon: icons/obj/item/clothing/rig/nt_ert/commander.dmi -- icon_state: `ert_commander_rig`
- **Serenity**: `/obj/item/weapon/rig/ert` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: asset protection command hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ert_commander_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. \improper heavy asset protection suit control module

- **Aurora**: `/obj/item/rig/ert/assetprotection` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: \improper heavy asset protection suit control module -- icon: icons/obj/item/clothing/rig/asset_protection.dmi -- icon_state: `asset_protection_rig`
- **Serenity**: `/obj/item/weapon/rig/ert/assetprotection` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: heavy asset protection suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `asset_protection_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. ERT-E suit control module

- **Aurora**: `/obj/item/rig/ert/engineer` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: ERT-E suit control module -- icon: icons/obj/item/clothing/rig/nt_ert/engineer.dmi -- icon_state: `ert_engineer_rig`
- **Serenity**: `/obj/item/weapon/rig/ert/engineer` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: asset protection engineering hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ert_engineer_rig`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "ERT-E suit control module" / Serenity: "asset protection engineering hardsuit control module") -- verify these are truly the same item before swapping.

#### 8. ERT-M suit control module

- **Aurora**: `/obj/item/rig/ert/medical` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: ERT-M suit control module -- icon: icons/obj/item/clothing/rig/nt_ert/medical.dmi -- icon_state: `ert_medical_rig`
- **Serenity**: `/obj/item/weapon/rig/ert/medical` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: asset protection medical hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ert_medical_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 9. ERT-S suit control module

- **Aurora**: `/obj/item/rig/ert/security` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: ERT-S suit control module -- icon: icons/obj/item/clothing/rig/nt_ert/security.dmi -- icon_state: `ert_security_rig`
- **Serenity**: `/obj/item/weapon/rig/ert/security` -- code/modules/clothing/spacesuits/rig/suits/ert.dm
  name: asset protection security hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ert_security_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 10. EVA suit control module

- **Aurora**: `/obj/item/rig/eva` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: EVA suit control module -- icon: icons/obj/item/clothing/rig/eva.dmi -- icon_state: `eva_rig`
- **Serenity**: `/obj/item/weapon/rig/eva` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: EVA hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `eva_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 11. EVA suit control module

- **Aurora**: `/obj/item/rig/eva/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: EVA suit control module -- icon: icons/obj/item/clothing/rig/eva.dmi -- icon_state: `eva_rig`
- **Serenity**: `/obj/item/weapon/rig/eva/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: EVA hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `eva_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 12. hazard hardsuit control module

- **Aurora**: `/obj/item/rig/hazard` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: hazard hardsuit control module -- icon: icons/obj/item/clothing/rig/hazard.dmi -- icon_state: `hazard_rig`
- **Serenity**: `/obj/item/weapon/rig/hazard` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: hazard hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `hazard_rig`
- Confidence: HIGH -- identical type path structure and identical name ("hazard hardsuit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 13. hazard hardsuit control module

- **Aurora**: `/obj/item/rig/hazard/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: hazard hardsuit control module -- icon: icons/obj/item/clothing/rig/hazard.dmi -- icon_state: `hazard_rig`
- **Serenity**: `/obj/item/weapon/rig/hazard/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: hazard hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `hazard_rig`
- Confidence: HIGH -- identical type path structure and identical name ("hazard hardsuit control module").

#### 14. AMI control module

- **Aurora**: `/obj/item/rig/hazmat` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: AMI control module -- icon: icons/obj/item/clothing/rig/hazmat.dmi -- icon_state: `hazmat_rig`
- **Serenity**: `/obj/item/weapon/rig/hazmat` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: AMI control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `science_rig`
- Confidence: HIGH -- identical type path structure and identical name ("AMI control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 15. AMI control module

- **Aurora**: `/obj/item/rig/hazmat/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: AMI control module -- icon: icons/obj/item/clothing/rig/hazmat.dmi -- icon_state: `hazmat_rig`
- **Serenity**: `/obj/item/weapon/rig/hazmat/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: AMI control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `science_rig`
- Confidence: HIGH -- identical type path structure and identical name ("AMI control module").

#### 16. industrial suit control module

- **Aurora**: `/obj/item/rig/industrial` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: industrial suit control module -- icon: icons/obj/item/clothing/rig/industrial.dmi -- icon_state: `industrial_rig`
- **Serenity**: `/obj/item/weapon/rig/industrial` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: industrial suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `engineering_rig`
- Confidence: HIGH -- identical type path structure and identical name ("industrial suit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 17. industrial suit control module

- **Aurora**: `/obj/item/rig/industrial/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: industrial suit control module -- icon: icons/obj/item/clothing/rig/industrial.dmi -- icon_state: `industrial_rig`
- **Serenity**: `/obj/item/weapon/rig/industrial/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: industrial suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `engineering_rig`
- Confidence: HIGH -- identical type path structure and identical name ("industrial suit control module").

#### 18. light suit control module

- **Aurora**: `/obj/item/rig/light` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: light suit control module -- icon: icons/obj/item/clothing/rig/light_ninja.dmi -- icon_state: `ninja_rig`
- **Serenity**: `/obj/item/weapon/rig/light` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: light suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ninja_rig`
- Confidence: HIGH -- identical type path structure and identical name ("light suit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 19. cybersuit control module

- **Aurora**: `/obj/item/rig/light/hacker` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: cybersuit control module -- icon: icons/obj/item/clothing/rig/light_hacker.dmi -- icon_state: `hacker_rig`
- **Serenity**: `/obj/item/weapon/rig/light/hacker` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: cybersuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `hacker_rig`
- Confidence: HIGH -- identical type path structure and identical name ("cybersuit control module").

#### 20. stealth suit control module

- **Aurora**: `/obj/item/rig/light/ninja` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: stealth suit control module -- icon: icons/obj/item/clothing/rig/light_ninja.dmi -- icon_state: `ninja_rig`
- **Serenity**: `/obj/item/weapon/rig/light/ninja` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: ominous suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `ninja_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 21. stealth suit control module

- **Aurora**: `/obj/item/rig/light/stealth` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: stealth suit control module -- icon: icons/obj/item/clothing/rig/light_stealth.dmi -- icon_state: `stealth_rig`
- **Serenity**: `/obj/item/weapon/rig/light/stealth` -- code/modules/clothing/spacesuits/rig/suits/light.dm
  name: stealth suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `stealth_rig`
- Confidence: HIGH -- identical type path structure and identical name ("stealth suit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 22. rescue suit control module

- **Aurora**: `/obj/item/rig/medical` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: rescue suit control module -- icon: icons/obj/item/clothing/rig/medical.dmi -- icon_state: `medical_rig`
- **Serenity**: `/obj/item/weapon/rig/medical` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: rescue suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `medical_rig`
- Confidence: HIGH -- identical type path structure and identical name ("rescue suit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 23. rescue suit control module

- **Aurora**: `/obj/item/rig/medical/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: rescue suit control module -- icon: icons/obj/item/clothing/rig/medical.dmi -- icon_state: `medical_rig`
- **Serenity**: `/obj/item/weapon/rig/medical/equipped` -- code/modules/clothing/spacesuits/rig/suits/station.dm
  name: rescue suit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `medical_rig`
- Confidence: HIGH -- identical type path structure and identical name ("rescue suit control module").

#### 24. crimson hardsuit control module

- **Aurora**: `/obj/item/rig/merc` -- code/modules/clothing/spacesuits/rig/suits/merc.dm
  name: crimson hardsuit control module -- icon: icons/obj/item/clothing/rig/merc_crimson.dmi -- icon_state: `merc_rig`
- **Serenity**: `/obj/item/weapon/rig/merc` -- code/modules/clothing/spacesuits/rig/suits/merc.dm
  name: crimson hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `merc_rig`
- Confidence: HIGH -- identical type path structure and identical name ("crimson hardsuit control module").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 25. crimson hardsuit control module

- **Aurora**: `/obj/item/rig/merc/empty` -- code/modules/clothing/spacesuits/rig/suits/merc.dm
  name: crimson hardsuit control module -- icon: icons/obj/item/clothing/rig/merc_crimson.dmi -- icon_state: `merc_rig`
- **Serenity**: `/obj/item/weapon/rig/merc/empty` -- code/modules/clothing/spacesuits/rig/suits/merc.dm
  name: crimson hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `merc_rig`
- Confidence: HIGH -- identical type path structure and identical name ("crimson hardsuit control module").

#### 26. vampire hardsuit control module

- **Aurora**: `/obj/item/rig/military` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: vampire hardsuit control module -- icon: icons/obj/item/clothing/rig/military.dmi -- icon_state: `military_rig`
- **Serenity**: `/obj/item/weapon/rig/military` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: military hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `military_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 27. vampire hardsuit control module

- **Aurora**: `/obj/item/rig/military/equipped` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: vampire hardsuit control module -- icon: icons/obj/item/clothing/rig/military.dmi -- icon_state: `military_rig`
- **Serenity**: `/obj/item/weapon/rig/military/equipped` -- code/modules/clothing/spacesuits/rig/suits/combat.dm
  name: military hardsuit control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `military_rig`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 28. NT breacher chassis control module

- **Aurora**: `/obj/item/rig/unathi` -- code/modules/clothing/spacesuits/rig/suits/alien.dm
  name: NT breacher chassis control module -- icon: icons/obj/item/clothing/rig/unathi_breacher_cheap.dmi -- icon_state: `breacher_rig_cheap`
- **Serenity**: `/obj/item/weapon/rig/unathi` -- code/modules/clothing/spacesuits/rig/suits/alien.dm
  name: NT breacher chassis control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `breacher_rig_cheap`
- Confidence: HIGH -- identical type path structure and identical name ("NT breacher chassis control module").

#### 29. breacher chassis control module

- **Aurora**: `/obj/item/rig/unathi/fancy` -- code/modules/clothing/spacesuits/rig/suits/alien.dm
  name: breacher chassis control module -- icon: icons/obj/item/clothing/rig/unathi_breacher.dmi -- icon_state: `breacher_rig`
- **Serenity**: `/obj/item/weapon/rig/unathi/fancy` -- code/modules/clothing/spacesuits/rig/suits/alien.dm
  name: breacher chassis control module -- icon: icons/obj/rig_modules.dmi -- icon_state: `breacher_rig`
- Confidence: HIGH -- identical type path structure and identical name ("breacher chassis control module").

#### 30. hardsuit upgrade

- **Aurora**: `/obj/item/rig_module` -- code/modules/clothing/spacesuits/rig/modules/modules.dm
  name: hardsuit upgrade -- icon: icons/obj/rig_modules.dmi -- icon_state: `generic`
- **Serenity**: `/obj/item/rig_module` -- code/modules/clothing/spacesuits/rig/modules/modules.dm
  name: hardsuit upgrade -- icon: icons/obj/rig_modules.dmi -- icon_state: `module`
- Confidence: HIGH -- identical type path structure and identical name ("hardsuit upgrade").

#### 31. mounted cooling unit

- **Aurora**: `/obj/item/rig_module/cooling_unit` -- code/modules/clothing/spacesuits/rig/modules/utility.dm
  name: mounted cooling unit -- icon: icons/obj/rig_modules.dmi -- icon_state: `suitcooler`
- **Serenity**: `/obj/item/rig_module/cooling_unit` -- code/modules/clothing/spacesuits/rig/modules/utility.dm
  name: mounted cooling unit -- icon: icons/obj/rig_modules.dmi -- icon_state: `module`
- Confidence: HIGH -- identical type path structure and identical name ("mounted cooling unit").

#### 32. mounted device

- **Aurora**: `/obj/item/rig_module/device` -- code/modules/clothing/spacesuits/rig/modules/utility.dm
  name: mounted device -- icon: icons/obj/rig_modules.dmi -- icon_state: `generic`
- **Serenity**: `/obj/item/rig_module/device` -- code/modules/clothing/spacesuits/rig/modules/utility.dm
  name: mounted device -- icon: icons/obj/rig_modules.dmi -- icon_state: `module`
- Confidence: HIGH -- identical type path structure and identical name ("mounted device").

#### 33. EMP dissipation module

- **Aurora**: `/obj/item/rig_module/emp_shielding` -- code/modules/clothing/spacesuits/rig/modules/ninja.dm
  name: EMP dissipation module -- icon: icons/obj/rig_modules.dmi -- icon_state: `generic`
- **Serenity**: `/obj/item/rig_module/emp_shielding` -- code/modules/clothing/spacesuits/rig/modules/computer.dm
  name: \improper EMP dissipation module -- icon: icons/obj/rig_modules.dmi -- icon_state: `module`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 34. mounted grenade launcher

- **Aurora**: `/obj/item/rig_module/grenade_launcher` -- code/modules/clothing/spacesuits/rig/modules/combat.dm
  name: mounted grenade launcher -- icon: icons/obj/rig_modules.dmi -- icon_state: `grenade`
- **Serenity**: `/obj/item/rig_module/grenade_launcher` -- code/modules/clothing/spacesuits/rig/modules/combat.dm
  name: mounted grenade launcher -- icon: icons/obj/rig_modules.dmi -- icon_state: `grenadelauncher`
- Confidence: HIGH -- identical type path structure and identical name ("mounted grenade launcher").

#### 35. mounted cleaning grenade launcher

- **Aurora**: `/obj/item/rig_module/grenade_launcher/cleaner` -- code/modules/clothing/spacesuits/rig/modules/combat.dm
  name: mounted cleaning grenade launcher -- icon: icons/obj/rig_modules.dmi -- icon_state: `grenade`
- **Serenity**: `/obj/item/rig_module/grenade_launcher/cleaner` -- code/modules/clothing/spacesuits/rig/modules/combat.dm
  name: mounted cleaning grenade launcher -- icon: icons/obj/rig_modules.dmi -- icon_state: `grenadelauncher`
- Confidence: HIGH -- identical type path structure and identical name ("mounted cleaning grenade launcher").

---

## ID Cards & Access (16)

#### 1. broken cryptographic sequencer

- **Aurora**: `/obj/item/card/emag_broken` -- code/game/objects/items/weapons/cards_ids.dm
  name: broken cryptographic sequencer -- icon: icons/obj/card.dmi -- icon_state: `emag_broken`
- **Serenity**: `/obj/item/weapon/card/emag_broken` -- code/game/objects/items/weapons/cards_ids.dm
  name: broken cryptographic sequencer -- icon: icons/obj/card.dmi -- icon_state: `emag`
- Confidence: HIGH -- identical type path structure and identical name ("broken cryptographic sequencer").

#### 2. captain's spare identification card

- **Aurora**: `/obj/item/card/id/captains_spare` -- code/game/objects/items/weapons/cards_ids.dm
  name: captain's spare identification card -- icon: icons/obj/card.dmi -- icon_state: `captain_card`
- **Serenity**: `/obj/item/weapon/card/id/captains_spare` -- code/game/objects/items/weapons/cards_ids.dm
  name: captain's spare ID -- icon: icons/obj/card.dmi -- icon_state: `gold`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 3. merchant identification card

- **Aurora**: `/obj/item/card/id/merchant` -- code/game/objects/items/weapons/cards_ids.dm
  name: merchant identification card -- icon: icons/obj/card.dmi -- icon_state: `centcom`
- **Serenity**: `/obj/item/weapon/card/id/merchant` -- code/game/objects/items/weapons/cards_ids.dm
  name: identification card -- icon: icons/obj/card.dmi -- icon_state: `trader`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 4. agent card

- **Aurora**: `/obj/item/card/id/syndicate` -- code/game/objects/items/weapons/cards_ids_syndicate.dm
  name: agent card -- icon: icons/obj/card.dmi -- icon_state: `id`
- **Serenity**: `/obj/item/weapon/card/id/syndicate` -- code/game/objects/items/weapons/cards_ids_syndicate.dm
  name: contrator card -- icon: icons/obj/card.dmi -- icon_state: `syndicate`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "agent card" / Serenity: "contrator card") -- verify these are truly the same item before swapping.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 5. standard encryption key

- **Aurora**: `/obj/item/encryptionkey/binary` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: standard encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/binary` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `cypherkey`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 6. operations radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_cargo` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: operations radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `cargo_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_cargo` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: supply radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `cargo_cypherkey`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 7. command radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_com` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: command radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `com_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_com` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: command radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `com_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("command radio encryption key").

#### 8. engineering radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_eng` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: engineering radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `eng_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_eng` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: engineering radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `eng_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("engineering radio encryption key").

#### 9. medical radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_med` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: medical radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `med_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_med` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: medical radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `med_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("medical radio encryption key").

#### 10. medical research radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_medsci` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: medical research radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `medsci_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_medsci` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: medical research radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `medsci_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("medical research radio encryption key").

#### 11. robotics radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_rob` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: robotics radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `rob_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_rob` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: robotics radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `rob_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("robotics radio encryption key").

#### 12. science radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_sci` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: science radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `sci_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_sci` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: science radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `sci_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("science radio encryption key").

#### 13. security radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_sec` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: security radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `sec_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_sec` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: security radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `sec_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("security radio encryption key").

#### 14. service radio encryption key

- **Aurora**: `/obj/item/encryptionkey/headset_service` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: service radio encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `srv_cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/headset_service` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: service radio encryption key -- icon: _(unset -- inherited/default)_ -- icon_state: `srv_cypherkey`
- Confidence: HIGH -- identical type path structure and identical name ("service radio encryption key").

#### 15. standard encryption key

- **Aurora**: `/obj/item/encryptionkey/raider` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: standard encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/raider` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `cypherkey`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

#### 16. standard encryption key

- **Aurora**: `/obj/item/encryptionkey/syndicate` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: standard encryption key -- icon: icons/obj/item/encryptionkey.dmi -- icon_state: `cypherkey`
- **Serenity**: `/obj/item/device/encryptionkey/syndicate` -- code/game/objects/items/devices/radio/encryptionkey.dm
  name: _(not set in-file -- inherited)_ -- icon: _(unset -- inherited/default)_ -- icon_state: `cypherkey`
- Confidence: MODERATE -- type path (and, where present, icon_state literal) matches exactly, but an explicit name/desc isn't set on one or both sides in-file (likely inherited) -- verify visually before swapping.

---

## Implants (13)

#### 1. chemical implant

- **Aurora**: `/obj/item/implant/chem` -- code/game/objects/items/weapons/implants/implants/chem.dm
  name: chemical implant -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_chem`
- **Serenity**: `/obj/item/weapon/implant/chem` -- code/game/objects/items/weapons/implants/implants/chem.dm
  name: chemical implant -- icon: icons/obj/device.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("chemical implant").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 2. compressed matter implant

- **Aurora**: `/obj/item/implant/compressed` -- code/game/objects/items/weapons/implants/implants/compressed_matter.dm
  name: compressed matter implant -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_storage`
- **Serenity**: `/obj/item/weapon/implant/compressed` -- code/game/objects/items/weapons/implants/implants/compressed.dm
  name: compressed matter implant -- icon: icons/obj/device.dmi -- icon_state: `implant_evil`
- Confidence: HIGH -- identical type path structure and identical name ("compressed matter implant").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 3. death alarm implant

- **Aurora**: `/obj/item/implant/death_alarm` -- code/game/objects/items/weapons/implants/implants/death_alarm.dm
  name: death alarm implant -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_deathalarm`
- **Serenity**: `/obj/item/weapon/implant/death_alarm` -- code/game/objects/items/weapons/implants/implants/death_alarm.dm
  name: death alarm implant -- icon: icons/obj/device.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("death alarm implant").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 4. explosive implant

- **Aurora**: `/obj/item/implant/explosive` -- code/game/objects/items/weapons/implants/implants/explosive.dm
  name: explosive implant -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_explosive`
- **Serenity**: `/obj/item/weapon/implant/explosive` -- code/game/objects/items/weapons/implants/implants/explosive.dm
  name: explosive implant -- icon: icons/obj/device.dmi -- icon_state: `implant_evil`
- Confidence: HIGH -- identical type path structure and identical name ("explosive implant").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 5. freedom implant

- **Aurora**: `/obj/item/implant/freedom` -- code/game/objects/items/weapons/implants/implants/freedom.dm
  name: freedom implant -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_freedom`
- **Serenity**: `/obj/item/weapon/implant/freedom` -- code/game/objects/items/weapons/implants/implants/freedom.dm
  name: freedom implant -- icon: icons/obj/device.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("freedom implant").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 6. tracking implant

- **Aurora**: `/obj/item/implant/tracking` -- code/game/objects/items/weapons/implants/implants/tracking.dm
  name: tracking implant -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_freedom`
- **Serenity**: `/obj/item/weapon/implant/tracking` -- code/game/objects/items/weapons/implants/implants/tracking.dm
  name: tracking implant -- icon: icons/obj/device.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("tracking implant").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. uplink

- **Aurora**: `/obj/item/implant/uplink` -- code/game/objects/items/weapons/implants/implants/uplink.dm
  name: uplink -- icon: _(unset -- inherited/default)_ -- icon_state: `implant_uplink`
- **Serenity**: `/obj/item/weapon/implant/uplink` -- code/game/objects/items/weapons/implants/implants/uplink.dm
  name: uplink -- icon: icons/obj/device.dmi -- icon_state: `implant`
- Confidence: HIGH -- identical type path structure and identical name ("uplink").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 8. implant case

- **Aurora**: `/obj/item/implantcase` -- code/game/objects/items/weapons/implants/implantcase.dm
  name: implant case -- icon: icons/obj/item/implants.dmi -- icon_state: `implantcase`
- **Serenity**: `/obj/item/weapon/implantcase` -- code/game/objects/items/weapons/implants/implantcase.dm
  name: glass case -- icon: icons/obj/items.dmi -- icon_state: `implantcase-0`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 9. `/obj/item/implantcase` and subtypes (7 types)

- **Aurora**: `/obj/item/implantcase` + subtypes -- code/game/objects/items/weapons/implants/implants/chem.dm
  icon: icons/obj/item/implants.dmi -- icon_state: `implantcase`
- **Serenity**: equivalent family -- code/game/objects/items/weapons/implants/implants/chem.dm
  icon: icons/obj/items.dmi -- icon_state: `implantcase-0`
- Subtypes covered: `/chem`, `/death_alarm`, `/explosive`, `/freedom`, `/health`, `/loyalty`, `/tracking`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 10. implanter

- **Aurora**: `/obj/item/implanter` -- code/game/objects/items/weapons/implants/implanter.dm
  name: implanter -- icon: icons/obj/item/implants.dmi -- icon_state: `implanter-0`
- **Serenity**: `/obj/item/weapon/implanter` -- code/game/objects/items/weapons/implants/implanter.dm
  name: implanter -- icon: icons/obj/items.dmi -- icon_state: `implanter0`
- Confidence: HIGH -- identical type path structure and identical name ("implanter").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 11. implanter (C)

- **Aurora**: `/obj/item/implanter/compressed` -- code/game/objects/items/weapons/implants/implants/compressed_matter.dm
  name: implanter (C) -- icon: icons/obj/item/implants.dmi -- icon_state: `implanter-0`
- **Serenity**: `/obj/item/weapon/implanter/compressed` -- code/game/objects/items/weapons/implants/implants/compressed.dm
  name: implanter (C) -- icon: icons/obj/items.dmi -- icon_state: `cimplanter1`
- Confidence: HIGH -- identical type path structure and identical name ("implanter (C)").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 12. `/obj/item/implanter` and subtypes (4 types)

- **Aurora**: `/obj/item/implanter` + subtypes -- code/game/objects/items/weapons/implants/implants/explosive.dm
  icon: icons/obj/item/implants.dmi -- icon_state: `implanter-0`
- **Serenity**: equivalent family -- code/game/objects/items/weapons/implants/implants/explosive.dm
  icon: icons/obj/items.dmi -- icon_state: `implanter0`
- Subtypes covered: `/explosive`, `/freedom`, `/loyalty`, `/uplink`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

#### 13. implantpad

- **Aurora**: `/obj/item/implantpad` -- code/game/objects/items/weapons/implants/implantpad.dm
  name: implantpad -- icon: icons/obj/item/implants.dmi -- icon_state: `implantpad-0`
- **Serenity**: `/obj/item/weapon/implantpad` -- code/game/objects/items/weapons/implants/implantpad.dm
  name: implant pad -- icon: icons/obj/items.dmi -- icon_state: `implantpad-0`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

---

## DNA Injectors (Genetics) (1)

#### 1. `/obj/item/dnainjector` and subtypes (47 types)

- **Aurora**: `/obj/item/dnainjector` + subtypes -- code/game/objects/items/weapons/dna_injector.dm
  icon: icons/obj/item/reagent_containers/syringe.dmi -- icon_state: `dnainjector`
- **Serenity**: equivalent family -- code/game/objects/items/weapons/dna_injector.dm
  icon: icons/obj/items.dmi -- icon_state: `dnainjector`
- Subtypes covered: `(base)`, `/antiblind`, `/anticlumsy`, `/anticold`, `/anticough`, `/antideaf`, `/antiepi`, `/antifire`, `/antiglasses`, `/antihallucination`, `/antihulk`, `/antiinsulation`, `/antimidgit`, `/antimorph`, `/antinobreath`, `/antinoprints`, `/antiregenerate`, `/antiremoteview`, `/antirunfast`, `/antistutt`, `/antitele`, `/antitour`, `/antixray`, `/blindmut`, `/clumsymut`, `/cold`, `/coughmut`, `/deafmut`, `/epimut`, `/firemut`, `/glassesmut`, `/h2m`, `/hallucination`, `/hulkmut`, `/insulation`, `/m2h`, `/midgit`, `/morph`, `/nobreath`, `/noprints`, `/regenerate`, `/remoteview`, `/runfast`, `/stuttmut`, `/telemut`, `/tourmut`, `/xraymut`
- Confidence: HIGH -- identical type-path family on both sides (only the legacy weapon/device segment differs), and every member subtype shares the exact same icon/icon_state pairing on each side.

---

## Personal Care & Cosmetics (12)

#### 1. glass jar

- **Aurora**: `/obj/item/glass_jar` -- code/game/objects/items/glassjar.dm
  name: glass jar -- icon: icons/obj/item/reagent_containers/glass.dmi -- icon_state: `jar_lid`
- **Serenity**: `/obj/item/glass_jar` -- code/game/objects/items/glassjar.dm
  name: glass jar -- icon: icons/obj/items.dmi -- icon_state: `jar`
- Confidence: HIGH -- identical type path structure and identical name ("glass jar").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. plastic comb

- **Aurora**: `/obj/item/haircomb` -- code/game/objects/items/weapons/cosmetics.dm
  name: plastic comb -- icon: icons/obj/cosmetics.dmi -- icon_state: `comb`
- **Serenity**: `/obj/item/weapon/haircomb` -- code/game/objects/items/weapons/cosmetics.dm
  name: plastic comb -- icon: icons/obj/items.dmi -- icon_state: `comb`
- Confidence: HIGH -- identical type path structure and identical name ("plastic comb").

#### 3. red lipstick

- **Aurora**: `/obj/item/lipstick` -- code/game/objects/items/weapons/cosmetics.dm
  name: red lipstick -- icon: icons/obj/cosmetics.dmi -- icon_state: `lipstick`
- **Serenity**: `/obj/item/weapon/lipstick` -- code/game/objects/items/weapons/cosmetics.dm
  name: red lipstick -- icon: icons/obj/items.dmi -- icon_state: `lipstick`
- Confidence: HIGH -- identical type path structure and identical name ("red lipstick").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 4. black lipstick

- **Aurora**: `/obj/item/lipstick/black` -- code/game/objects/items/weapons/cosmetics.dm
  name: black lipstick -- icon: icons/obj/cosmetics.dmi -- icon_state: `lipstick`
- **Serenity**: `/obj/item/weapon/lipstick/black` -- code/game/objects/items/weapons/cosmetics.dm
  name: black lipstick -- icon: icons/obj/items.dmi -- icon_state: `lipstick`
- Confidence: HIGH -- identical type path structure and identical name ("black lipstick").

#### 5. jade lipstick

- **Aurora**: `/obj/item/lipstick/jade` -- code/game/objects/items/weapons/cosmetics.dm
  name: jade lipstick -- icon: icons/obj/cosmetics.dmi -- icon_state: `lipstick`
- **Serenity**: `/obj/item/weapon/lipstick/jade` -- code/game/objects/items/weapons/cosmetics.dm
  name: jade lipstick -- icon: icons/obj/items.dmi -- icon_state: `lipstick`
- Confidence: HIGH -- identical type path structure and identical name ("jade lipstick").

#### 6. purple lipstick

- **Aurora**: `/obj/item/lipstick/purple` -- code/game/objects/items/weapons/cosmetics.dm
  name: purple lipstick -- icon: icons/obj/cosmetics.dmi -- icon_state: `lipstick`
- **Serenity**: `/obj/item/weapon/lipstick/purple` -- code/game/objects/items/weapons/cosmetics.dm
  name: purple lipstick -- icon: icons/obj/items.dmi -- icon_state: `lipstick`
- Confidence: HIGH -- identical type path structure and identical name ("purple lipstick").

#### 7. lipstick

- **Aurora**: `/obj/item/lipstick/random` -- code/game/objects/items/weapons/cosmetics.dm
  name: lipstick -- icon: icons/obj/cosmetics.dmi -- icon_state: `lipstick`
- **Serenity**: `/obj/item/weapon/lipstick/random` -- code/game/objects/items/weapons/cosmetics.dm
  name: lipstick -- icon: icons/obj/items.dmi -- icon_state: `lipstick`
- Confidence: HIGH -- identical type path structure and identical name ("lipstick").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 8. ashtray

- **Aurora**: `/obj/item/material/ashtray` -- code/game/objects/items/weapons/material/ashtray.dm
  name: ashtray -- icon: icons/obj/ashtray.dmi -- icon_state: `ashtray`
- **Serenity**: `/obj/item/weapon/material/ashtray` -- code/game/objects/items/weapons/material/ashtray.dm
  name: ashtray -- icon: icons/obj/objects.dmi -- icon_state: `ashtray`
- Confidence: HIGH -- identical type path structure and identical name ("ashtray").

#### 9. soap

- **Aurora**: `/obj/item/soap` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/soap.dmi -- icon_state: `soap`
- **Serenity**: `/obj/item/weapon/soap` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/items.dmi -- icon_state: `soap`
- Confidence: HIGH -- identical type path structure and identical name ("soap").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 10. soap

- **Aurora**: `/obj/item/soap/deluxe` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/soap.dmi -- icon_state: `soapdeluxe`
- **Serenity**: `/obj/item/weapon/soap/deluxe` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/items.dmi -- icon_state: `soapdeluxe`
- Confidence: HIGH -- identical type path structure and identical name ("soap").

#### 11. soap

- **Aurora**: `/obj/item/soap/nanotrasen` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/soap.dmi -- icon_state: `soapnt`
- **Serenity**: `/obj/item/weapon/soap/nanotrasen` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/items.dmi -- icon_state: `soapnt`
- Confidence: HIGH -- identical type path structure and identical name ("soap").

#### 12. soap

- **Aurora**: `/obj/item/soap/syndie` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/soap.dmi -- icon_state: `soapsyndie`
- **Serenity**: `/obj/item/weapon/soap/syndie` -- code/game/objects/items/weapons/soap.dm
  name: soap -- icon: icons/obj/items.dmi -- icon_state: `soapsyndie`
- Confidence: HIGH -- identical type path structure and identical name ("soap").

---

## Smoking & Fire (8)

#### 1. red candle

- **Aurora**: `/obj/item/flame/candle` -- code/game/objects/items/weapons/candle.dm
  name: red candle -- icon: icons/obj/storage/fancy/candle.dmi -- icon_state: `candle1`
- **Serenity**: `/obj/item/weapon/flame/candle` -- code/game/objects/items/weapons/candle.dm
  name: red candle -- icon: icons/obj/candle.dmi -- icon_state: `candle1`
- Confidence: HIGH -- identical type path structure and identical name ("red candle").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. cheap lighter

- **Aurora**: `/obj/item/flame/lighter` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cheap lighter -- icon: icons/obj/cigs_lighters.dmi -- icon_state: `lighter-g`
- **Serenity**: `/obj/item/weapon/flame/lighter` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cheap lighter -- icon: icons/obj/items.dmi -- icon_state: `lighter-g`
- Confidence: HIGH -- identical type path structure and identical name ("cheap lighter").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 3. \improper Zippo lighter

- **Aurora**: `/obj/item/flame/lighter/zippo` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: \improper Zippo lighter -- icon: icons/obj/cigs_lighters.dmi -- icon_state: `zippo`
- **Serenity**: `/obj/item/weapon/flame/lighter/zippo` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: \improper Zippo lighter -- icon: icons/obj/items.dmi -- icon_state: `zippo`
- Confidence: HIGH -- identical type path structure and identical name ("\improper Zippo lighter").

#### 4. safety match

- **Aurora**: `/obj/item/flame/match` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: safety match -- icon: icons/obj/cigs_lighters.dmi -- icon_state: `match_unlit`
- **Serenity**: `/obj/item/weapon/flame/match` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: match -- icon: icons/obj/cigarettes.dmi -- icon_state: `match_unlit`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "safety match" / Serenity: "match") -- verify these are truly the same item before swapping.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 5. rolling paper

- **Aurora**: `/obj/item/paper/cig` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: rolling paper -- icon: icons/obj/cigs_lighters.dmi -- icon_state: `cigpaper_generic`
- **Serenity**: `/obj/item/paper/cig` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: rolling paper -- icon: icons/obj/cigarettes.dmi -- icon_state: `cig_paper`
- Confidence: HIGH -- identical type path structure and identical name ("rolling paper").

#### 6. cigarette butt

- **Aurora**: `/obj/item/trash/cigbutt` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigarette butt -- icon: icons/obj/smokables.dmi -- icon_state: `cigbutt`
- **Serenity**: `/obj/item/trash/cigbutt` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigarette butt -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigbutt`
- Confidence: HIGH -- identical type path structure and identical name ("cigarette butt").

#### 7. cigar butt

- **Aurora**: `/obj/item/trash/cigbutt/cigarbutt` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigar butt -- icon: icons/obj/smokables.dmi -- icon_state: `cigarbutt`
- **Serenity**: `/obj/item/trash/cigbutt/cigarbutt` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: cigar butt -- icon: icons/obj/clothing/masks.dmi -- icon_state: `cigarbutt`
- Confidence: HIGH -- identical type path structure and identical name ("cigar butt").

#### 8. sausage butt

- **Aurora**: `/obj/item/trash/cigbutt/sausagebutt` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: sausage butt -- icon: icons/obj/smokables.dmi -- icon_state: `sausagebutt`
- **Serenity**: `/obj/item/trash/cigbutt/sausagebutt` -- code/game/objects/items/weapons/cigs_lighters.dm
  name: sausage butt -- icon: icons/obj/clothing/masks.dmi -- icon_state: `sausagebutt`
- Confidence: HIGH -- identical type path structure and identical name ("sausage butt").

---

## Tape & Sealing (8)

#### 1. tape

- **Aurora**: `/obj/item/tape` -- code/game/objects/items/weapons/policetape.dm
  name: tape -- icon: icons/obj/policetape.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/tape` -- code/game/objects/items/weapons/policetape.dm
  name: tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("tape").
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. engineering tape

- **Aurora**: `/obj/item/tape/engineering` -- code/game/objects/items/weapons/policetape.dm
  name: engineering tape -- icon: icons/obj/policetape.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/tape/engineering` -- code/game/objects/items/weapons/policetape.dm
  name: engineering tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("engineering tape").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 3. medical tape

- **Aurora**: `/obj/item/tape/medical` -- code/game/objects/items/weapons/policetape.dm
  name: medical tape -- icon: icons/obj/policetape.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/tape/medical` -- code/game/objects/items/weapons/policetape.dm
  name: medical tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("medical tape").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 4. police tape

- **Aurora**: `/obj/item/tape/police` -- code/game/objects/items/weapons/policetape.dm
  name: police tape -- icon: icons/obj/policetape.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/tape/police` -- code/game/objects/items/weapons/policetape.dm
  name: police tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("police tape").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 5. tape roll

- **Aurora**: `/obj/item/taperoll` -- code/game/objects/items/weapons/policetape.dm
  name: tape roll -- icon: icons/obj/policetape.dmi -- icon_state: `tape`
- **Serenity**: `/obj/item/taperoll` -- code/game/objects/items/weapons/policetape.dm
  name: tape roll -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("tape roll").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 6. engineering tape

- **Aurora**: `/obj/item/taperoll/engineering` -- code/game/objects/items/weapons/policetape.dm
  name: engineering tape -- icon: icons/obj/policetape.dmi -- icon_state: `engineering_start`
- **Serenity**: `/obj/item/taperoll/engineering` -- code/game/objects/items/weapons/policetape.dm
  name: engineering tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("engineering tape").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 7. medical tape

- **Aurora**: `/obj/item/taperoll/medical` -- code/game/objects/items/weapons/policetape.dm
  name: medical tape -- icon: icons/obj/policetape.dmi -- icon_state: `medical_start`
- **Serenity**: `/obj/item/taperoll/medical` -- code/game/objects/items/weapons/policetape.dm
  name: medical tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("medical tape").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 8. police tape

- **Aurora**: `/obj/item/taperoll/police` -- code/game/objects/items/weapons/policetape.dm
  name: police tape -- icon: icons/obj/policetape.dmi -- icon_state: `police_start`
- **Serenity**: `/obj/item/taperoll/police` -- code/game/objects/items/weapons/policetape.dm
  name: police tape -- icon: icons/policetape.dmi -- icon_state: `tape`
- Confidence: HIGH -- identical type path structure and identical name ("police tape").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

---

## Medical / Morgue (1)

#### 1. stasis bag

- **Aurora**: `/obj/item/bodybag/cryobag` -- code/game/objects/items/bodybag.dm
  name: stasis bag -- icon: icons/obj/bodybag.dmi -- icon_state: `stasis_folded`
- **Serenity**: `/obj/item/bodybag/cryobag` -- code/game/objects/items/cryobag.dm
  name: stasis bag -- icon: icons/obj/cryobag.dmi -- icon_state: `bodybag_folded`
- Confidence: HIGH -- identical type path structure and identical name ("stasis bag").

---

## Engineering Misc (4)

#### 1. blueprints

- **Aurora**: `/obj/item/blueprints` -- code/game/objects/items/blueprints.dm
  name: blueprints -- icon: icons/obj/item/blueprints.dmi -- icon_state: `blueprints`
- **Serenity**: `/obj/item/blueprints` -- code/game/objects/items/blueprints.dm
  name: blueprints -- icon: icons/obj/items.dmi -- icon_state: `blueprints`
- Confidence: HIGH -- identical type path structure and identical name ("blueprints").

#### 2. voidsuit modification kit

- **Aurora**: `/obj/item/kit/suit` -- code/game/objects/items/paintkit.dm
  name: voidsuit modification kit -- icon: icons/obj/item/modkit.dmi -- icon_state: `modkit`
- **Serenity**: `/obj/item/device/kit/suit` -- code/game/objects/items/paintkit.dm
  name: voidsuit modification kit -- icon: icons/obj/device.dmi -- icon_state: `modkit`
- Confidence: HIGH -- identical type path structure and identical name ("voidsuit modification kit").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 3. voidsuit modification kit

- **Aurora**: `/obj/item/modkit` -- code/game/objects/items/devices/modkit.dm
  name: voidsuit modification kit -- icon: icons/obj/item/modkit.dmi -- icon_state: `modkit`
- **Serenity**: `/obj/item/device/modkit` -- code/game/objects/items/devices/modkit.dm
  name: hardsuit modification kit -- icon: icons/obj/device.dmi -- icon_state: `modkit`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 4. tajaran voidsuit modification kit

- **Aurora**: `/obj/item/modkit/tajaran` -- code/game/objects/items/devices/modkit.dm
  name: tajaran voidsuit modification kit -- icon: icons/obj/item/modkit.dmi -- icon_state: `modkit`
- **Serenity**: `/obj/item/device/modkit/tajaran` -- code/game/objects/items/devices/modkit.dm
  name: tajaran hardsuit modification kit -- icon: icons/obj/device.dmi -- icon_state: `modkit`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

---

## Food, Toys & Misc Props (5)

#### 1. shooting target

- **Aurora**: `/obj/item/target` -- code/game/objects/items/shooting_range.dm
  name: shooting target -- icon: icons/obj/target_stake.dmi -- icon_state: `target_h`
- **Serenity**: `/obj/item/target` -- code/game/objects/items/shooting_range.dm
  name: shooting target -- icon: icons/obj/objects.dmi -- icon_state: `target_h`
- Confidence: HIGH -- identical type path structure and identical name ("shooting target").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 2. balloon

- **Aurora**: `/obj/item/toy/balloon` -- code/game/objects/items/toys.dm
  name: balloon -- icon: icons/obj/toy.dmi -- icon_state: _(unset -- inherited/default)_
- **Serenity**: `/obj/item/toy/balloon` -- code/game/objects/items/toys.dm
  name: \improper 'criminal' balloon -- icon: icons/obj/weapons.dmi -- icon_state: `syndballoon`
- Confidence: MODERATE -- type path matches exactly, but name/description text differs somewhat (Aurora: "balloon" / Serenity: "\improper 'criminal' balloon") -- verify these are truly the same item before swapping.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 3. 'motivational' balloon

- **Aurora**: `/obj/item/toy/balloon/nanotrasen` -- code/game/objects/items/toys.dm
  name: 'motivational' balloon -- icon: icons/obj/toy.dmi -- icon_state: `ntballoon`
- **Serenity**: `/obj/item/toy/balloon/nanotrasen` -- code/game/objects/items/toys.dm
  name: \improper 'motivational' balloon -- icon: icons/obj/weapons.dmi -- icon_state: `ntballoon`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 4. completely glitched action figure

- **Aurora**: `/obj/item/toy/figure` -- code/game/objects/items/toys.dm
  name: completely glitched action figure -- icon: icons/obj/toy.dmi -- icon_state: `glitched`
- **Serenity**: `/obj/item/toy/figure` -- code/game/objects/items/toys.dm
  name: Completely Glitched action figure -- icon: icons/obj/toy.dmi -- icon_state: `assistant`
- Confidence: HIGH -- identical type path structure and identical name ("completely glitched action figure").

#### 5. candle

- **Aurora**: `/obj/item/trash/candle` -- code/game/objects/items/trash.dm
  name: candle -- icon: icons/obj/storage/fancy/candle.dmi -- icon_state: `candle4`
- **Serenity**: `/obj/item/trash/candle` -- code/game/objects/items/trash.dm
  name: candle -- icon: icons/obj/candle.dmi -- icon_state: `candle4`
- Confidence: HIGH -- identical type path structure and identical name ("candle").

---

## Misc / Other (11)

#### 1. safari net

- **Aurora**: `/obj/item/energy_net/safari` -- code/game/objects/items/safari_net.dm
  name: safari net -- icon: icons/effects/effects.dmi -- icon_state: `safarinet`
- **Serenity**: `/obj/item/weapon/energy_net/safari` -- code/game/objects/items/weapons/weaponry.dm
  name: animal net -- icon: icons/effects/effects.dmi -- icon_state: `energynet`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.

#### 2. flamethrower

- **Aurora**: `/obj/item/flamethrower` -- code/game/objects/items/weapons/flamethrower.dm
  name: flamethrower -- icon: icons/obj/item/flamethrower.dmi -- icon_state: `flamethrower1`
- **Serenity**: `/obj/item/weapon/flamethrower` -- code/game/objects/items/weapons/flamethrower.dm
  name: flamethrower -- icon: icons/obj/flamethrower.dmi -- icon_state: `flamethrowerbase`
- Confidence: HIGH -- identical type path structure and identical name ("flamethrower").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.

#### 3. unfinished concealed knife

- **Aurora**: `/obj/item/material/butterflyconstruction` -- code/game/objects/items/weapons/improvised_components.dm
  name: unfinished concealed knife -- icon: icons/obj/weapons_build.dmi -- icon_state: `butterflystep1`
- **Serenity**: `/obj/item/weapon/material/butterflyconstruction` -- code/game/objects/items/weapons/improvised_components.dm
  name: unfinished concealed knife -- icon: icons/obj/buildingobject.dmi -- icon_state: `butterflystep1`
- Confidence: HIGH -- identical type path structure and identical name ("unfinished concealed knife").

#### 4. concealed knife grip

- **Aurora**: `/obj/item/material/butterflyhandle` -- code/game/objects/items/weapons/improvised_components.dm
  name: concealed knife grip -- icon: icons/obj/weapons_build.dmi -- icon_state: `butterfly1`
- **Serenity**: `/obj/item/weapon/material/butterflyhandle` -- code/game/objects/items/weapons/improvised_components.dm
  name: concealed knife grip -- icon: icons/obj/buildingobject.dmi -- icon_state: `butterfly1`
- Confidence: HIGH -- identical type path structure and identical name ("concealed knife grip").

#### 5. fork

- **Aurora**: `/obj/item/material/kitchen/utensil/fork/plastic` -- code/game/objects/items/weapons/material/kitchen.dm
  name: fork -- icon: icons/obj/kitchen.dmi -- icon_state: `plastic_fork`
- **Serenity**: `/obj/item/weapon/material/kitchen/utensil/fork/plastic` -- code/game/objects/items/weapons/material/kitchen.dm
  name: fork -- icon: icons/obj/kitchen.dmi -- icon_state: `fork`
- Confidence: HIGH -- identical type path structure and identical name ("fork").

#### 6. spoon

- **Aurora**: `/obj/item/material/kitchen/utensil/spoon/plastic` -- code/game/objects/items/weapons/material/kitchen.dm
  name: spoon -- icon: icons/obj/kitchen.dmi -- icon_state: `plastic_spoon`
- **Serenity**: `/obj/item/weapon/material/kitchen/utensil/spoon/plastic` -- code/game/objects/items/weapons/material/kitchen.dm
  name: spoon -- icon: icons/obj/kitchen.dmi -- icon_state: `spoon`
- Confidence: HIGH -- identical type path structure and identical name ("spoon").

#### 7. bat

- **Aurora**: `/obj/item/material/twohanded/baseballbat` -- code/game/objects/items/weapons/material/bats.dm
  name: bat -- icon: icons/obj/weapons.dmi -- icon_state: `metalbat0`
- **Serenity**: `/obj/item/weapon/material/twohanded/baseballbat` -- code/game/objects/items/weapons/material/bats.dm
  name: bat -- icon: _(unset -- inherited/default)_ -- icon_state: `metalbat0`
- Confidence: HIGH -- identical type path structure and identical name ("bat").
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 8. wired rod

- **Aurora**: `/obj/item/material/wirerod` -- code/game/objects/items/weapons/improvised_components.dm
  name: wired rod -- icon: icons/obj/weapons.dmi -- icon_state: `wiredrod`
- **Serenity**: `/obj/item/weapon/material/wirerod` -- code/game/objects/items/weapons/improvised_components.dm
  name: wired rod -- icon: _(unset -- inherited/default)_ -- icon_state: `wiredrod`
- Confidence: HIGH -- identical type path structure and identical name ("wired rod").

#### 9. chain of command

- **Aurora**: `/obj/item/melee/chainofcommand` -- code/game/objects/items/weapons/melee/misc.dm
  name: chain of command -- icon: icons/obj/weapons.dmi -- icon_state: `chain`
- **Serenity**: `/obj/item/weapon/melee/chainofcommand` -- code/game/objects/items/weapons/melee/misc.dm
  name: chain of command -- icon: _(unset -- inherited/default)_ -- icon_state: `chain`
- Confidence: HIGH -- identical type path structure and identical name ("chain of command").

#### 10. portable suit cooling unit

- **Aurora**: `/obj/item/suit_cooling_unit` -- code/game/objects/items/devices/suit_cooling.dm
  name: portable suit cooling unit -- icon: icons/obj/item/suitcooler.dmi -- icon_state: `suitcooler0`
- **Serenity**: `/obj/item/device/suit_cooling_unit` -- code/game/objects/items/devices/suit_cooling.dm
  name: portable cooling unit -- icon: icons/obj/suitcooler.dmi -- icon_state: `suitcooler0`
- Confidence: HIGH -- identical type path structure (after accounting for Serenity's legacy weapon/device path segment) and closely-matching name/description.
- **CAUTION**: Aurora changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm all needed states exist on the Serenity sprite sheet before swapping.
- **CAUTION**: Serenity changes this item's icon/icon_state from within a proc elsewhere in its code (e.g. on state change, damage, charge, emag, wear) -- confirm the replacement covers the same dynamic states.

#### 11. used stasis bag

- **Aurora**: `/obj/item/usedcryobag` -- code/game/objects/items/bodybag.dm
  name: used stasis bag -- icon: icons/obj/bodybag.dmi -- icon_state: `cryobag_used`
- **Serenity**: `/obj/item/usedcryobag` -- code/game/objects/items/cryobag.dm
  name: used stasis bag -- icon: icons/obj/cryobag.dmi -- icon_state: `bodybag_used`
- Confidence: HIGH -- identical type path structure and identical name ("used stasis bag").

---
