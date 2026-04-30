# Agent API Access

Use one LiteLLM virtual key per user or per coding agent. Do not share the
LiteLLM master key.

The hub exposes the API shapes that common coding agents expect:

- OpenAI Chat Completions: `/v1/chat/completions`
- OpenAI Responses: `/v1/responses`
- Codex Responses compatibility: `/codex/v1/responses`
- Anthropic Messages: `/v1/messages`
- Anthropic token counting: `/v1/messages/count_tokens`

Both public model names are local Qwen routes:

- `qwen3.6-27b`
- `qwen3.6-27b-thinking`

## URLs

Stage 1 quick tunnel:

```text
OpenAI/OpenClaw base URL:      https://<quick-tunnel>.trycloudflare.com/v1
Codex base URL:                https://<quick-tunnel>.trycloudflare.com/codex/v1
Claude Code base URL:          https://<quick-tunnel>.trycloudflare.com
```

Current local test URLs:

```text
OpenAI-compatible base URL: http://127.0.0.1:8090/v1
Codex-compatible base URL:  http://127.0.0.1:8090/codex/v1
Anthropic-compatible base:  http://127.0.0.1:8090
```

Stage 2 production URLs:

```text
OpenAI/OpenClaw base URL:      https://api.your-domain.com/v1
Codex base URL:                https://api.your-domain.com/codex/v1
Claude Code base URL:          https://api.your-domain.com
Browser UI URL:                https://llm.your-domain.com
```

## Admin Key Management

The admin helper reads `LITELLM_MASTER_KEY` from `.env` by default.

Generate one virtual key:

```bash
cd /home/adventor/simon/llm-hub
./scripts/litellm-key generate \
  --user alice@example.com \
  --alias alice-codex
```

Defaults:

- Models: `qwen3.6-27b,qwen3.6-27b-thinking`
- Duration: `30d`
- RPM limit: `10`
- TPM limit: `60000`

Useful variants:

```bash
./scripts/litellm-key generate \
  --user alice@example.com \
  --alias alice-claude-code \
  --duration 14d \
  --rpm-limit 8 \
  --tpm-limit 40000

./scripts/litellm-key list
./scripts/litellm-key info --key sk-user-litellm-key
./scripts/litellm-key delete --key sk-user-litellm-key --yes
```

Run protocol smoke tests with a user key:

```bash
./scripts/litellm-key smoke \
  --key sk-user-litellm-key \
  --base-url http://127.0.0.1:8090
```

The smoke test checks model listing, Chat Completions, Responses, Anthropic
Messages, Anthropic token counting, a forced tool call, and denial of an
unknown model.

## Codex

For Codex-style clients that use the OpenAI Responses API:

```bash
export OPENAI_API_KEY="sk-user-litellm-key"
```

Example `~/.codex/config.toml`:

```toml
model = "qwen3.6-27b"
model_provider = "llm-hub"

[model_providers.llm-hub]
name = "Local LLM Hub"
base_url = "https://api.your-domain.com/codex/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
```

During the Stage 1 quick-tunnel pilot, use:

```toml
base_url = "https://<quick-tunnel>.trycloudflare.com/codex/v1"
```

Use `model = "qwen3.6-27b-thinking"` when you want the reasoning alias.

Codex should use the `/codex/v1` gateway rather than raw `/v1`. Codex sends
native OpenAI Responses tool types such as `image_generation` that llama.cpp
rejects. The gateway keeps function tools and strips unsupported native tool
entries before forwarding to LiteLLM.

## Claude Code

Claude Code uses the Anthropic-compatible surface, so the base URL should not
include `/v1`:

```bash
export ANTHROPIC_BASE_URL="https://api.your-domain.com"
export ANTHROPIC_AUTH_TOKEN="sk-user-litellm-key"
export ANTHROPIC_MODEL="qwen3.6-27b"
export ANTHROPIC_CUSTOM_MODEL_OPTION="qwen3.6-27b"
export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="Local Qwen 27B"
```

During Stage 1:

```bash
export ANTHROPIC_BASE_URL="https://<quick-tunnel>.trycloudflare.com"
```

Use `ANTHROPIC_MODEL="qwen3.6-27b-thinking"` for the reasoning alias.

## OpenClaw

Add a custom OpenAI-compatible provider:

```js
{
  env: { LLM_HUB_API_KEY: "sk-user-litellm-key" },
  agents: {
    defaults: { model: { primary: "llmhub/qwen3.6-27b" } }
  },
  models: {
    mode: "merge",
    providers: {
      llmhub: {
        baseUrl: "https://api.your-domain.com/v1",
        apiKey: "${LLM_HUB_API_KEY}",
        api: "openai-completions",
        models: [
          {
            id: "qwen3.6-27b",
            name: "Local Qwen 27B",
            reasoning: false,
            input: ["text", "image"],
            contextWindow: 32768,
            maxTokens: 8192
          },
          {
            id: "qwen3.6-27b-thinking",
            name: "Local Qwen 27B Thinking",
            reasoning: true,
            input: ["text", "image"],
            contextWindow: 32768,
            maxTokens: 8192
          }
        ]
      }
    }
  }
}
```

During Stage 1, set `baseUrl` to the quick-tunnel `/v1` URL.

## Generic OpenAI-Compatible Clients

```bash
export OPENAI_API_KEY="sk-user-litellm-key"
export OPENAI_BASE_URL="https://api.your-domain.com/v1"
```

Minimal request:

```bash
curl -s "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.6-27b",
    "messages": [{"role": "user", "content": "Reply with exactly: ready"}],
    "max_tokens": 12,
    "temperature": 0,
    "stream": false
  }'
```

## Security Notes

- API authentication is LiteLLM virtual keys only, for compatibility with
  coding agents that cannot send Cloudflare Access service-token headers.
- Browser access can still sit behind Cloudflare Access and Open WebUI auth.
- Stage 1 `trycloudflare.com` URLs are for trusted pilots only.
- Stage 2 should use `api.your-domain.com` for agents and `llm.your-domain.com`
  for browser users.
- The model backend is local. User prompts and code context go to this hub and
  the local GPU worker, not to an external LLM provider.
- Cloudflare still carries tunnel traffic, and Open WebUI web-search queries
  can leave the machine through SearXNG search engines when users enable search.
