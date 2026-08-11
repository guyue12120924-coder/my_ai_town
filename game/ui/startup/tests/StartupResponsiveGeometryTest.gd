extends SceneTree


const STARTUP_SCENE := preload("res://ui/startup/StartupScreen.tscn")
const REFERENCE_VIEWPORT := Vector2(1920.0, 1080.0)
const MAIN_MENU_SCALE := 0.86
const MAIN_MENU_PIVOT := Vector2(960.0, 570.0)
const VIEWPORT_CASES: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1536, 730),
	Vector2i(1365, 650),
	Vector2i(1280, 720),
]
const CONTROL_NAMES: Array[String] = [
	"StartupTitle",
	"StartupMenuShell",
	"StartupSaveSummaryPlaque",
	"SaveSummary",
	"ContinueGameButton",
	"NewGameButton",
	"LoadGameButton",
	"ConnectionSettingsButton",
	"GameSettingsButton",
	"ExitGameButton",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var checks := 0
	for viewport_size: Vector2i in VIEWPORT_CASES:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		root.add_child(viewport)
		var startup := STARTUP_SCENE.instantiate() as Control
		viewport.add_child(startup)
		await process_frame
		await process_frame
		checks += _expect(
			startup.size.is_equal_approx(Vector2(viewport_size)),
			"启动页未填满 viewport=%s actual=%s" % [viewport_size, startup.size],
			failures,
		)
		var layout_scale := maxf(
			minf(
				float(viewport_size.x) / REFERENCE_VIEWPORT.x,
				float(viewport_size.y) / REFERENCE_VIEWPORT.y,
			),
			0.5,
		)
		var canvas_offset := (
			Vector2(viewport_size) - REFERENCE_VIEWPORT * layout_scale
		) * 0.5
		for control_name: String in CONTROL_NAMES:
			var control := startup.get_node_or_null(control_name) as Control
			checks += _expect(
				control != null,
				"缺少启动控件：%s" % control_name,
				failures,
			)
			if control == null:
				continue
			var reference_rect := control.get_meta("startup_reference_rect") as Rect2
			var visual_rect := Rect2(
				MAIN_MENU_PIVOT + (
					reference_rect.position - MAIN_MENU_PIVOT
				) * MAIN_MENU_SCALE,
				reference_rect.size * MAIN_MENU_SCALE,
			)
			var expected := Rect2(
				canvas_offset + visual_rect.position * layout_scale,
				visual_rect.size * layout_scale,
			)
			checks += _expect(
				control.scale.is_equal_approx(Vector2.ONE),
				"%s viewport=%s 仍使用 Control.scale=%s"
				% [control_name, viewport_size, control.scale],
				failures,
			)
			checks += _expect(
				control.get_rect().is_equal_approx(expected),
				"%s viewport=%s 矩形被 Theme 最小尺寸改写：expected=%s actual=%s"
				% [control_name, viewport_size, expected, control.get_rect()],
				failures,
			)
		checks += _expect_button_gaps(startup, viewport_size, failures)
		viewport.queue_free()
		await process_frame
	_finish(failures, checks)


func _expect_button_gaps(
	startup: Control,
	viewport_size: Vector2i,
	failures: Array[String],
) -> int:
	var checks := 0
	var vertical_names: Array[String] = [
		"ContinueGameButton",
		"NewGameButton",
		"LoadGameButton",
		"ConnectionSettingsButton",
		"ExitGameButton",
	]
	for index: int in range(vertical_names.size() - 1):
		var current := startup.get_node(vertical_names[index]) as Control
		var following := startup.get_node(vertical_names[index + 1]) as Control
		checks += _expect(
			current.get_rect().end.y <= following.get_rect().position.y + 0.01,
			"viewport=%s 按钮命中框重叠：%s 与 %s"
			% [viewport_size, current.name, following.name],
			failures,
		)
	var left := startup.get_node("ConnectionSettingsButton") as Control
	var right := startup.get_node("GameSettingsButton") as Control
	checks += _expect(
		left.get_rect().end.x <= right.get_rect().position.x + 0.01,
		"viewport=%s 设置按钮命中框横向重叠" % viewport_size,
		failures,
	)
	return checks


func _expect(condition: bool, message: String, failures: Array[String]) -> int:
	if not condition:
		failures.append(message)
	return 1


func _finish(failures: Array[String], checks: int) -> void:
	if failures.is_empty():
		print("STARTUP_RESPONSIVE_GEOMETRY_PASS checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"STARTUP_RESPONSIVE_GEOMETRY_FAILED checks=%d failures=%d"
		% [checks, failures.size()]
	)
	quit(1)
