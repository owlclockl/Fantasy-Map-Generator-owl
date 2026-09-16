class_name FmgDiplomacy
extends RefCounted
## Diplomacy and campaigns. Port of states-generator.ts generateCampaigns /
## generateDiplomacy: weighted relation matrix (neighbors / neighbors of
## neighbors / far lands / naval), vassals, war declarations with allied and
## vassal participation, chronicle kept on the Neutrals state.

const YEAR: int = 1000 # options.map.lore.calendar.year default

const WAR_TYPES := {
	"War": 6, "Conflict": 2, "Campaign": 4, "Invasion": 2, "Rebellion": 2,
	"Conquest": 2, "Intervention": 1, "Expedition": 1, "Crusade": 1
}

# relation pick weights by context (upstream generateDiplomacy)
const NEIBS := {"Ally": 1, "Friendly": 2, "Neutral": 1, "Suspicion": 10, "Rival": 9}
const NEIBS_OF_NEIBS := {"Ally": 10, "Friendly": 8, "Neutral": 5, "Suspicion": 1}
const FAR := {"Friendly": 1, "Neutral": 12, "Suspicion": 2, "Unknown": 6}
const NAVALS := {"Neutral": 1, "Suspicion": 2, "Rival": 1, "Unknown": 1}

# alert contribution per relation (used by military-generator)
const RELATION_RATE := {
	"x": 0.0, "Ally": -0.2, "Friendly": -0.1, "Neutral": 0.0, "Suspicion": 0.1,
	"Enemy": 1.0, "Unknown": 0.0, "Rival": 0.5, "Vassal": 0.5, "Suzerain": -0.5
}

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	generate_campaigns()
	generate_diplomacy()


## Historic campaigns for every state (one per neighbor, 20% replaced by a
## culture-derived campaign against "wild" lands).
func generate_campaigns() -> void:
	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		state["campaigns"] = _generate_campaign(state)


func _generate_campaign(state: Dictionary) -> Array:
	var neighbors: Array = state.get("neighbors", [])
	if neighbors.is_empty():
		neighbors = [0]
	var campaigns: Array = []
	for neib: Variant in neighbors:
		var neib_id: int = int(neib)
		var name_v: String
		if neib_id != 0 and rng.P(0.8) and neib_id < pack.states.size():
			name_v = pack.states[neib_id].get("name", "")
		else:
			name_v = Names.get_culture_short(int(state.get("culture", 0)))
		var start: int = int(rng.gauss(float(YEAR - 100), 150.0, 1.0, float(YEAR - 6)))
		var end: int = start + int(rng.gauss(4.0, 5.0, 1.0, float(maxi(YEAR - start - 1, 1))))
		campaigns.append({
			"name": "%s %s" % [get_adjective(name_v), rng.rw(WAR_TYPES)],
			"start": start, "end": end,
			"attacker": int(state["i"]), "defender": neib_id
		})
	campaigns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start"]) < int(b["start"]))
	return campaigns


