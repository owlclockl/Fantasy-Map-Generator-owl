class_name HeightmapTemplates
extends RefCounted
## The heightmap templates of the original generator (data/heightmap-templates.ts).
## Each template is a script of heightmap tool steps.

const VOLCANO := """Hill 1 90-100 44-56 40-60
Multiply 0.8 50-100 0 0
Range 1.5 30-55 45-55 40-60
Smooth 3 0 0 0
Hill 1.5 35-45 25-30 20-75
Hill 1 35-55 75-80 25-75
Hill 0.5 20-25 10-15 20-25
Mask 3 0 0 0"""

const HIGH_ISLAND := """Hill 1 90-100 65-75 47-53
Add 7 all 0 0
Hill 5-6 20-30 25-55 45-55
Range 1 40-50 45-55 45-55
Multiply 0.8 land 0 0
Mask 3 0 0 0
Smooth 2 0 0 0
Trough 2-3 20-30 20-30 20-30
Trough 2-3 20-30 60-80 70-80
Hill 1 10-15 60-60 50-50
Hill 1.5 13-16 15-20 20-75
Range 1.5 30-40 15-85 30-40
Range 1.5 30-40 15-85 60-70
Pit 3-5 10-30 15-85 20-80"""

const LOW_ISLAND := """Hill 1 90-99 60-80 45-55
Hill 1-2 20-30 10-30 10-90
Smooth 2 0 0 0
Hill 6-7 25-35 20-70 30-70
Range 1 40-50 45-55 45-55
Trough 2-3 20-30 15-85 20-30
Trough 2-3 20-30 15-85 70-80
Hill 1.5 10-15 5-15 20-80
Hill 1 10-15 85-95 70-80
Pit 5-7 15-25 15-85 20-80
Multiply 0.4 20-100 0 0
Mask 4 0 0 0"""

const CONTINENTS := """Hill 1 80-85 60-80 40-60
Hill 1 80-85 20-30 40-60
Hill 6-7 15-30 25-75 15-85
Multiply 0.6 land 0 0
Hill 8-10 5-10 15-85 20-80
Range 1-2 30-60 5-15 25-75
Range 1-2 30-60 80-95 25-75
Range 0-3 30-60 80-90 20-80
Strait 2 vertical 0 0
Strait 1 vertical 0 0
Smooth 3 0 0 0
Trough 3-4 15-20 15-85 20-80
Trough 3-4 5-10 45-55 45-55
Pit 3-4 10-20 15-85 20-80
Mask 4 0 0 0"""

const ARCHIPELAGO := """Add 11 all 0 0
Range 2-3 40-60 20-80 20-80
Hill 5 15-20 10-90 30-70
Hill 2 10-15 10-30 20-80
Hill 2 10-15 60-90 20-80
Smooth 3 0 0 0
Trough 10 20-30 5-95 5-95
Strait 2 vertical 0 0
Strait 2 horizontal 0 0"""

const ATOLL := """Hill 1 75-80 50-60 45-55
Hill 1.5 30-50 25-75 30-70
Hill .5 30-50 25-35 30-70
Smooth 1 0 0 0
Multiply 0.2 25-100 0 0
Hill 0.5 10-20 50-55 48-52"""

const MEDITERRANEAN := """Range 4-6 30-80 0-100 0-10
Range 4-6 30-80 0-100 90-100
Hill 6-8 30-50 10-90 0-5
Hill 6-8 30-50 10-90 95-100
Multiply 0.9 land 0 0
Mask -2 0 0 0
Smooth 1 0 0 0
Hill 2-3 30-70 0-5 20-80
Hill 2-3 30-70 95-100 20-80
Trough 3-6 40-50 0-100 0-10
Trough 3-6 40-50 0-100 90-100"""

const PENINSULA := """Range 2-3 20-35 40-50 0-15
Add 5 all 0 0
Hill 1 90-100 10-90 0-5
Add 13 all 0 0
Hill 3-4 3-5 5-95 80-100
Hill 1-2 3-5 5-95 40-60
Trough 5-6 10-25 5-95 5-95
Smooth 3 0 0 0
Invert 0.4 both 0 0"""

