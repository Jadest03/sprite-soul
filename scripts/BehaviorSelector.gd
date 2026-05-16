extends Node

const CompanionFSM = preload("res://scripts/CompanionFSM.gd")

const MIN_IDLE_DURATION = 3.0
const MIN_WALK_DURATION = 4.0
const MIN_SLEEP_DURATION = 8.0

func select(fsm, emotion, _mouse_near: bool) -> int:
	var current: int = fsm.current_state
	var t: float = fsm.time_in_state()

	if emotion.is_sleepy():
		if current != CompanionFSM.State.SLEEP:
			return CompanionFSM.State.SLEEP
		return current

	if current == CompanionFSM.State.SLEEP:
		if emotion.energy > 0.6 and t > MIN_SLEEP_DURATION:
			return CompanionFSM.State.IDLE
		return current

	if current == CompanionFSM.State.IDLE and t > MIN_IDLE_DURATION:
		if emotion.is_bored() or randf() < 0.002:
			return CompanionFSM.State.WALK

	if current == CompanionFSM.State.WALK and t > MIN_WALK_DURATION:
		if randf() < 0.01:
			return CompanionFSM.State.IDLE

	return current