## Full relation matrix + vassal copying + war declarations.
func generate_diplomacy() -> void:
	var states: Array = pack.states
	if states.is_empty():
		return
	states[0]["diplomacy"] = []
	var chronicle: Array = states[0]["diplomacy"]

	var n_states: int = states.size()
	var state_areas := PackedFloat32Array()
	state_areas.resize(n_states)
	for i: int in pack.cell_count():
		if pack.h[i] >= 20 and pack.state[i] > 0 and pack.state[i] < n_states:
			state_areas[pack.state[i]] += pack.area[i] if pack.area.size() > i else 1.0

	for state in states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		var arr: Array = []
		arr.resize(n_states)
		arr.fill("x")
		state["diplomacy"] = arr
		state["campaigns"] = state.get("campaigns", [])

	var valid: Array = []
	for s_idx: int in range(1, n_states):
		if states[s_idx] != null and int(states[s_idx].get("i", 0)) > 0:
			valid.append(s_idx)
	if valid.size() < 2:
		return

	var area_sum: float = 0.0
	for s_idx: int in valid:
		area_sum += state_areas[s_idx]
	var area_mean: float = area_sum / float(valid.size())

	# generic relations
	for f: int in range(1, n_states):
		if states[f] == null or int(states[f].get("i", 0)) == 0:
			continue
		var f_diplomacy: Array = states[f]["diplomacy"]
		if f_diplomacy.has("Vassal"):
			# vassals copy relations from their suzerain
			var suzerain: int = f_diplomacy.find("Vassal")
			for i: int in range(1, n_states):
				if i == f or i == suzerain or states[i] == null or int(states[i].get("i", 0)) == 0:
					continue
				f_diplomacy[i] = states[suzerain]["diplomacy"][i]
				if states[suzerain]["diplomacy"][i] == "Suzerain":
					f_diplomacy[i] = "Ally"
				for e: int in range(1, n_states):
					if e == f or e == suzerain or states[e] == null or int(states[e].get("i", 0)) == 0:
						continue
					var e_rel: String = states[e]["diplomacy"][suzerain]
					if e_rel == "Suzerain" or e_rel == "Vassal":
						continue
					states[e]["diplomacy"][f] = e_rel
			continue

		for t: int in range(f + 1, n_states):
			if states[t] == null or int(states[t].get("i", 0)) == 0:
				continue
			var t_diplomacy: Array = states[t]["diplomacy"]
			if t_diplomacy.has("Vassal"):
				var suzerain: int = t_diplomacy.find("Vassal")
				f_diplomacy[t] = f_diplomacy[suzerain]
				continue

			var naval: bool = states[f].get("type", "") == "Naval" \
				and states[t].get("type", "") == "Naval" \
				and pack.f[int(states[f]["center"])] != pack.f[int(states[t]["center"])]
			var f_neighbors: Array = states[f].get("neighbors", [])
			var neib: bool = false if naval else f_neighbors.has(t)
			var neib_of_neib: bool = false
			if not naval and not neib:
				for n: Variant in f_neighbors:
					var n_id: int = int(n)
					if n_id > 0 and n_id < n_states and states[n_id] != null:
						if (states[n_id].get("neighbors", []) as Array).has(t):
							neib_of_neib = true
							break

			var status: String
			if naval:
				status = rng.rw(NAVALS)
			elif neib:
				status = rng.rw(NEIBS)
			elif neib_of_neib:
				status = rng.rw(NEIBS_OF_NEIBS)
			else:
				status = rng.rw(FAR)

			# add vassal
			if neib and rng.P(0.8) and state_areas[f] > area_mean \
					and state_areas[t] < area_mean \
					and state_areas[t] > 0.0 \
					and state_areas[f] / state_areas[t] > 2.0:
				status = "Vassal"
			f_diplomacy[t] = "Suzerain" if status == "Vassal" else status
			t_diplomacy[f] = status

	# declare wars
	for attacker: int in range(1, n_states):
		if states[attacker] == null or int(states[attacker].get("i", 0)) == 0:
			continue
		var ad: Array = states[attacker]["diplomacy"]
		if not ad.has("Rival"):
			continue # no rivals to attack
		if ad.has("Vassal"):
			continue # not independent
		if ad.has("Enemy"):
			continue # already at war

		var rival_ids: Array = []
		for d: int in range(1, n_states):
			if ad[d] == "Rival" and states[d] != null and not (states[d]["diplomacy"] as Array).has("Vassal"):
				rival_ids.append(d)
		if rival_ids.is_empty():
			continue
		var defender: int = int(rng.ra(rival_ids))

		var ap: float = state_areas[attacker] * float(states[attacker].get("expansionism", 1.0))
		var dp: float = state_areas[defender] * float(states[defender].get("expansionism", 1.0))
		if ap < dp * rng.gauss(1.6, 0.8, 0.0, 10.0, 2):
			continue # defender is too strong

		var an: String = states[attacker].get("name", "")
		var dn: String = states[defender].get("name", "")
		var attackers: Array = [attacker]
		var defenders: Array = [defender]
		var dd: Array = states[defender]["diplomacy"]

		var name_v: String = "%s-%sian War" % [an, trim_vowels(dn)]
		var start: int = YEAR - int(rng.gauss(2.0, 3.0, 0.0, 10.0))
		var war: Array = [name_v, "%s declared a war on its rival %s" % [an, dn]]
		var campaign := {"name": name_v, "start": start, "attacker": attacker, "defender": defender}
		(states[attacker]["campaigns"] as Array).append(campaign)
		(states[defender]["campaigns"] as Array).append(campaign)

		# attacker vassals join the war
		for d: int in range(1, n_states):
			if ad[d] == "Suzerain":
				attackers.append(d)
				war.append("%s's vassal %s joined the war on attackers side" % [an, states[d].get("name", "")])

		# defender vassals join the war
		for d: int in range(1, n_states):
			if dd[d] == "Suzerain":
				defenders.append(d)
				war.append("%s's vassal %s joined the war on defenders side" % [dn, states[d].get("name", "")])

		ap = 0.0
		for a: Variant in attackers:
			ap += state_areas[int(a)] * float(states[int(a)].get("expansionism", 1.0))
		dp = 0.0
		for d: Variant in defenders:
			dp += state_areas[int(d)] * float(states[int(d)].get("expansionism", 1.0))

		# defender allies join (or sever the pact if frightened by the attacker)
		for d: int in range(1, n_states):
			if dd[d] != "Ally" or (states[d]["diplomacy"] as Array).has("Vassal"):
				continue
			var ally_name: String = states[d].get("name", "")
			if states[d]["diplomacy"][attacker] != "Rival" and dp > 0.0 \
					and ap / dp > 2.0 * rng.gauss(1.6, 0.8, 0.0, 10.0, 2):
				var reason: String = "Being already at war," if (states[d]["diplomacy"] as Array).has("Enemy") else "Frightened by %s," % an
				war.append("%s %s severed the defense pact with %s" % [reason, ally_name, dn])
				dd[d] = "Suspicion"
				states[d]["diplomacy"][defender] = "Suspicion"
				continue
			defenders.append(d)
			dp += state_areas[d] * float(states[d].get("expansionism", 1.0))
			war.append("%s's ally %s joined the war on defenders side" % [dn, ally_name])
			# ally vassals join
			for v: int in range(1, n_states):
				if states[d]["diplomacy"][v] == "Suzerain":
					defenders.append(v)
					dp += state_areas[v] * float(states[v].get("expansionism", 1.0))
					war.append("%s's vassal %s joined the war on defenders side" % [ally_name, states[v].get("name", "")])

		# attacker allies join if the defender is their rival or the coalition is strong enough
		for d: int in range(1, n_states):
			if ad[d] != "Ally" or (states[d]["diplomacy"] as Array).has("Vassal") or defenders.has(d):
				continue
			var ally_name: String = states[d].get("name", "")
			if states[d]["diplomacy"][defender] != "Rival" and (rng.P(0.2) or ap <= dp * 1.2):
				war.append("%s's ally %s avoided entering the war" % [an, ally_name])
				continue
			var allies: Array = []
			for e: int in range(1, n_states):
				if states[d]["diplomacy"][e] == "Ally":
					allies.append(e)
			var both_sides: bool = false
			for ally: Variant in allies:
				if defenders.has(int(ally)):
					both_sides = true
					break
			if both_sides:
				war.append("%s's ally %s did not join the war as its allies are in war on both sides" % [an, ally_name])
				continue
			attackers.append(d)
			ap += state_areas[d] * float(states[d].get("expansionism", 1.0))
			war.append("%s's ally %s joined the war on attackers side" % [an, ally_name])
			# ally vassals join
			for v: int in range(1, n_states):
				if states[d]["diplomacy"][v] == "Suzerain":
					attackers.append(v)
					ap += state_areas[v] * float(states[v].get("expansionism", 1.0))
					war.append("%s's vassal %s joined the war on attackers side" % [ally_name, states[v].get("name", "")])

		# change relations to Enemy for all participants
		for a: Variant in attackers:
			for d: Variant in defenders:
				states[int(a)]["diplomacy"][int(d)] = "Enemy"
				states[int(d)]["diplomacy"][int(a)] = "Enemy"
		chronicle.append(war)


