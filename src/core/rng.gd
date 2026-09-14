class_name FmgRng
extends RefCounted
## Seeded PRNG: a faithful port of the Alea PRNG used by the original
## Fantasy Map Generator (Johannes Baagoe's Alea, as packaged by the `alea` npm lib).
## All generator modules draw from one shared instance so the same seed
## always reproduces the same map.

var _s0: float = 0.0
var _s1: float = 0.0
var _s2: float = 0.0
var _c: int = 1


## Port of Alea's mash(): n += charCode; h = K*n; n = h>>>0; h -= n; h *= n; n = h>>>0
static func _mash(data: String) -> float:
	var n: int = 0xefc8249d
	for i: int in data.length():
		n = (n + data.unicode_at(i)) & 0xFFFFFFFF
		var h: float = 0.02519603282416938 * float(n)
		var ni: int = int(h) & 0xFFFFFFFF # h >>> 0
		var hf: float = h - float(ni)
		hf *= float(ni)
		n = int(hf) & 0xFFFFFFFF
	return (float(n) + 16777216.0) * 2.3283064365386963e-10 # (n + 2^24) * 2^-32


func _init(seed_value: String = "0") -> void:
	reseed(seed_value)


func reseed(seed_value: String) -> void:
	# mash(' ') three times, then subtract mash(seed) — exactly like Alea
	_s0 = _mash(" ")
	_s1 = _mash(" ")
	_s2 = _mash(" ")
	_s0 -= _mash(seed_value)
	if _s0 < 0.0:
		_s0 += 1.0
	_s1 -= _mash(seed_value)
	if _s1 < 0.0:
		_s1 += 1.0
	_s2 -= _mash(seed_value)
	if _s2 < 0.0:
		_s2 += 1.0
	_c = 1


## Like Math.random() in the original: float in [0, 1)
func random() -> float:
	var t: float = 2091639.0 * _s0 + float(_c) * 2.3283064365386963e-10
	_c = int(t)
	_s0 = _s1
	_s1 = _s2
	_s2 = t - float(_c)
	return _s2


# --- convenience helpers, ports of FMG's probabilityUtils ---

func randf() -> float:
	return random()


## FMG rand(min, max): random INTEGER in [min, max]; rand(n) means [0, n]
func rand(min_v: int, max_v: int = -1) -> int:
	if max_v < 0:
		max_v = min_v
		min_v = 0
	return int(random() * float(max_v - min_v + 1)) + min_v


## FMG P(probability): true with the given probability
func P(probability: float) -> bool:
	if probability >= 1.0:
		return true
	if probability <= 0.0:
		return false
	return random() < probability


## FMG ra(array): random element
func ra(arr: Array) -> Variant:
	return arr[int(random() * float(arr.size()))]


func range_f(min_v: float, max_v: float) -> float:
	return min_v + random() * (max_v - min_v)


## FMG rw(object): random key weighted by value
func rw(weights: Dictionary) -> String:
	var total: float = 0.0
	for k: String in weights:
		total += float(weights[k])
	var roll: float = random() * total
	for k: String in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys().back()


## FMG biased(min, max, ex): integer biased towards min by exponent
func biased(min_v: int, max_v: int, ex: float) -> int:
	return int(round(float(min_v) + float(max_v - min_v) * pow(random(), ex)))


## FMG gauss(expected, deviation, min, max, round): clamped gaussian
func gauss(expected: float = 100.0, deviation: float = 30.0, min_v: float = 0.0, max_v: float = 300.0, round_to: int = 0) -> float:
	var u1: float = maxf(random(), 1e-12)
	var u2: float = random()
	var g: float = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
	var value: float = clampf(expected + g * deviation, min_v, max_v)
	if round_to > 0:
		var m: float = pow(10.0, round_to)
		return roundf(value * m) / m
	return value


## FMG getNumberInRange("3-5" | "2" | "0.5"): parses count ranges of the heightmap templates
func get_number_in_range(r: String) -> float:
	var trimmed := r.strip_edges()
	var slash := trimmed.split("-")
	if slash.size() != 2:
		var whole: float = trimmed.to_float()
		var fl: float = floorf(whole)
		return fl + (1.0 if P(whole - fl) else 0.0)
	var sign_mult: float = -1.0 if trimmed.begins_with("-") else 1.0
	var body := trimmed.substr(1) if trimmed.begins_with("-") else trimmed
	var parts := body.split("-")
	var a: float = parts[0].to_float() * sign_mult
	var b: float = parts[1].to_float()
	var count: float = float(rand(int(a), int(b)))
	if count < 0.0:
		return 0.0
	return count


static func generate_seed(rng: FmgRng) -> String:
	return str(int(rng.random() * 1e9))


# --- small numeric utils (numberUtils.ts) ---
static func rn(v: float, d: int = 0) -> float:
	var m: float = pow(10.0, d)
	return roundf(v * m) / m


static func minmax(value: float, min_v: float, max_v: float) -> float:
	return minf(maxf(value, min_v), max_v)


static func lim(v: float) -> float:
	return clampf(v, 0.0, 100.0)


static func normalize(val: float, min_v: float, max_v: float) -> float:
	if max_v == min_v:
		return 0.0
	return clampf((val - min_v) / (max_v - min_v), 0.0, 1.0)
