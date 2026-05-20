extends Node

signal progress_updated(message: String)
signal generation_completed
signal generation_failed(error: String)

var _thread: Thread
var _status_file: String
var _poll_timer: Timer


func generate(reference_image_path: String = "", seed: int = -1) -> void:
	_status_file = OS.get_user_data_dir() + "/gen_status.txt"

	if FileAccess.file_exists(_status_file):
		DirAccess.remove_absolute(_status_file)

	# Extract script on the main thread (res:// reads can fail inside threads)
	var script_path := _extract_script()

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_poll_status)
	add_child(_poll_timer)
	_poll_timer.start()

	_thread = Thread.new()
	_thread.start(_run_generation.bind(reference_image_path, seed, script_path))


func _run_generation(reference_image_path: String, seed: int, script: String) -> void:
	var python := _find_python()
	if python.is_empty():
		call_deferred("_on_failed", "Python 3을 찾을 수 없어요.\npython.org에서 설치 후 재시작해주세요.")
		return
	var out_dir := OS.get_user_data_dir() + "/sprites"
	var hf_token := _load_token()

	var args := [script,
		"--output",  out_dir,
		"--status-file", _status_file,
	]
	if not hf_token.is_empty():
		args.append_array(["--hf-token", hf_token])
	if not reference_image_path.is_empty():
		args.append_array(["--reference-image", reference_image_path])
	if seed >= 0:
		args.append_array(["--seed", str(seed)])

	var output: Array = []
	var exit_code := OS.execute(python, args, output)

	if exit_code == 0:
		call_deferred("_on_completed")
	else:
		var detail := "\n".join(output).strip_edges()
		call_deferred("_on_failed", "스프라이트 생성에 실패했어요. (exit %d)\n%s" % [exit_code, detail])


func _load_token() -> String:
	const TOKEN_PATH = "user://hf_token.txt"
	if FileAccess.file_exists(TOKEN_PATH):
		var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
		if f:
			return f.get_as_text().strip_edges()
	return OS.get_environment("HF_TOKEN")

func _extract_script() -> String:
	var dest := OS.get_user_data_dir() + "/generate_sprites.py"
	# In editor: res:// globalizes to an absolute filesystem path
	var globalized := ProjectSettings.globalize_path("res://sprite_gen/generate_sprites.py")
	if globalized.is_absolute_path() and FileAccess.file_exists(globalized):
		return globalized
	# In exported .app: extract from PCK to user data dir
	var src := FileAccess.open("res://sprite_gen/generate_sprites.py", FileAccess.READ)
	if not src:
		return dest
	var data := src.get_buffer(src.get_length())
	src = null
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if not dst:
		return dest
	dst.store_buffer(data)
	dst = null
	return dest

func _find_python() -> String:
	# Build candidate venv paths: res://-based (editor) + relative to .app bundle
	var candidates: Array[String] = []
	candidates.append(ProjectSettings.globalize_path("res://sprite_gen/.venv/bin/python3"))
	candidates.append(ProjectSettings.globalize_path("res://sprite_gen/.venv/bin/python"))

	# Walk up from executable to find project root (handles both editor and exported .app)
	var exe_dir := OS.get_executable_path().get_base_dir()
	var d := exe_dir
	for _i in 6:
		d = d.get_base_dir()
		candidates.append(d + "/sprite_gen/.venv/bin/python3")
		candidates.append(d + "/sprite_gen/.venv/bin/python")

	# Verify each candidate by actually executing it (FileAccess can't follow symlinks)
	for c in candidates:
		var out: Array = []
		if OS.execute(c, ["--version"], out) == 0:
			return c

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
