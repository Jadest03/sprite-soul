extends RefCounted

var energy: float = 1.0
var boredom: float = 0.0

const DECAY_RATE = {
	"energy":  -0.002,
	"boredom":  0.001,
}
const SLEEP_RECOVERY = 0.004  # 잠자는 동안 초당 에너지 회복량

func tick(delta: float, sleeping: bool = false) -> void:
	var energy_rate: float = SLEEP_RECOVERY if sleeping else DECAY_RATE["energy"]
	energy  = clampf(energy  + energy_rate * delta, 0.0, 1.0)
	boredom = clampf(boredom + DECAY_RATE["boredom"] * delta, 0.0, 1.0)

func on_click() -> void:
	energy = minf(1.0, energy + 0.1)

func wake_up() -> void:
	energy = maxf(energy, 0.5)

func is_sleepy() -> bool:
	return energy < 0.2

func is_bored() -> bool:
	return boredom > 0.7

