class_name GenericOpenAICompatibleModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_MODEL := "custom"
const WORKER_DEFAULT_MODEL := "ai-town-worker-default"
const WORKER_SLOT_PREFIX := "ai-town-worker-slot-"
const WORKER_SLOT_COUNT := 8
const MODEL_DESCRIPTORS := [
	{
		"id": DEFAULT_MODEL,
		"label": "自定义模型 / Worker 默认",
		"input_modalities": ["text"],
		"runtime_modalities_configurable": true,
	},
	{
		"id": WORKER_DEFAULT_MODEL,
		"label": "硅基流动 · 默认模型",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-1",
		"label": "硅基流动 · 模型槽 1",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-2",
		"label": "硅基流动 · 模型槽 2",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-3",
		"label": "硅基流动 · 模型槽 3",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-4",
		"label": "硅基流动 · 模型槽 4",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-5",
		"label": "硅基流动 · 模型槽 5",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-6",
		"label": "硅基流动 · 模型槽 6",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-7",
		"label": "硅基流动 · 模型槽 7",
		"input_modalities": ["text"],
	},
	{
		"id": "ai-town-worker-slot-8",
		"label": "硅基流动 · 模型槽 8",
		"input_modalities": ["text"],
	},
]


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "openai-compatible"


func _provider_label() -> String:
	return "OpenAI Compatible"


func _transport_label() -> String:
	return "通用 OpenAI-compatible API"


func _default_endpoint() -> String:
	return OS.get_environment("OPENAI_COMPATIBLE_ENDPOINT").strip_edges()


func _default_model() -> String:
	return DEFAULT_MODEL


func _build_request_body(model_request: Dictionary) -> Dictionary:
	if _is_ai_town_worker_endpoint():
		return {
			"model": _api_model(),
			"messages": model_request["messages"],
			"request_kind": (
				"health_probe"
				if _is_health_probe_request(model_request)
				else String(model_request.get("request_kind", "resident_decision"))
			),
			"initialization": (model_request.get("initialization", {}) as Dictionary).duplicate(true),
			"wake_packet": (model_request.get("wake_packet", {}) as Dictionary).duplicate(true),
			"derived_constraints": (model_request.get("derived_constraints", {}) as Dictionary).duplicate(true),
			"max_tokens": int(model_request.get("max_tokens", 1024)),
		}
	var body := super._build_request_body(model_request)
	body["model"] = _api_model()
	body.erase("max_tokens")
	return body


func validate_configuration() -> Array[String]:
	var endpoint := String(_config.get("endpoint", _default_endpoint())).strip_edges()
	var errors: Array[String] = []
	if endpoint.is_empty():
		errors.append("缺少 OpenAI-compatible endpoint")
		return errors
	if _is_ai_town_worker_endpoint_value(endpoint):
		return errors
	errors.append_array(super.validate_configuration())
	if _api_model().is_empty():
		errors.append("缺少 OpenAI-compatible api_model")
	return errors


func _api_model() -> String:
	var configured_api_model := String(
		_config.get("api_model", OS.get_environment("OPENAI_COMPATIBLE_MODEL"))
	).strip_edges()
	if not _is_ai_town_worker_endpoint():
		return configured_api_model
	var selected_model := String(_config.get("model", DEFAULT_MODEL)).strip_edges()
	if selected_model == WORKER_DEFAULT_MODEL:
		return WORKER_DEFAULT_MODEL
	if _is_worker_slot_model(selected_model):
		return selected_model
	return configured_api_model


func _is_worker_slot_model(model_id: String) -> bool:
	if not model_id.begins_with(WORKER_SLOT_PREFIX):
		return false
	var suffix := model_id.trim_prefix(WORKER_SLOT_PREFIX)
	if not suffix.is_valid_int():
		return false
	var slot := int(suffix)
	return slot >= 1 and slot <= WORKER_SLOT_COUNT


func _is_health_probe_request(model_request: Dictionary) -> bool:
	var messages_value: Variant = model_request.get("messages", [])
	if not messages_value is Array:
		return false
	var messages := messages_value as Array
	if messages.size() != 1 or not messages[0] is Dictionary:
		return false
	var message := messages[0] as Dictionary
	return (
		String(message.get("role", "")) == "user"
		and String(message.get("content", "")).strip_edges()
		== "Return exactly {\"ok\":true}."
	)


func _api_key_environment_names() -> Array[String]:
	return ["OPENAI_COMPATIBLE_API_KEY"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 OPENAI_COMPATIBLE_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message


func _is_ai_town_worker_endpoint() -> bool:
	return _is_ai_town_worker_endpoint_value(
		String(_config.get("endpoint", _default_endpoint())).strip_edges()
	)


func _is_ai_town_worker_endpoint_value(endpoint: String) -> bool:
	var normalized := endpoint.trim_suffix("/")
	return normalized.ends_with("/api/agent")