const PANGEA := """Hill 1-2 25-40 15-50 0-10
Hill 1-2 5-40 50-85 0-10
Hill 1-2 25-40 50-85 90-100
Hill 1-2 5-40 15-50 90-100
Hill 8-12 20-40 20-80 48-52
Smooth 2 0 0 0
Multiply 0.7 land 0 0
Trough 3-4 25-35 5-95 10-20
Trough 3-4 25-35 5-95 80-90
Range 5-6 30-40 10-90 35-65"""

const ISTHMUS := """Hill 5-10 15-30 0-30 0-20
Hill 5-10 15-30 10-50 20-40
Hill 5-10 15-30 30-70 40-60
Hill 5-10 15-30 50-90 60-80
Hill 5-10 15-30 70-100 80-100
Smooth 2 0 0 0
Trough 4-8 15-30 0-30 0-20
Trough 4-8 15-30 10-50 20-40
Trough 4-8 15-30 30-70 40-60
Trough 4-8 15-30 50-90 60-80
Trough 4-8 15-30 70-100 80-100
Invert 0.25 x 0 0"""

const SHATTERED := """Hill 8 35-40 15-85 30-70
Trough 10-20 40-50 5-95 5-95
Range 5-7 30-40 10-90 20-80
Pit 12-20 30-40 15-85 20-80"""

const TAKLAMAKAN := """Hill 1-3 20-30 30-70 30-70
Hill 2-4 60-85 0-5 0-100
Hill 2-4 60-85 95-100 0-100
Hill 3-4 60-85 20-80 0-5
Hill 3-4 60-85 20-80 95-100
Smooth 3 0 0 0"""

const OLD_WORLD := """Range 3 70 15-85 20-80
Hill 2-3 50-70 15-45 20-80
Hill 2-3 50-70 65-85 20-80
Hill 4-6 20-25 15-85 20-80
Multiply 0.5 land 0 0
Smooth 2 0 0 0
Range 3-4 20-50 15-35 20-45
Range 2-4 20-50 65-85 45-80
Strait 3-7 vertical 0 0
Trough 6-8 20-50 15-85 45-65
Pit 5-6 20-30 10-90 10-90"""

const FRACTIOUS := """Hill 12-15 50-80 5-95 5-95
Mask -1.5 0 0 0
Mask 3 0 0 0
Add -20 30-100 0 0
Range 6-8 40-50 5-95 10-90"""

const TEMPLATES := {
	"volcano": {"id": 0, "name": "Volcano", "probability": 3, "template": VOLCANO},
	"highIsland": {"id": 1, "name": "High Island", "probability": 19, "template": HIGH_ISLAND},
	"lowIsland": {"id": 2, "name": "Low Island", "probability": 9, "template": LOW_ISLAND},
	"continents": {"id": 3, "name": "Continents", "probability": 16, "template": CONTINENTS},
	"archipelago": {"id": 4, "name": "Archipelago", "probability": 18, "template": ARCHIPELAGO},
	"atoll": {"id": 5, "name": "Atoll", "probability": 1, "template": ATOLL},
	"mediterranean": {"id": 6, "name": "Mediterranean", "probability": 5, "template": MEDITERRANEAN},
	"peninsula": {"id": 7, "name": "Peninsula", "probability": 3, "template": PENINSULA},
	"pangea": {"id": 8, "name": "Pangea", "probability": 5, "template": PANGEA},
	"isthmus": {"id": 9, "name": "Isthmus", "probability": 2, "template": ISTHMUS},
	"shattered": {"id": 10, "name": "Shattered", "probability": 7, "template": SHATTERED},
	"taklamakan": {"id": 11, "name": "Taklamakan", "probability": 1, "template": TAKLAMAKAN},
	"oldWorld": {"id": 12, "name": "Old World", "probability": 8, "template": OLD_WORLD},
	"fractious": {"id": 13, "name": "Fractious", "probability": 3, "template": FRACTIOUS}
}


static func get_template(id: String) -> String:
	if TEMPLATES.has(id):
		return TEMPLATES[id]["template"]
	push_warning("Unknown heightmap template: " + id)
	return VOLCANO


static func template_name(id: String) -> String:
	if TEMPLATES.has(id):
		return TEMPLATES[id]["name"]
	return id
