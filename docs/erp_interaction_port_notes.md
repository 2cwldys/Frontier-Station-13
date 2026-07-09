# Intimate interaction menu: status and remaining work

Source reference codebase: `D:\GIT Storage\InterBay` (BYOND/DM SS13 fork). This doc originally
inventoried InterBay's drag-mob-onto-mob ERP system; it now tracks what's been implemented in
Aurora-Persistence versus what's still a stub for follow-up work.

## What's implemented

A working, non-explicit scaffold: drag your own mob onto another human mob to open a small
interaction menu, gated on a server config flag and, for real players, both participants'
individual opt-in preference, with both participants' consciousness/restraint state checked
(unlike InterBay, which only ever checked the initiator).

| Piece | File | What it does |
|---|---|---|
| Bitflag | `code/__DEFINES/misc.dm` | `INTIMATE_INTERACTIONS_ENABLED BITFLAG(11)` on `prefs.toggles_secondary` |
| Preference verb | `code/modules/client/preferences_toggles.dm` | `/client/verb/toggle_intimate_interactions()` |
| Config var + parser | `code/controllers/configuration.dm` | `intimate_interactions_allowed`, parsed from `allow_intimate_interactions` |
| Config flag | `config/example/config.txt` | `#ALLOW_INTIMATE_INTERACTIONS` (commented out / off by default) |
| Drag hook | `code/modules/mob/living/carbon/human/intimate_interactions.dm` | `mouse_drop_receive()` override -- validates config flag, both mobs are human, the dragger dragged *themselves*, the dragger has `client` and opted in, and neither is unconscious/dead/restrained, then opens the menu |
| Menu | same file | `open_intimate_menu()` -- builds a `/datum/browser` popup with 15 working actions: Hug, Super Hug, Shake hands, Wave, Bow, Pat on the head, Kiss on the cheek, Cheer for, High five, Slap, Flip off, Knock on, Spit at, Threaten, Stick tongue out at |
| Dispatch | `code/modules/mob/living/carbon/human/human.dm`, `Topic()`, `href_list["intimate_action"]` branch | Re-validates config flag, the dragger's preference, target consent (if applicable), both states, and adjacency at click time (defense in depth against a stale popup), then handles all 15 actions above via `visible_message()` (Super Hug via its own proc, see below) |
| Include | `aurorastation.dme` | `intimate_interactions.dm` registered alphabetically in the human mob include block |

