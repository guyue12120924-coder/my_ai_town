class_name GenericOpenAICompatibleModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_MODEL := "custom"
const MODEL_DESCRIPTORS := [
	{
		"id": DEFAULT_MODEL,
		"label": "自定义模型",
		"input_modalities": ["text"],
		"runtime_modalities_configurable": true,
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
			"request_kind": String(model_request.get("request_kind", "resident_decision")),
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
	return String(
		_config.get("api_model", OS.get_environment("OPENAI_COMPATIBLE_MODEL"))
	).strip_edges()


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
