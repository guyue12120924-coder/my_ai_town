import { buildCreativeContextMessage } from "../../vendor/unlimited-ai-first/src/context.js";

const DEFAULT_SILICONFLOW_CHAT_URL = "https://api.siliconflow.cn/v1/chat/completions";
const UPSTREAM_UNLIMITED_AI_COMMIT = "64409d7ad930e7ff5948f2c15764c440741d01ae";
const WORKER_DEFAULT_MODEL = "ai-town-worker-default";
const WORKER_SLOT_PREFIX = "ai-town-worker-slot-";
const WORKER_SLOT_COUNT = 8;

function jsonResponse(value, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(value, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      ...extraHeaders
    }
  });
}

function cleanText(value, limit = 6000) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > limit ? text.slice(0, limit) : text;
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function parseModelList(value) {
  const source = cleanText(value, 12000);
  if (!source) return [];
  if (source.startsWith("[")) {
    try {
      const parsed = JSON.parse(source);
      if (Array.isArray(parsed)) {
        return parsed.map((item) => cleanText(item, 300)).filter(Boolean);
      }
    } catch {}
  }
  return source
    .split(/[\n,;]/)
    .map((item) => cleanText(item, 300))
    .filter(Boolean);
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const normalized = cleanText(value, 300);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function extractTaggedSection(messages, tag) {
  const source = arrayValue(messages)
    .map((message) => typeof message?.content === "string" ? message.content : "")
    .join("\n");
  const open = `<${tag}>`;
  const close = `</${tag}>`;
  const start = source.indexOf(open);
  const end = source.indexOf(close, start + open.length);
  if (start < 0 || end <= start) return "";
  return cleanText(source.slice(start + open.length, end), 6500);
}

function renderCurrentState(wakePacket) {
  const wake = objectValue(wakePacket);
  const snapshot = objectValue(wake.snapshot);
  const state = {
    time: snapshot.time ?? wake.time ?? "",
    weather: snapshot.weather ?? "",
    weather_context: snapshot.weather_context ?? "",
    location: snapshot.location ?? snapshot.place ?? "",
    activity: snapshot.activity ?? snapshot.current_activity ?? "",
    body_state: snapshot.body_state ?? snapshot.body ?? {},
    conditions: snapshot.conditions ?? snapshot.active_needs ?? [],
    work_tasks: snapshot.work_tasks ?? [],
    social_matters: snapshot.social_matters ?? [],
    nearby_residents: snapshot.nearby_residents ?? snapshot.nearby ?? [],
    conflicts: snapshot.conflicts ?? snapshot.conflict ?? [],
    announcements: snapshot.announcements ?? [],
    recent_events: wake.events ?? [],
    action_results: wake.action_results ?? []
  };
  return cleanText(JSON.stringify(state, null, 2), 5000);
}

function buildAiTownContext(payload) {
  const initialization = objectValue(payload.initialization);
  const me = objectValue(initialization.me);
  const attributes = objectValue(me.attributes);
  const socialState = objectValue(me.social_state);
  const soulProfile = objectValue(me.soul_profile);
  const wakePacket = objectValue(payload.wake_packet);
  const derivedConstraints = objectValue(payload.derived_constraints);

  const name = cleanText(attributes.name || me.name || me.resident_id || "居民", 120);
  const specialIdentities = arrayValue(soulProfile.special_identities)
    .map((item) => typeof item === "string" ? item : item?.label)
    .filter(Boolean);
  const relationshipHints = arrayValue(soulProfile.relationship_hints);
  const interests = [
    ...arrayValue(attributes.interests),
    ...arrayValue(attributes.customInterests)
  ].filter(Boolean);

  const currentState = renderCurrentState(wakePacket);
  const memoryText = extractTaggedSection(payload.messages, "memory_context");

  const character = {
    name,
    role: cleanText(socialState.job, 300),
    personality: cleanText(attributes.personality, 1000),
    goal: cleanText(attributes.desire, 900),
    voice: cleanText(attributes.speech, 900),
    currentState,
    notes: cleanText(JSON.stringify({
      interests,
      specialIdentities,
      soulProfile
    }, null, 2), 2200)
  };

  const creativeContext = {
    project: {
      name: "AI Town",
      description: "LLM 驱动居民生活的持续世界模拟。居民必须忠于自己的稳定人物设定，同时以 Godot 世界确认的事实为准。",
      worldOverview: cleanText(JSON.stringify({
        known_places: initialization.places ?? [],
        known_residents: initialization.residents ?? []
      }, null, 2), 5000),
      worldRules: cleanText(JSON.stringify(derivedConstraints, null, 2), 4200),
      relations: cleanText(JSON.stringify(relationshipHints, null, 2), 3200)
    },
    characters: [character]
  };

  const memoryContext = memoryText ? {
    items: [{
      type: "人物记忆",
      content: memoryText,
      characters: [name],
      tags: ["AI Town", "居民记忆"],
      importance: 5
    }]
  } : { items: [] };

  const continuityContext = {
    characterStates: currentState ? [{ name, state: currentState }] : []
  };

  const upstreamContext = buildCreativeContextMessage(
    creativeContext,
    memoryContext,
    continuityContext
  );

  return upstreamContext
    .replace("# 当前小说创作上下文", "# 当前居民人物连续性上下文")
    .replace(
      "正式正文与已确认的连续性状态优先于宽泛总纲。",
      "已确认的世界事实与人物连续性状态优先于宽泛背景。"
    );
}

function enrichMessages(payload) {
  const messages = arrayValue(payload.messages).map((message) => ({ ...message }));
  const context = buildAiTownContext(payload);
  if (!context) return messages;

  const block = `<character_intelligence_context>\n${context}\n</character_intelligence_context>`;
  const systemIndex = messages.findIndex((message) => message?.role === "system" && typeof message?.content === "string");
  if (systemIndex >= 0) {
    messages[systemIndex] = {
      ...messages[systemIndex],
      content: `${messages[systemIndex].content}\n\n${block}`
    };
  } else {
    messages.unshift({ role: "system", content: block });
  }
  return messages;
}

function configuredModelSlots(env) {
  const result = [];
  for (let index = 1; index <= WORKER_SLOT_COUNT; index += 1) {
    const alias = `${WORKER_SLOT_PREFIX}${index}`;
    const model = cleanText(env[`SILICONFLOW_MODEL_${index}`], 300);
    result.push({ alias, index, model, configured: Boolean(model) });
  }
  return result;
}

function resolveModelToken(token, env) {
  const normalized = cleanText(token, 300);
  if (!normalized) return "";
  if (normalized === WORKER_DEFAULT_MODEL) {
    return cleanText(env.SILICONFLOW_MODEL, 300);
  }
  if (normalized.startsWith(WORKER_SLOT_PREFIX)) {
    const suffix = normalized.slice(WORKER_SLOT_PREFIX.length);
    const index = Number(suffix);
    if (Number.isInteger(index) && index >= 1 && index <= WORKER_SLOT_COUNT) {
      return cleanText(env[`SILICONFLOW_MODEL_${index}`], 300);
    }
    return "";
  }
  return normalized;
}

function residentIdentity(payload) {
  const initialization = objectValue(payload.initialization);
  const me = objectValue(initialization.me);
  const attributes = objectValue(me.attributes);
  return {
    id: cleanText(me.resident_id || me.residentId, 160),
    name: cleanText(attributes.name || me.name, 160)
  };
}

function residentModelOverride(payload, env) {
  const source = cleanText(env.SILICONFLOW_RESIDENT_MODELS, 16000);
  if (!source) return "";
  let mapping;
  try {
    mapping = JSON.parse(source);
  } catch {
    return "";
  }
  if (!mapping || typeof mapping !== "object" || Array.isArray(mapping)) return "";
  const identity = residentIdentity(payload);
  const token = mapping[identity.id] ?? mapping[identity.name] ?? "";
  return cleanText(token, 300);
}

function primaryModelToken(payload, env) {
  const requested = cleanText(payload?.model, 300);
  if (requested) return requested;
  const residentOverride = residentModelOverride(payload, env);
  if (residentOverride) return residentOverride;
  return WORKER_DEFAULT_MODEL;
}

function fallbackModelTokens(env) {
  const explicit = parseModelList(env.SILICONFLOW_FALLBACK_MODELS);
  if (explicit.length) return explicit;
  return [
    WORKER_DEFAULT_MODEL,
    ...configuredModelSlots(env)
      .filter((item) => item.configured)
      .map((item) => item.alias)
  ];
}

function modelCandidates(payload, env) {
  const primaryToken = primaryModelToken(payload, env);
  const tokens = unique([primaryToken, ...fallbackModelTokens(env)]);
  const result = [];
  const seenModels = new Set();
  for (const token of tokens) {
    const model = resolveModelToken(token, env);
    if (!model || seenModels.has(model)) continue;
    seenModels.add(model);
    result.push({ token, model });
  }
  return result;
}

function shouldFallback(status) {
  return status === 400
    || status === 404
    || status === 408
    || status === 409
    || status === 410
    || status === 429
    || status >= 500;
}

function healthProbeResponse(modelToken, model) {
  return jsonResponse({
    id: "ai-town-worker-health",
    object: "chat.completion",
    model: model || modelToken || "unconfigured",
    choices: [{
      index: 0,
      message: { role: "assistant", content: "{\"ok\":true}" },
      finish_reason: "stop"
    }],
    usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
  }, 200, {
    "X-AI-Town-Health-Probe": "local",
    "X-Model-Used": model || modelToken || "unconfigured"
  });
}

async function requestSiliconFlow(endpoint, apiKey, body) {
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify(body)
    });
    return { response, error: null };
  } catch (error) {
    return { response: null, error };
  }
}

