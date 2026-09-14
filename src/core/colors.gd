class_name FmgColors
extends RefCounted
## Color helpers ported from colorUtils.ts (d3 rainbow replaced by
## golden-angle hue cycling which gives similarly distinct results).

const C_12: Array = [
	"#dababf", "#fb8072", "#80b1d3", "#fdb462", "#b3de69", "#fccde5",
	"#c6b9c1", "#bc80bd", "#ccebc5", "#ffed6f", "#8dd3c7", "#eb8de7"
]


static func hsv_to_hex(h: float, s: float, v: float) -> String:
	var c := Color.from_hsv(fposmod(h, 1.0), s, v)
	return "#%02x%02x%02x" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]


## array of `count` distinct colors: the 12 pastels first, then hue-cycled colors
static func get_colors(count: int, rng: FmgRng = null) -> Array:
	var out: Array = []
	for i: int in count:
		if i < 12:
			out.append(C_12[i])
		else:
			var t: float = float(i - 12) / float(maxi(count - 12, 1))
			out.append(hsv_to_hex(fmod(t * 0.85 + 0.05, 1.0), 0.45, 0.75))
	if rng != null:
		# seeded Fisher-Yates shuffle like the original shuffler()
		for i: int in range(out.size() - 1, 0, -1):
			var j: int = rng.rand(i)
			var tmp: String = out[i]
			out[i] = out[j]
			out[j] = tmp
	return out


static func get_random_color(rng: FmgRng) -> String:
	return hsv_to_hex(rng.random(), 0.55, 0.8)


## blend a color with a random one, then brighten (getMixedColor)
static func get_mixed_color(color_to_mix: String, rng: FmgRng, mix: float = 0.2, bright: float = 0.3) -> String:
	var base := Color.html(color_to_mix) if color_to_mix.begins_with("#") else Color.html(get_random_color(rng))
	var other := Color.html(get_random_color(rng))
	var mixed := base.lerp(other, mix)
	mixed = mixed.lightened(bright * 0.5)
	return "#%02x%02x%02x" % [int(round(mixed.r * 255.0)), int(round(mixed.g * 255.0)), int(round(mixed.b * 255.0))]