# ---------------------------------------------------------------------------
# Language helpers (languageUtils.ts)

static func trim_vowels(s: String, min_length: int = 3) -> String:
	var out: String = s
	while out.length() > min_length and Names.is_vowel(out.right(1)):
		out = out.left(out.length() - 1)
	return out


## Port of getAdjective: turn a state/nation noun into an adjective.
static func get_adjective(noun: String) -> String:
	if noun.is_empty():
		return noun
	if noun.ends_with(" Guo"):
		return noun.left(noun.length() - 4)
	if noun.ends_with("orszag"):
		return noun + "ian" if noun.length() < 9 else noun.left(noun.length() - 6)
	if noun.ends_with("stan"):
		return noun + "i" if noun.length() < 9 else trim_vowels(noun.left(noun.length() - 4))
	if noun.ends_with("land"):
		if noun.length() > 9:
			return noun.left(noun.length() - 4)
		var root: String = trim_vowels(noun.left(noun.length() - 4), 0)
		if root.length() < 3:
			return noun + "ic"
		if root.length() < 4:
			return root + "lish"
		return root + "ish"
	if noun.ends_with("que"):
		return noun.left(noun.length() - 3) + "can"
	if noun.ends_with("a") or noun.ends_with("u") or noun.ends_with("i") \
			or noun.ends_with("e") or noun.ends_with("ay"):
		return noun + "n"
	if noun.ends_with("o"):
		return noun.left(noun.length() - 1) + "an"
	if noun.ends_with("os"):
		var root: String = trim_vowels(noun.left(noun.length() - 2), 0)
		return noun.left(noun.length() - 1) if root.length() < 4 else root + "ian"
	if noun.ends_with("es"):
		var root: String = trim_vowels(noun.left(noun.length() - 2), 0)
		return noun.left(noun.length() - 1) if root.length() > 7 else root + "ian"
	if noun.ends_with("l") or noun.ends_with("n"):
		return noun + "ese"
	if noun.ends_with("ad") or noun.ends_with("an"):
		return noun + "ian"
	return noun
