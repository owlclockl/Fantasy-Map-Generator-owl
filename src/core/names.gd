class_name FmgNames
extends Node
## Names: Markov-chain name generator. Port of names-generator.ts.
## Autoloaded as `Names`. Reads cultures from `Sim.pack`.

const VOWELS := "aeiouyɑ'əøɛœæɶɒɨɪɔɐʊɤɯаоиеёэыуюяàèìòùỳẁȁȅȉȍȕáéíóúýẃőűâêîôûŷŵäëïöüÿẅãẽĩõũỹąęįǫųāēīōūȳăĕĭŏŭǎěǐǒǔȧėȯẏẇạẹịọụỵẉḛḭṵṳ"

var name_bases: Array = []
var chains: Array = [] # per base: Dictionary letter -> PackedStringArray of syllables


func _ready() -> void:
	name_bases = NameBasesData.get_default_name_bases()
	chains.resize(name_bases.size())


static func is_vowel(c: String) -> bool:
	return VOWELS.contains(c)


static func capitalize(s: String) -> String:
	if s.is_empty():
		return s
	return s[0].to_upper() + s.substr(1)


## Build the Markov chain: key is a letter (or "" for word start), value is
## an array of possible next syllables
func calculate_chain(names_list: String) -> Dictionary:
	var chain := {}
	var available_names := names_list.split(",")

	for n: String in available_names:
		var name_v := n.strip_edges().to_lower()
		var basic: bool = not name_v.contains("ё") # treat as basic-ASCII pipeline
		for ch: String in name_v:
			if ch.unicode_at(0) > 127:
				basic = false
				break

		# split word into pseudo-syllables
		var i: int = -1
		var syllable := ""
		while i < name_v.length():
			var prev: String = name_v[i] if i >= 0 else ""
			var v: bool = false
			syllable = ""
			var c: int = i + 1
			while c < name_v.length() and syllable.length() < 5:
				var that: String = name_v[c]
				var next: String = name_v[c + 1] if c + 1 < name_v.length() else ""
				syllable += that
				if syllable == " " or syllable == "-":
					break
				if next == "" or next == " " or next == "-":
					break
				if is_vowel(that):
					v = true
				if that == "y" and next == "e":
					c += 1
					continue
				if basic:
					if that == "o" and next == "o":
						c += 1
						continue
					if that == "e" and next == "e":
						c += 1
						continue
					if that == "a" and next == "e":
						c += 1
						continue
					if that == "c" and next == "h":
						c += 1
						continue
				if is_vowel(that) == is_vowel(next):
					break
				if v and c + 2 < name_v.length() and is_vowel(name_v[c + 2]):
					break
				c += 1

			if not chain.has(prev):
				chain[prev] = []
			(chain[prev] as Array).append(syllable)

			var advance: int = syllable.length() if syllable.length() > 0 else 1
			i += advance
	return chain


func update_chain(index: int) -> void:
	if index < 0 or index >= name_bases.size():
		return
	chains[index] = calculate_chain(name_bases[index]["b"])


