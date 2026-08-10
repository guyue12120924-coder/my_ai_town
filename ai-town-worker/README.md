# AI Town Worker Adapter

This directory is the thin adapter between the Godot AI Town and the existing `unlimited-ai-first` Worker codebase.

The upstream project is preserved unchanged at `vendor/unlimited-ai-first` as a Git submodule pinned to commit `64409d7ad930e7ff5948f2c15764c440741d01ae`.

The adapter intentionally reuses the upstream `src/context.js` character/context builder instead of rewriting it in GDScript. AI Town still owns world facts, action validation, execution, save/load and resident memory. The Worker only enriches the model context and forwards the request to a SiliconFlow OpenAI-compatible endpoint.

## Required configuration

Keep the API values empty until you are ready to use them.

```text
SILICONFLOW_API_KEY=
SILICONFLOW_MODEL=
SILICONFLOW_CHAT_URL=https://api.siliconflow.cn/v1/chat/completions
```

For Cloudflare deployment:

```bash
git submodule update --init --recursive
cd ai-town-worker
wrangler secret put SILICONFLOW_API_KEY
wrangler deploy
```

Set `SILICONFLOW_MODEL` in `wrangler.toml` or in the Cloudflare dashboard before enabling AI calls.

## Godot connection

In AI Town model settings choose `OpenAI Compatible` and use the deployed Worker endpoint ending in:

```text
/api/agent
```

When the endpoint ends in `/api/agent`, the Godot provider forwards the compiled resident initialization, wake packet and derived constraints in addition to normal messages. API key and model fields may remain empty on the Godot side because the Worker owns the SiliconFlow credentials/model.

## Routes

- `GET /health` — configuration/status check without exposing secrets.
- `POST /api/agent` — AI Town resident decision endpoint. Returns the upstream OpenAI-compatible JSON response unchanged.

The original `unlimited-ai-first` source is not modified by this adapter.
