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
## Alea's mash keeps its 32-bit state *between* calls (the original creates one
## masher per generator and reuses it eight times while seeding)
var _mash_state: float = 0.0


## Port of Alea's Mash 0.9 (alea/alea.js):
##   n += charCode; h = K*n; n = h>>>0; h -= n; h *= n; n = h>>>0; h -= n;
##   n += h * 2^32;  return (n>>>0) * 2^-32
func _mash(data: String) -> float:
	for i: int in data.length():
		_mash_state += float(data.unicode_at(i))
		var h: float = 0.02519603282416938 * _mash_state
		_mash_state = float(_to_uint32(h))
		h -= _mash_state
		h *= _mash_state
		_mash_state = float(_to_uint32(h))
		h -= _mash_state
		_mash_state += h * 4294967296.0 # * 2^32
	return float(_to_uint32(_mash_state)) * 2.3283064365386963e-10 # * 2^-32


## JavaScript's `value >>> 0`: truncate towards zero, then wrap into 32 bits
static func _to_uint32(value: float) -> int:
	return int(value) & 0xFFFFFFFF


func _init(seed_value: String = "0") -> void:
	reseed(seed_value)


func reseed(seed_value: String) -> void:
	# Alea: mash(' ') three times, then subtract mash(seed) from each state
	_mash_state = float(0xefc8249d)
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


## FMG rand(min, max) with float bounds: Math.floor(random() * (max - min + 1)) + min
func rand_f(min_v: float, max_v: float) -> float:
	return floorf(random() * (max_v - min_v + 1.0)) + min_v


## FMG rand(min, max): random INTEGER in [min, max]; rand(n) means [0, n]
func rand(min_v: int, max_v: int = -1) -> int:
	if max_v < 0:
		max_v = min_v
		min_v = 0
	return int(rand_f(float(min_v), float(max_v)))


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


## FMG rw(object): random key weighted by value. The original expands the
## weights into a plain array and picks one element, so we do the same — the
## uniform draw maps to the same key as in the browser build.
func rw(weights: Dictionary) -> String:
	var pool: Array[String] = []
	for k: Variant in weights:
		var weight: int = int(weights[k])
		for _i: int in maxi(weight, 0):
			pool.append(String(k))
	if pool.is_empty():
		return ""
	return pool[int(random() * float(pool.size()))]


## FMG biased(min, max, ex): integer biased towards min by exponent
func biased(min_v: int, max_v: int, ex: float) -> int:
	return int(round(float(min_v) + float(max_v - min_v) * pow(random(), ex)))


## FMG gauss(expected, deviation, min, max, round): a clamped gaussian rounded
## to `round` decimals. Same algorithm as the original, which wraps d3-random's
## randomNormal (Marsaglia polar method, rejecting samples outside the unit
## circle) in minmax() and rn() — so the random stream stays in step.
func gauss(expected: float = 100.0, deviation: float = 30.0, min_v: float = 0.0, max_v: float = 300.0, round_to: int = 0) -> float:
	var x: float = 0.0
	var y: float = 0.0
	var r: float = 0.0
	while true:
		x = random() * 2.0 - 1.0
		y = random() * 2.0 - 1.0
		r = x * x + y * y
		if r != 0.0 and r <= 1.0:
			break
	var normal: float = y * sqrt(-2.0 * log(r) / r)
	return rn(clampf(expected + normal * deviation, min_v, max_v), round_to)


## FMG getNumberInRange("3-5" | "2" | "0.5" | "-3"): parses the count ranges
## of the heightmap templates. Numbers keep their fractional part, a leading
## minus signs the lower bound ("-1-3" means rand(-1, 3)).
func get_number_in_range(r: String) -> float:
	var text := r.strip_edges()
	if text.is_valid_float():
		var whole: float = text.to_float()
		var truncated: float = float(int(whole)) # JS ~~ truncates towards zero
		return truncated + (1.0 if P(whole - truncated) else 0.0)
	var sign_mult: float = -1.0 if text.begins_with("-") else 1.0
	var body := text.substr(1) if text.begins_with("-") else text
	if body.is_empty():
		return 0.0
	if not body.substr(0, 1).is_valid_float(): # the original drops a non-numeric head
		body = body.substr(1)
	if not body.contains("-"):
		return 0.0
	var parts := body.split("-")
	if parts.size() < 2 or not parts[1].is_valid_float():
		return 0.0
	var count: float = rand_f(parts[0].to_float() * sign_mult, parts[1].to_float())
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
