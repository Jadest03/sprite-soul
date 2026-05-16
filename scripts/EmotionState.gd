extends RefCounted

var energy: float = 1.0
var boredom: float = 0.0
var affection: float = 0.5
var attention: float = 0.0

const DECAY_RATE = {
	"energy":    -0.002,
	"boredom":    0.001,
	"affection": -0.0001,
	"attention": -0.05,
}

func tick(delta: float) -> void:
	energy    = clampf(energy    + DECAY_RATE["energy"]    * delta, 0.0, 1.0)
	boredom   = clampf(boredom   + DECAY_RATE["boredom"]   * delta, 0.0, 1.0)
	affection = clampf(affection + DECAY_RATE["affection"] * delta, 0.0, 1.0)
	attention = clampf(attention + DECAY_RATE["attention"] * delta, 0.0, 1.0)

func on_interaction() -> void:
	attention = 1.0
	boredom   = maxf(0.0, boredom - 0.2)
	affection = minf(1.0, affection + 0.05)

func on_click() -> void:
	attention = 1.0
	energy    = minf(1.0, energy + 0.1)

func wake_up() -> void:
	energy    = maxf(energy, 0.5)
	attention = 1.0

func is_sleepy() -> bool:
	return energy < 0.2

func is_bored() -> bool:
	return boredom > 0.7

func is_attentive() -> bool:
	return attention > 0.3
