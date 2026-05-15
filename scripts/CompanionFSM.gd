extends Node

enum State {
	IDLE,
	WALK,
	SLEEP,
	REACT,
}

var current_state: int = State.IDLE
var _time_in_state: float = 0.0

signal state_entered(state: int)
signal state_exited(state: int)

func _ready() -> void:
	_enter_state(State.IDLE)

func transition_to(new_state: int) -> void:
	if new_state == current_state:
		return
	_exit_state(current_state)
	_enter_state(new_state)

func tick(delta: float) -> void:
	_time_in_state += delta

func time_in_state() -> float:
	return _time_in_state

func _enter_state(state: int) -> void:
	current_state = state
	_time_in_state = 0.0
	state_entered.emit(state)

func _exit_state(state: int) -> void:
	state_exited.emit(state)
