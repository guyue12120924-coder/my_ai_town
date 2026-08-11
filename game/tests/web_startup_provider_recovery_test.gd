extends SceneTree


const PROVIDER_CONFIG_STORE := preload(
	"res://world/presentation/ui/TownProviderConfigStore.gd"
)
const PROVIDER_SETTINGS_SERVICE := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const STARTUP_SAVE_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
)
const PROVIDER_PATH := "user://tests/web_provider_recovery/provider.json"
const PROFILE_PATH := "user://tests/town_startup_profile/web-recovery.json"


class EmptySaveStore:
	extends RefCounted

	func list_published(_slot_id: String) -> Dictionary:
		return {"ok": true, "manifests": [], "invalid": []}

	func list_incomplete(_slot_id: String) -> Dictionary:
		return {"ok": true, "records": []}

	func read_reference(_reference: Dictionary) -> Dictionary:
		return {"ok": false, "errorCode": "SESSION_SAVE_REFERENCE_NOT_FOUND"}


class LegacyBrokenSaveStore:
	extends EmptySaveStore

	func list_incomplete(slot_id: String) -> Dictionary:
		if slot_id == "town-main":
			return {
				"ok": false,
				"errorCode": "SESSION_SAVE_JOURNAL_STATE_INVALID",
				"retryable": false,
			}
		return super.list_incomplete(slot_id)


var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("AI_TOWN_PROVIDER_TEST_NO_NETWORK", "1")
	_test_worker_managed_provider_without_local_key()
	_test_legacy_provider_selection_migrates_to_worker()
	_test_invalid_profile_does_not_block_empty_slot()
	_test_legacy_broken_slot_does_not_block_other_empty_slot()
	_finish()


func _test_worker_managed_provider_without_local_key() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PROVIDER_PATH.get_base_dir()),
	)
	var store: RefCounted = PROVIDER_CONFIG_STORE.new()
	_expect_ok(store.call("configure", PROVIDER_PATH), "配置 Provider 测试存储")
	_expect_ok(store.call("save_config", {
		"schemaVersion": 1,
		"selectedProviderId": "openai-compatible",
		"selectedModelByProvider": {
			"openai-compatible": "ai-town-worker-default",
		},
		"providers": {
			"openai-compatible": {
				"enabled": true,
				"endpoint": "https://town.example/api/agent",
			},
		},
	}), "保存 Worker 托管配置")
	var settings: RefCounted = PROVIDER_SETTINGS_SERVICE.new()
	_expect_ok(settings.call("configure_store", PROVIDER_PATH), "加载 Worker 托管配置")
	var provider: RefCounted = PROVIDER_SERVICE.new()
	_expect_ok(settings.call("bind_provider_service", provider, root), "绑定 Provider 服务")
	var view_model := settings.call("get_view_model") as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var providers := data.get("providers", []) as Array
	_expect(providers.size() > 0, "Worker 托管配置必须渲染 Provider，而不是空白页")
	var worker_provider: Dictionary = {}
	for provider_value: Variant in providers:
		if String((provider_value as Dictionary).get("providerId", "")) == "openai-compatible":
			worker_provider = provider_value as Dictionary
			break
	_expect(not worker_provider.is_empty(), "Provider 目录必须包含 OpenAI Compatible")
	if not worker_provider.is_empty():
		var key := worker_provider.get("key", {}) as Dictionary
		_expect(String(key.get("status", "")) == "managed", "Worker 凭据应显示为服务器托管")
		_expect(String(key.get("errorCode", "")).is_empty(), "Worker 托管凭据不应要求本地 API Key")


func _test_invalid_profile_does_not_block_empty_slot() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PROFILE_PATH.get_base_dir()),
	)
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("{obsolete-profile")
		file = null
	var catalog: RefCounted = STARTUP_SAVE_CATALOG.new()
	_expect_ok(catalog.call("configure", EmptySaveStore.new(), PROFILE_PATH), "配置启动存档目录")
	var result := catalog.call("get_catalog", [
		{"slotId": "town-main", "displayName": "小镇 1"},
		{"slotId": "town-2", "displayName": "小镇 2"},
	]) as Dictionary
	_expect_ok(result, "无效的旧启动资料不应阻塞存档目录：%s" % result)
	_expect(
		String(result.get("firstEmptySlotId", "")) == "town-main",
		"新游戏仍应获得空存档位：%s" % result,
	)


func _test_legacy_provider_selection_migrates_to_worker() -> void:
	var legacy_path := "user://tests/web_provider_recovery/legacy-provider.json"
	var store: RefCounted = PROVIDER_CONFIG_STORE.new()
	_expect_ok(store.call("configure", legacy_path), "配置旧 Provider 测试存储")
	_expect_ok(store.call("save_config", {
		"schemaVersion": 1,
		"selectedProviderId": "alibaba-bailian",
		"selectedModelByProvider": {
			"alibaba-bailian": "qwen3.5-plus",
		},
		"providers": {
			"alibaba-bailian": {"enabled": true, "endpoint": ""},
		},
	}), "保存旧 Provider 配置")
	var settings: RefCounted = PROVIDER_SETTINGS_SERVICE.new()
	_expect_ok(settings.call("configure_store", legacy_path), "加载旧 Provider 配置")
	_expect_ok(settings.call(
		"_merge_web_worker_defaults",
		"https://town.example/api/agent",
	), "迁移旧 Provider 配置")
	var runtime := settings.call("load_saved_runtime_configuration") as Dictionary
	_expect(
		String(runtime.get("providerId", "")) == "openai-compatible",
		"无可用凭据的旧选择应自动切换到硅基流动 Worker",
	)
	_expect(
		String(runtime.get("modelId", "")) == "ai-town-worker-default",
		"迁移后应自动选择硅基流动默认模型",
	)


func _test_legacy_broken_slot_does_not_block_other_empty_slot() -> void:
	var catalog: RefCounted = STARTUP_SAVE_CATALOG.new()
	_expect_ok(catalog.call(
		"configure",
		LegacyBrokenSaveStore.new(),
		"user://tests/town_startup_profile/legacy-broken-slot.json",
	), "配置旧损坏槽位目录")
	var result := catalog.call("get_catalog", [
		{"slotId": "town-main", "displayName": "小镇 1"},
		{"slotId": "town-2", "displayName": "小镇 2"},
		{"slotId": "town-3", "displayName": "小镇 3"},
	]) as Dictionary
	_expect_ok(result, "单个旧损坏槽位不应阻塞整个启动目录")
	_expect(
		String(result.get("firstEmptySlotId", "")) == "town-2",
		"新游戏应跳过旧损坏槽位并使用下一个空槽",
	)


func _expect_ok(value: Variant, message: String) -> void:
	_expect(value is Dictionary and bool((value as Dictionary).get("ok", false)), message)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WEB_STARTUP_PROVIDER_RECOVERY_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	push_error("WEB_STARTUP_PROVIDER_RECOVERY_FAILED checks=%d" % _checks)
	quit(1)
