# AI Town Worker Adapter

This directory is the thin adapter between the Godot AI Town and the existing `unlimited-ai-first` Worker codebase.

The upstream project is preserved unchanged at `vendor/unlimited-ai-first` as a Git submodule pinned to commit `64409d7ad930e7ff5948f2c15764c440741d01ae`.

The adapter intentionally reuses the upstream `src/context.js` character/context builder instead of rewriting it in GDScript. AI Town still owns world facts, action validation, execution, save/load and resident memory. The Worker only enriches the model context and forwards the request to a SiliconFlow OpenAI-compatible endpoint.

## Cloudflare runtime configuration

Configure runtime values in Cloudflare Dashboard → Worker → Settings → Variables and Secrets. `wrangler.toml` uses `keep_vars = true`, so dashboard variables are preserved when GitHub automatic deployments run.

Required:

```text
SILICONFLOW_API_KEY=<Secret>
SILICONFLOW_MODEL=<default SiliconFlow model id>
```

Optional model slots:

```text
SILICONFLOW_MODEL_1=<model id>
SILICONFLOW_MODEL_2=<model id>
SILICONFLOW_MODEL_3=<model id>
SILICONFLOW_MODEL_4=<model id>
SILICONFLOW_MODEL_5=<model id>
SILICONFLOW_MODEL_6=<model id>
SILICONFLOW_MODEL_7=<model id>
SILICONFLOW_MODEL_8=<model id>
```

Optional explicit fallback order, using either real SiliconFlow model IDs or the aliases below:

```text
SILICONFLOW_FALLBACK_MODELS=ai-town-worker-slot-2,ai-town-worker-slot-1,ai-town-worker-default
```

Optional resident override map (resident id or resident name → actual model id / alias):

```text
SILICONFLOW_RESIDENT_MODELS={"resident-01":"ai-town-worker-slot-1","张三":"Qwen/Example-Model"}
```

The endpoint defaults to:

```text
https://api.siliconflow.cn/v1/chat/completions
```

You may override it with `SILICONFLOW_CHAT_URL` if needed.

## Model aliases used by AI Town

The existing resident model-assignment page can now assign these OpenAI Compatible models per resident:

```text
ai-town-worker-default   -> SILICONFLOW_MODEL
ai-town-worker-slot-1    -> SILICONFLOW_MODEL_1
ai-town-worker-slot-2    -> SILICONFLOW_MODEL_2
ai-town-worker-slot-3    -> SILICONFLOW_MODEL_3
ai-town-worker-slot-4    -> SILICONFLOW_MODEL_4
ai-town-worker-slot-5    -> SILICONFLOW_MODEL_5
ai-town-worker-slot-6    -> SILICONFLOW_MODEL_6
ai-town-worker-slot-7    -> SILICONFLOW_MODEL_7
ai-town-worker-slot-8    -> SILICONFLOW_MODEL_8
```

If an assigned model fails with a retryable HTTP status or a network failure, the Worker tries the configured fallback list. If no explicit fallback list is supplied, it falls back through the configured default/slot models without repeating the same real model ID.

Provider health checks for these Worker aliases are handled locally by the adapter so opening the model-assignment page does not spend model tokens merely to populate the catalog.

## Godot connection

In AI Town model settings choose `OpenAI Compatible` and use the deployed Worker endpoint ending in:

```text
/api/agent
```

When the endpoint ends in `/api/agent`, the Godot provider forwards the compiled resident initialization, wake packet and derived constraints in addition to normal messages. The Godot-side API key can remain empty because the Worker owns the SiliconFlow credential.

## Routes

- `GET /health` — configuration/status check without exposing secrets.
- `GET /api/models` — shows the default/slot/fallback configuration without exposing the API key.
- `POST /api/agent` — AI Town resident decision endpoint. Returns the successful SiliconFlow OpenAI-compatible response unchanged and reports the model actually used in response headers.

The original `unlimited-ai-first` source is not modified by this adapter.