## Generate a name using the Markov chain of the given base
func get_base(base: int, min_len: int = 0, max_len: int = 0, dupl: String = "~") -> String:
	if base < 0 or base >= name_bases.size():
		base = 0
	if not chains[base] is Dictionary:
		update_chain(base)

	var data: Dictionary = chains[base]
	if data.is_empty() or not data.has(""):
		push_warning("Namebase %d is incorrect" % base)
		return "Error"

	if min_len == 0:
		min_len = name_bases[base]["min"]
	if max_len == 0:
		max_len = name_bases[base]["max"]
	if dupl == "~":
		dupl = name_bases[base]["d"]

	var v: Array = data[""]
	var cur: String = v[Sim.rng.rand(v.size() - 1)]
	var w := ""
	for i: int in 20:
		if cur == "":
			# end of word
			if w.length() < min_len:
				cur = ""
				w = ""
				v = data[""]
			else:
				break
		else:
			if w.length() + cur.length() > max_len:
				if w.length() < min_len:
					w += cur
				break
			else:
				var last_char: String = cur[cur.length() - 1]
				v = data.get(last_char, data[""])

		w += cur
		cur = v[Sim.rng.rand(v.size() - 1)]

	# parse word to get a final name
	var l: String = w[w.length() - 1]
	if l == "'" or l == " " or l == "-":
		w = w.substr(0, w.length() - 1)

	var name_v := ""
	var chars := []
	for ch: String in w:
		chars.append(ch)
	for i: int in chars.size():
		var c: String = chars[i]
		var next_c: String = chars[i + 1] if i + 1 < chars.size() else ""
		if c == next_c and not dupl.contains(c):
			continue
		if name_v.is_empty():
			name_v = c.to_upper()
			continue
		if name_v[name_v.length() - 1] == "-" and c == " ":
			continue
		if name_v[name_v.length() - 1] == " ":
			name_v += c.to_upper()
			continue
		if name_v[name_v.length() - 1] == "-":
			name_v += c.to_upper()
			continue
		if c == "a" and next_c == "e":
			continue
		if i + 2 < chars.size() and c == next_c and c == chars[i + 2]:
			continue
		name_v += c

	# join the word if any part has only 1 letter
	var parts := name_v.split(" ")
	var has_short: bool = false
	for p: String in parts:
		if p.length() < 2:
			has_short = true
			break
	if has_short:
		var joined := ""
		for pi: int in parts.size():
			joined += parts[pi].to_lower() if pi > 0 else parts[pi]
		name_v = joined

	if name_v.length() < 2:
		var all_names: PackedStringArray = name_bases[base]["b"].split(",")
		name_v = all_names[Sim.rng.rand(all_names.size() - 1)]

	return name_v


func get_culture(culture: int, min_len: int = 0, max_len: int = 0, dupl: String = "~") -> String:
	if not Sim.pack or culture < 0 or culture >= Sim.pack.cultures.size():
		return get_base(1, min_len, max_len, dupl)
	var base: int = Sim.pack.cultures[culture]["base"]
	return get_base(base, min_len, max_len, dupl)


func get_base_short(base: int) -> String:
	var min_len: int = name_bases[base]["min"] - 1 if base >= 0 and base < name_bases.size() else 3
	var max_len: int = maxi(name_bases[base]["max"] - 2, min_len) if base >= 0 and base < name_bases.size() else 8
	return get_base(base, min_len, max_len, "")


func get_culture_short(culture: int) -> String:
	if not Sim.pack or culture < 0 or culture >= Sim.pack.cultures.size():
		return get_base_short(1)
	return get_base_short(Sim.pack.cultures[culture]["base"])


func _validate_suffix(name_v: String, suffix: String) -> String:
	if name_v.length() >= suffix.length() and name_v.substr(name_v.length() - suffix.length()) == suffix:
		return name_v
	var s1: String = suffix[0]
	if name_v[name_v.length() - 1] == s1:
		name_v = name_v.substr(0, name_v.length() - 1)
	if is_vowel(s1) == is_vowel(name_v[name_v.length() - 1]) and is_vowel(s1) == is_vowel(name_v[name_v.length() - 2]):
		name_v = name_v.substr(0, name_v.length() - 1)
	if name_v[name_v.length() - 1] == s1:
		name_v = name_v.substr(0, name_v.length() - 1)
	return name_v + suffix


func _add_suffix(name_v: String) -> String:
	var suffix: String = "ia" if Sim.rng.P(0.8) else "land"
	if suffix == "ia" and name_v.length() > 6:
		name_v = name_v.substr(0, 3)
	elif suffix == "land" and name_v.length() > 6:
		name_v = name_v.substr(0, 5)
	return _validate_suffix(name_v, suffix)


