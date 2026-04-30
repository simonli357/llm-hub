# Codex CLI Setup

Use this when you want Codex CLI to talk to this local LLM hub.

## Fast Setup

Run the installer from the hub URL:

```bash
curl -fsSL https://<hub-host>/codex/setup.sh | bash
```

The installer prompts for the Codex gateway URL and your LiteLLM API key, writes
`~/.codex/config.toml`, creates `codex-llm-hub` and
`codex-llm-hub-thinking` in `~/.local/bin`, and stores the key in
`~/.config/llm-hub/codex.env` with `0600` permissions. When the installer is
served from the hub, it pre-fills the gateway URL; press Enter to accept it.

For the current quick tunnel:

```bash
curl -fsSL https://clark-colleague-areas-pearl.trycloudflare.com/codex/setup.sh | bash
```

Then start Codex with:

```bash
codex-llm-hub
```

Use the thinking model with:

```bash
codex-llm-hub-thinking
```

## Prerequisites

- A LiteLLM API key from the hub admin.
- The public hub URL. For Codex, use the Codex gateway path: `https://<hub-host>/codex/v1`.
- Node.js/npm, if Codex CLI is not already installed.

Install Codex CLI:

```bash
npm install -g @openai/codex
codex --version
```

If `codex` is not found after install, add npm's global bin directory to `PATH`:

```bash
export PATH="$(npm prefix -g)/bin:$PATH"
```

## Configure Codex

Set your key:

```bash
export OPENAI_API_KEY="<your-litellm-key>"
```

If your shell already has `OPENAI_BASE_URL` set for another client, unset it or point it at the Codex gateway:

```bash
unset OPENAI_BASE_URL
```

Add this to `~/.codex/config.toml`. Replace the `base_url` host with the current hub URL.

```toml
[profiles."llm-hub"]
model = "qwen3.6-27b"
model_provider = "llm-hub"
model_context_window = 32768
model_auto_compact_token_limit = 28000
model_reasoning_effort = "minimal"
web_search = "disabled"
tools_view_image = false

[profiles."llm-hub-thinking"]
model = "qwen3.6-27b-thinking"
model_provider = "llm-hub"
model_context_window = 32768
model_auto_compact_token_limit = 28000
model_reasoning_effort = "minimal"
web_search = "disabled"
tools_view_image = false

[model_providers."llm-hub"]
name = "Local LLM Hub"
base_url = "https://<hub-host>/codex/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
```

Important: use `/codex/v1`, not `/v1`. The raw `/v1` endpoint is for normal OpenAI-compatible clients; Codex needs the compatibility gateway.

## Run

Normal model:

```bash
codex --profile llm-hub \
  --disable apps \
  --disable image_generation \
  --disable multi_agent \
  --disable plugins \
  --disable tool_suggest
```

Thinking model:

```bash
codex --profile llm-hub-thinking \
  --disable apps \
  --disable image_generation \
  --disable multi_agent \
  --disable plugins \
  --disable tool_suggest
```

Quick smoke test:

```bash
codex --profile llm-hub exec --skip-git-repo-check "Reply with exactly ready"
```

## Troubleshooting

- `401` or auth errors: check that `OPENAI_API_KEY` is set to a valid LiteLLM key.
- `type of tool must be function`: you are probably using `/v1`; switch to `/codex/v1`.
- `codex: command not found`: add `$(npm prefix -g)/bin` to `PATH`.
- Model warnings are usually harmless if requests still complete, but using `/codex/v1` avoids the common model-catalog mismatch.