async function handleAgent(request, env) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: { message: "Bad JSON", type: "request_validation" } }, 400);
  }

  const apiKey = cleanText(env.SILICONFLOW_API_KEY, 1000);
  const endpoint = cleanText(env.SILICONFLOW_CHAT_URL, 1000) || DEFAULT_SILICONFLOW_CHAT_URL;
  const candidates = modelCandidates(payload, env);
  const requestedToken = primaryModelToken(payload, env);

  if (!apiKey) {
    return jsonResponse({
      error: {
        message: "SILICONFLOW_API_KEY is not configured yet.",
        type: "configuration"
      }
    }, 503);
  }
  if (!arrayValue(payload.messages).length) {
    return jsonResponse({
      error: { message: "messages must be a non-empty array", type: "request_validation" }
    }, 400);
  }
  if (!candidates.length) {
    return jsonResponse({
      error: {
        message: `No SiliconFlow model is configured for ${requestedToken || "the default model"}.`,
        type: "configuration"
      }
    }, 503);
  }

  if (payload.request_kind === "health_probe") {
    return healthProbeResponse(requestedToken, candidates[0]?.model || "");
  }

  const messages = enrichMessages(payload);
  const maxTokens = Math.max(256, Math.min(4096, Number(payload.max_tokens) || 1024));
  let fallbackReason = "";
  let lastStatus = 502;
  let lastErrorText = "No model candidate was available.";

  for (let index = 0; index < candidates.length; index += 1) {
    const candidate = candidates[index];
    const upstreamBody = {
      model: candidate.model,
      messages,
      stream: false,
      max_tokens: maxTokens
    };
    const { response, error } = await requestSiliconFlow(endpoint, apiKey, upstreamBody);

    if (error) {
      lastStatus = 504;
      lastErrorText = error?.message || "SiliconFlow network request failed";
      if (!fallbackReason) fallbackReason = `request failure on ${candidate.model}`;
      continue;
    }

    if (!response.ok) {
      const errorText = (await response.text().catch(() => "")).slice(0, 3000);
      lastStatus = response.status;
      lastErrorText = errorText || `HTTP ${response.status}`;
      if (index < candidates.length - 1 && shouldFallback(response.status)) {
        if (!fallbackReason) fallbackReason = `HTTP ${response.status} on ${candidate.model}`;
        continue;
      }
      return jsonResponse({
        error: {
          message: lastErrorText,
          type: "upstream",
          status: response.status,
          model: candidate.model
        }
      }, response.status);
    }

    const headers = new Headers(response.headers);
    headers.set("Access-Control-Allow-Origin", "*");
    headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    headers.set("Cache-Control", "no-store");
    headers.set("X-AI-Town-Context", "unlimited-ai-first/context.js");
    headers.set("X-Upstream-Commit", UPSTREAM_UNLIMITED_AI_COMMIT);
    headers.set("X-Requested-Model", requestedToken || WORKER_DEFAULT_MODEL);
    headers.set("X-Model-Used", candidate.model);
    headers.set("X-Model-Alias-Used", candidate.token);
    if (index > 0 && fallbackReason) {
      headers.set("X-Model-Fallback", fallbackReason);
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers
    });
  }

  return jsonResponse({
    error: {
      message: lastErrorText,
      type: "upstream",
      status: lastStatus,
      attemptedModels: candidates.map((candidate) => candidate.model)
    }
  }, lastStatus);
}

