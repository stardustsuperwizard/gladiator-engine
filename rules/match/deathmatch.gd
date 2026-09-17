## Spec §11.2's MVP game mode: one fighter defeated is one point of VP for the
## fighter that defeated it, and nothing else awards any.
##
## `GameMode` is what every caller asks; this class is the implementation its
## registry resolves `MODE_ID` to, and Deathmatch's one rule lives here and
## nowhere else.
##
## **The number stays authored.** `defeat_award()` returns
## `combat_profile.defeat_award` unchanged -- this class decides only that the
## defeat award applies under this mode, never what the award's value is.
##
## `RefCounted`, static methods only, never instantiated -- the shape
## `MatchVictory`, `StandardVictory`, `EndSegment` and `ChargeLockout` already
## use.
class_name Deathmatch
extends RefCounted

## The id `RoundProfile.game_mode` carries to select this mode, and the key
## `GameMode`'s registry files it under.
const MODE_ID := "deathmatch"


## Spec §11.2's Deathmatch award for a defeat resolved under `combat_profile`:
## the profile's own `defeat_award`, restated by no other number.
static func defeat_award(combat_profile: CombatProfile) -> int:
	return combat_profile.defeat_award
