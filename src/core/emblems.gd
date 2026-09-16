class_name FmgEmblems
extends RefCounted
## Heraldry. Simplified port of emblems-generator.ts: tincture selection
## with the original weights (metals/colours/stains per element kind),
## divisions, ordinaries and charges. The data model matches the original
## ({t1, t2, tc, division, ordinary, charge, shield}) so renderers can grow.
## Patterns (furs) are not ported in this edition.

const TINCTURE_COLORS := {
	"argent": "#fafafa", "or": "#ffe066", "gules": "#d7374a", "sable": "#333333",
	"azure": "#377cd7", "vert": "#26c061", "purpure": "#522d5b",
	"murrey": "#85185b", "sanguine": "#b63a3a", "tenné": "#cc7f19"
}

# tinctures.ts weights per element kind
const TINCTURE_RULES := {
	"field": {"metals": 3.0, "colours": 4.0, "stains": 0.03},
	"division": {"metals": 5.0, "colours": 8.0, "stains": 0.03},
	"charge": {"metals": 2.0, "colours": 3.0, "stains": 0.05}
}

const METALS := {"argent": 3, "or": 2}
const COLOURS := {"gules": 5, "azure": 4, "sable": 3, "purpure": 3, "vert": 2}
const STAINS := {"murrey": 1, "sanguine": 1, "tenné": 1}

# divisions.ts variant weights
const DIVISIONS := {
	"perPale": 5, "perFess": 5, "perBend": 2, "perBendSinister": 1,
	"perChevron": 1, "perChevronReversed": 1, "perCross": 5,
	"perPile": 1, "perSaltire": 1
}

const ORDINARIES := {"fess": 3, "pale": 3, "bend": 2, "cross": 3, "chief": 1, "bordure": 1}

# charges subset (charges.ts categories collapsed to weighted names)
const CHARGES := {
	"Lion": 8, "Eagle": 7, "Star": 6, "Cross": 6, "Sun": 4, "Moon": 3,
	"Boar": 3, "Wolf": 3, "Bear": 3, "Horse": 3, "Stag": 3, "Raven": 2,
	"Swan": 2, "Fish": 2, "Serpent": 2, "Dragon": 3, "Griffin": 2,
	"Tower": 3, "Castle": 2, "Ship": 2, "Anchor": 2, "Crown": 3,
	"Sword": 3, "Axe": 2, "Key": 2, "Rose": 2, "Lily": 2, "Oak": 2, "Sheaf": 2
}

const SHIELDS := {"heater": 6, "french": 3, "spanish": 2, "round": 1}

var rng: FmgRng
var pack: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref


func generate() -> void:
	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		state["co"] = generate_emblem()
	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		if int(burg.get("capital", 0)) == 1:
			var state_id: int = int(burg.get("state", 0))
			var parent: Dictionary = {}
			if state_id > 0 and state_id < pack.states.size() and pack.states[state_id] != null:
				parent = pack.states[state_id].get("co", {})
			burg["co"] = generate_emblem(parent, 0.35)


## One coat of arms. With a parent, parts may be inherited (kinship).
func generate_emblem(parent: Dictionary = {}, kinship: float = 0.0) -> Dictionary:
	var used_tinctures: Array = []
	var emblem := {"shield": rng.rw(SHIELDS)}

	var t1: String = _get_tincture("field", used_tinctures)
	emblem["t1"] = t1
	used_tinctures.append(t1)

	var divisioned: bool = rng.P(0.6)
	var ordinary: String = ""
	if divisioned:
		var division: String = parent.get("division", {}).get("division", "") if parent.has("division") else ""
		if division == "" or not rng.P(maxf(kinship - 0.1, 0.0)):
			division = rng.rw(DIVISIONS)
		var t2: String = _get_tincture("division", used_tinctures, t1)
		emblem["division"] = {"division": division, "t": t2}
		used_tinctures.append(t2)
	else:
		if rng.P(0.35):
			ordinary = rng.rw(ORDINARIES)
			var t2: String = _get_tincture("charge", used_tinctures, t1)
			emblem["ordinaries"] = [{"ordinary": ordinary, "t": t2}]
			used_tinctures.append(t2)

	var add_charge: bool = rng.P(0.5 if emblem.has("division") else 0.93)
	if add_charge:
		var charge: String = parent.get("charges", [{}])[0].get("charge", "") \
			if parent.has("charges") and not (parent["charges"] as Array).is_empty() else ""
		if charge == "" or not rng.P(maxf(kinship - 0.1, 0.0)):
			charge = rng.rw(CHARGES)
		var against: String = t1
		if ordinary != "":
			against = emblem["ordinaries"][0]["t"]
		var tc: String = _get_tincture("charge", used_tinctures, against)
		emblem["charges"] = [{"charge": charge, "t": tc}]
	return emblem


## Weighted tincture pick: element kind decides metals/colours/stains odds,
## then the group table; avoids the tinctures listed in `avoid`.
func _get_tincture(kind: String, used: Array, avoid: String = "") -> String:
	var rules: Dictionary = TINCTURE_RULES[kind]
	var group: String = rng.rw({"metals": int(float(rules["metals"]) * 100.0), "colours": int(float(rules["colours"]) * 100.0), "stains": maxi(int(float(rules["stains"]) * 100.0), 1)})
	var table: Dictionary = METALS if group == "metals" else (COLOURS if group == "colours" else STAINS)
	for _attempt: int in 8:
		var pick: String = rng.rw(table)
		if pick != avoid and not used.has(pick):
			return pick
	return rng.rw(table)