function publicModelConfig(env) {
  return {
    default: {
      alias: WORKER_DEFAULT_MODEL,
      configured: Boolean(cleanText(env.SILICONFLOW_MODEL)),
      model: cleanText(env.SILICONFLOW_MODEL, 300)
    },
    slots: configuredModelSlots(env),
    fallbackModels: fallbackModelTokens(env),
    residentOverrideCount: (() => {
      const source = cleanText(env.SILICONFLOW_RESIDENT_MODELS, 16000);
      if (!source) return 0;
      try {
        const parsed = JSON.parse(source);
        return parsed && typeof parsed === "object" && !Array.isArray(parsed)
          ? Object.keys(parsed).length
          : 0;
      } catch {
        return 0;
      }
    })()
  };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Max-Age": "86400"
        }
      });
    }

    if (request.method === "GET" && url.pathname === "/health") {
      const modelConfig = publicModelConfig(env);
      return jsonResponse({
        ok: true,
        upstreamCommit: UPSTREAM_UNLIMITED_AI_COMMIT,
        contextEngine: "vendor/unlimited-ai-first/src/context.js",
        siliconFlowKeyConfigured: Boolean(cleanText(env.SILICONFLOW_API_KEY)),
        siliconFlowModelConfigured: modelConfig.default.configured,
        siliconFlowEndpointConfigured: Boolean(cleanText(env.SILICONFLOW_CHAT_URL) || DEFAULT_SILICONFLOW_CHAT_URL),
        configuredModelSlotCount: modelConfig.slots.filter((item) => item.configured).length,
        fallbackConfigured: Boolean(cleanText(env.SILICONFLOW_FALLBACK_MODELS)),
        residentModelOverrideCount: modelConfig.residentOverrideCount
      });
    }

    if (request.method === "GET" && url.pathname === "/api/models") {
      return jsonResponse(publicModelConfig(env));
    }

    if (request.method === "POST" && url.pathname === "/api/agent") {
      return handleAgent(request, env);
    }

    return jsonResponse({ error: "Not found" }, 404);
  }
};
