extends Node

signal progress_updated(message: String)
signal generation_completed
signal generation_failed(error: String)

var _thread: Thread
var _status_file: String
var _poll_timer: Timer


func generate(character: String, reference_image_path: String = "") -> void:
	_status_file = OS.get_user_data_dir() + "/gen_status.txt"

	if FileAccess.file_exists(_status_file):
		DirAccess.remove_absolute(_status_file)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_poll_status)
	add_child(_poll_timer)
	_poll_timer.start()

	_thread = Thread.new()
	_thread.start(_run_generation.bind(character, reference_image_path))


func _run_generation(character: String, reference_image_path: String) -> void:
	var python := _find_python()
	if python.is_empty():
		call_deferred("_on_failed", "Python 3을 찾을 수 없어요.\npython.org에서 설치 후 재시작해주세요.")
		return

	var script := ProjectSettings.globalize_path("res://sprite_gen/generate_sprites.py")
	var out_dir := OS.get_user_data_dir() + "/sprites"
	var hf_token := _load_token()

	var args := [script,
		"--character", character,
		"--output",    out_dir,
		"--status-file", _status_file,
	]
	if not hf_token.is_empty():
		args.append_array(["--hf-token", hf_token])
	if not reference_image_path.is_empty():
		args.append_array(["--reference-image", reference_image_path])

	var exit_code := OS.execute(python, args)

	if exit_code == 0:
		call_deferred("_on_completed")
	else:
		call_deferred("_on_failed", "스프라이트 생성에 실패했어요. (exit %d)" % exit_code)


func _load_token() -> String:
	const TOKEN_PATH = "user://hf_token.txt"
	if FileAccess.file_exists(TOKEN_PATH):
		var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
		if f:
			return f.get_as_text().strip_edges()
	return OS.get_environment("HF_TOKEN")

func _find_python() -> String:
	var venv := ProjectSettings.globalize_path("res://sprite_gen/.venv/bin/python")
	if FileAccess.file_exists(venv):
		return venv
	for cmd in ["python3", "python"]:
		var out: Array = []
		if OS.execute(cmd, ["--version"], out) == 0:
			return cmd
	return ""


func _poll_status() -> void:
	if not FileAccess.file_exists(_status_file):
		return
	var f := FileAccess.open(_status_file, FileAccess.READ)
	if not f:
		return
	var line := f.get_as_text().strip_edges()
	f.close()

	if line.begins_with("STATUS:"):
		progress_updated.emit(line.substr(7))
	elif line == "DONE":
		_poll_timer.stop()


func _on_completed() -> void:
	_cleanup()
	generation_completed.emit()


func _on_failed(error: String) -> void:
	_cleanup()
	generation_failed.emit(error)


func _cleanup() -> void:
	if _poll_timer and is_instance_valid(_poll_timer):
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