Both **EXTENSION POINT** comments (in `intimate_interactions.dm`'s `open_intimate_menu()` and in
`human.dm`'s `Topic()`) mark exactly where to add more actions.

### Super Hug (rate-limited action)

`receive_super_hug()` in `intimate_interactions.dm` is a plain repeatable-action-with-cooldown
pattern: the same `visible_message()` + placeholder `playsound()` fires identically on every
use (nothing distinguishes any particular use), tracked via `super_hug_count` on the target.
After `SUPER_HUG_CAP` (5) uses, the count resets and `super_hug_cooldown_until` is set
`SUPER_HUG_COOLDOWN` (5 minutes) into the future; further attempts during that window just get
a `to_chat()` message and do nothing else. No decal, no second sound, no distinct payoff
reserved for the capping use -- deliberately uniform throughout.

### NPC / unpossessed targets

The target doesn't have to be a real connected player. The gate is `ckey`, not `client`
(matching the existing `if(src.ckey || src.client)` convention at `living.dm:888`):

- **`src.ckey` set** (a real player, whether currently connected or SSD) -- full gate applies:
  needs `client`, needs `INTIMATE_INTERACTIONS_ENABLED` in their `prefs.toggles_secondary`,
  and needs to be conscious/unrestrained. This last part is deliberate: the preference is a
  standing, general opt-in, not consent to any specific interaction at any specific moment --
  it does not waive the requirement that the target be conscious and unrestrained to receive
  an action. An SSD player's body is *not* treated as free-for-all -- no client means no way
  to confirm consent, so it's blocked the same as before.
- **`src.ckey` unset** (a genuine NPC/unpossessed humanoid body, never controlled by a player)
  -- both the preference/client check *and* the `stat`/`restrained()` state check are skipped
  entirely. There's no real person behind an NPC, so there's no consent to bypass.

The dragger (initiator) must always be a real connected player, conscious and unrestrained,
regardless of what's being targeted.

This is checked both in `mouse_drop_receive()` (menu-open time) and in `Topic()`'s
`intimate_action` branch (click time).

### Sounds

Two real InterBay sound assets were ported (non-explicit, generic social-gesture sounds, not
tied to any explicit act): `honk/sound/interactions/hug.ogg` and `honk/sound/interactions/
slap.ogg`, copied to `sound/effects/interactions/hug.ogg` and `sound/effects/interactions/
slap.ogg`. Wired in via `playsound()` matching InterBay's original call sites (`human.dm:736,
749, 773` in InterBay): `hug` plays `hug.ogg`; `five` (high five) and `slap` both play
`slap.ogg`, same as InterBay reused it for both. `assslap` was never ported (left out
intentionally, see the 14-action list above) so its would-be `slap.ogg` reuse doesn't apply.

No other non-explicit action had a sound in InterBay -- confirmed in the original asset
investigation (`bow`, `pet`, `give`, `kiss`, `cheer`, `handshake`, `wave`, `fuckyou`, `knock`,
`spit`, `threaten`, `tongue`, `pull` had no associated `playsound()` calls anywhere in
InterBay's source).

### Kiss placeholder sound

No kiss/smooch-appropriate sound exists anywhere in InterBay or Aurora's `sound/` tree
(checked both). The `kiss` case in `human.dm`'s `Topic()` plays `sound/effects/pop.ogg` as an
explicit placeholder (marked with a `// TODO:` comment) -- that file is otherwise used for
sci-fi teleport/materialize pops (RFD, telepad, glasses), so it's a stand-in, not a permanent
choice. Swap it for a
dedicated asset when one exists; it's a one-line `playsound()` change.

## How to try it in-game

1. Uncomment `#ALLOW_INTIMATE_INTERACTIONS` in `config/example/config.txt` (or your live
   server's config) and recompile/restart.
2. Each player who wants to participate runs the **Toggle Intimate Interactions** verb
   (Preferences.Game category) to opt in. Both the dragger and any player target need this on;
   NPC targets don't need it (see above).
3. Make sure both mobs are conscious and not restrained.
4. Drag your own mob's sprite onto the other mob's sprite to open the popup.
5. Click any of the 14 actions to fire it -- a `visible_message()` to anyone nearby (plus a
   placeholder sound for kiss).

## What's NOT implemented (by design -- see below)

Genital anatomy, explicit sexual-act procs, and the associated audio/sprite assets were
deliberately left out of this pass. If you want to add them yourself, here's where to look:

### 1. Anatomy flags

InterBay gates ERP acts on ad-hoc booleans computed inline (`haspenis`, `hasvagina`, `hasanus_p`,
`isnude`, `mouthfree`) -- see `InterBay/code/modules/mob/living/carbon/human/interactions.dm:30-48`
(`get_pleasure_amt()`, `is_nude()`) and the species-level enable flags at
`InterBay/code/modules/mob/living/carbon/human/species/species.dm:48-49` (`genitals`, `anus`).

Aurora has no equivalent anatomy vars. Don't copy InterBay's ad-hoc boolean style -- follow
Aurora's existing organ-presence + clothing-coverage pairing instead, e.g.
`check_has_mouth()` (`human.dm:1001`) + `check_mouth_coverage()`
(`human_defense.dm:147`), composed together in `can_drink()` (`human.dm:1927-1939`). A new
genital check should follow the same `should_have_organ(BP_XXX)` / coverage-check shape rather
than a flat boolean var.

### 2. Explicit act procs

InterBay's logic lives in `InterBay/code/modules/mob/living/carbon/human/interactions.dm`:

- `fuck(mob/H, mob/P, hole)` -- lines 227-443, a `switch(hole)` over `vaglick`, `fingering`,
  `blowjob`, `vaginal`, `anal`, `oral`, `mount`. Each branch plays a sound, shows a
  `visible_message()`, and calls `do_fucking_animation()` / `cum()`.
- `cum(mob/H, mob/P, hole)` -- lines 159-226, plays an orgasm sound and spawns a cleanable decal.
- `moan()` -- lines 444-460.
- `handle_lust()` -- lines 463-473.
- `do_fucking_animation(mob/P)` -- lines 475-499, a purely positional pixel-offset shake, no icon
  overlay needed.

To add one of these to the Aurora scaffold:
1. Add a new `<a href='byond://?src=[REF(user)];intimate_action=xxx;intimate_target=[REF(src)]'>Label</a>`
   line in `open_intimate_menu()` (`intimate_interactions.dm`), gated behind whatever anatomy
   check you add per item 1 above, mirroring how the existing three actions are listed.
2. Add a matching `if("xxx")` case in the `switch(href_list["intimate_action"])` block in
   `human.dm`'s `Topic()`, translating the relevant InterBay logic. The consent/state/config
   re-validation already happens before the `switch` -- you don't need to repeat it per-case.
3. Consider a per-actor cooldown var (InterBay has `erpcooldown`, `interactions.dm:150`,
   checked in `human.dm:852/860/869/881` of InterBay) if you don't want an action spammable.

### 3. Assets

Not copied. `honk/` in the InterBay repo root is a self-contained resource pack (its own `code/`
copy is dead, unused) -- only the sounds/icons are real:

- [ ] `honk/sound/interactions/*.ogg` (52 files) -> copy into an Aurora `sound/` subfolder, e.g.
  `sound/effects/interactions/`. Call sites and exact filenames documented in the "Sound files"
  table below.
- [ ] `honk/icons/effects/cum.dmi` -> `icons/effects/` (decal sprite, if you add a `cum()`
  equivalent -- follow Aurora's existing cleanable-decal pattern:
  `/obj/effect/decal/cleanable/vomit` at
  `code/game/objects/effects/decals/Cleanable/misc.dm:155-168` for the simple case, or
  `.../Cleanable/humans.dm:3-100+` (`blood`) for a more elaborate DNA-tracked version.)
- [ ] `honk/icons/obj/items/dildo.dmi` -> `icons/obj/items/` (only needed if porting the
  `/obj/item/weapon/dildo` item, `InterBay/.../interactions.dm:530-605`).

Sound reference table (InterBay call sites, for translating step 2 above):

| Interaction | Files | InterBay call site |
|---|---|---|
| Male orgasm | `final_m1-5.ogg` | `interactions.dm:197` |
| Female orgasm | `final_f1-3.ogg` | `interactions.dm:210` |
| Fingering | `champ_fingering.ogg` | `interactions.dm:277` |
| Blowjob | `bj1-11.ogg` | `interactions.dm:297` |
| Vaginal | `bang1-3.ogg` | `interactions.dm:340` |
| Anal | `bang1-3.ogg` | `interactions.dm:374` |
| Oral | `oral1-2.ogg`, (Slime bonus) `champ1-2.ogg` | `interactions.dm:398, 400` |
| Mount | `bang1-3.ogg`, (Slime bonus) `champ1-2.ogg` | `interactions.dm:440, 442` |
| Moan (default) | `moan_f1-7.ogg` / `moan_m1-7.ogg` | `interactions.dm:457` |
| Moan (in closet, female) | `under_moan_f1-4.ogg` | `interactions.dm:459` |

Orphaned/unused in InterBay, skip: `purr1-3.ogg`, `swallow.ogg`, `moan_m0.ogg`, `moan_m12.ogg`.

## Gaps InterBay had -- status in Aurora

1. **Target consent/opt-in** -- **done**. Both participants must have
   `INTIMATE_INTERACTIONS_ENABLED` set via `toggle_intimate_interactions()`, checked both when
   the menu opens (`mouse_drop_receive`) and again at click time (`Topic()`).
2. **Target state check** -- **done**. `target.stat`/`target.restrained()` checked alongside the
   initiator's, at both stages.
3. **Server-side config gate** -- **done**. `ALLOW_INTIMATE_INTERACTIONS` in `config.txt`, off by
   default.
4. **Href namespacing** -- **done**. Uses `intimate_action`/`intimate_target`, not InterBay's bare
   `interaction` key.
