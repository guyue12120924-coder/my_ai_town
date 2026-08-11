extends SceneTree


const SERVICE := preload(
	"res://world/presentation/ui/TownAudioDisplaySettingsService.gd"
)
const SETTINGS_PATH := "user://web_window_geometry_guard_test.json"


class FakeWebDisplayBackend:
	extends RefCounted

	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	var size := Vector2i(2048, 1128)
	var position := Vector2i.ZERO
	var mode_set_count := 0
	var size_set_count := 0
	var position_set_count := 0

	func get_name() -> String:
		return "Web"

	func window_get_mode() -> int:
		return mode

	func window_set_mode(value: int) -> void:
		mode_set_count += 1
		mode = value

	func window_get_size() -> Vector2i:
		return size

	func window_set_size(value: Vector2i) -> void:
		size_set_count += 1
		size = value

	func window_get_position() -> Vector2i:
		return position

	func window_set_position(value: Vector2i) -> void:
		position_set_count += 1
		position = value

	func window_get_current_screen() -> int:
		return 0

	func screen_get_usable_rect(_screen: int) -> Rect2i:
		return Rect2i(Vector2i.ZERO, size)


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_settings_file()
	var backend := FakeWebDisplayBackend.new()
	var service := SERVICE.new()
	service.settings_path = SETTINGS_PATH
	var configured := service.call(
		"configure_display_backend_for_tests",
		backend,
	) as Dictionary
	_expect(bool(configured.get("ok", false)), "fake Web backend is accepted")
	root.add_child(service)
	await process_frame
	await process_frame

	_expect(bool(service.call("_is_web_runtime")), "Web runtime is detected")
	_expect(
		not bool(service.call("_display_changes_available")),
		"browser-owned window geometry is not exposed as mutable",
	)
	_expect_equal(backend.mode_set_count, 0, "startup does not change Web window mode")
	_expect_equal(backend.size_set_count, 0, "startup does not force Web to 1920x1080")
	_expect_equal(
		backend.position_set_count,
		0,
		"startup does not reposition the browser viewport",
	)

	var result := service.call("_apply_display_draft", {
		"windowModeId": "windowed",
		"windowedResolutionId": "1920x1080",
		"uiScalePercent": 100,
		"reducedFlashingEnabled": false,
	}) as Dictionary
	_expect(bool(result.get("ok", false)), "non-window Web settings still apply")
	_expect_equal(backend.mode_set_count, 0, "Web apply leaves window mode untouched")
	_expect_equal(backend.size_set_count, 0, "Web apply leaves canvas size adaptive")
	_expect_equal(
		service.get("_pending_windowed_geometry"),
		{},
		"Web apply never schedules desktop geometry retries",
	)

	service.queue_free()
	await process_frame
	_remove_settings_file()
	if _failures.is_empty():
		print("WEB_WINDOW_GEOMETRY_GUARD_PASS checks=11")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s expected=%s actual=%s" % [message, expected, actual])


func _remove_settings_file() -> void:
	var absolute := ProjectSettings.globalize_path(SETTINGS_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