## Generate a state name based on capital or random name and culture-specific suffix
func get_state(name_v: String, culture: int, base: int = -1) -> String:
	if base < 0 and Sim.pack and culture >= 0 and culture < Sim.pack.cultures.size():
		base = Sim.pack.cultures[culture]["base"]
	elif base < 0:
		base = 1

	if name_v.contains(" "):
		name_v = capitalize(name_v.replace(" ", "").to_lower())
	if name_v.length() > 6 and name_v.substr(name_v.length() - 4) == "berg":
		name_v = name_v.substr(0, name_v.length() - 4)
	if name_v.length() > 5 and name_v.substr(name_v.length() - 3) == "ton":
		name_v = name_v.substr(0, name_v.length() - 3)

	if base == 5 and (name_v.ends_with("sk") or name_v.ends_with("ev") or name_v.ends_with("ov")):
		name_v = name_v.substr(0, name_v.length() - 2)
	elif base == 12:
		return name_v if is_vowel(name_v[name_v.length() - 1]) else name_v + "u"
	elif base == 18 and Sim.rng.P(0.4):
		name_v = ("Al" + name_v.to_lower()) if is_vowel(name_v[0].to_lower()) else ("Al " + name_v)

	if base > 32 and base < 42:
		return name_v

	if name_v.length() > 3 and is_vowel(name_v[name_v.length() - 1]):
		if is_vowel(name_v[name_v.length() - 2]) and Sim.rng.P(0.85):
			name_v = name_v.substr(0, name_v.length() - 2)
		elif Sim.rng.P(0.7):
			name_v = name_v.substr(0, name_v.length() - 1)
		else:
			return name_v
	elif Sim.rng.P(0.4):
		return name_v

	var suffix := "ia"
	var rnd: float = Sim.rng.random()
	var l: int = name_v.length()
	if base == 3 and rnd < 0.03 and l < 7: suffix = "terra"
	elif base == 4 and rnd < 0.03 and l < 7: suffix = "terra"
	elif base == 13 and rnd < 0.03 and l < 7: suffix = "terra"
	elif base == 2 and rnd < 0.03 and l < 7: suffix = "terre"
	elif base == 0 and rnd < 0.5 and l < 7: suffix = "land"
	elif base == 1 and rnd < 0.4 and l < 7: suffix = "land"
	elif base == 6 and rnd < 0.3 and l < 7: suffix = "land"
	elif base == 32 and rnd < 0.1 and l < 7: suffix = "land"
	elif base == 7 and rnd < 0.1: suffix = "eia"
	elif base == 9 and rnd < 0.35: suffix = "maa"
	elif base == 15 and rnd < 0.4 and l < 6: suffix = "orszag"
	elif base == 16: suffix = "yurt" if rnd < 0.6 else "eli"
	elif base == 10: suffix = "guk"
	elif base == 11: suffix = " Guo"
	elif base == 14: suffix = ("tlan" if rnd < 0.5 and l < 6 else "co")
	elif base == 17 and rnd < 0.8: suffix = "a"
	elif base == 18 and rnd < 0.8: suffix = "a"

	return _validate_suffix(name_v, suffix)


func get_map_name() -> String:
	var base: int = 2 if Sim.rng.P(0.7) else (Sim.rng.rand(0, 6) if Sim.rng.P(0.5) else Sim.rng.rand(0, 31))
	if base >= name_bases.size():
		base = 1
	var min_len: int = name_bases[base]["min"] - 1
	var max_len: int = maxi(name_bases[base]["max"] - 3, min_len)
	var base_name := get_base(base, min_len, max_len, "")
	if Sim.rng.P(0.7):
		return _add_suffix(base_name)
	return base_name


## Abbreviation for a culture name, avoiding duplicates (languageUtils.abbreviate)
static func abbreviate(name_v: String, restricted: Array = []) -> String:
	var parsed: String = name_v.replace("Old ", "O ").replace("(", "").replace(")", "")
	var words := parsed.split(" ")
	var letters := "".join(words)

	var code: String = (words[0][0] + words[1][0]) if words.size() == 2 else letters.substr(0, 2)
	var i: int = 1
	while i < letters.length() - 1 and restricted.has(code):
		code = letters[0] + letters[i].to_upper()
		i += 1
	return code
