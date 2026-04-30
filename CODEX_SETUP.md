# Codex CLI Setup

Use this to connect Codex CLI to this local LLM hub.

## Prerequisites

- A LiteLLM API key from the hub admin.
- The hub setup URL.
- Node.js/npm if Codex CLI is not already installed.

The installer can install `@openai/codex` automatically when `npm` is present. It does not install Node/npm itself.

## Setup

Run the installer from the hub URL:

```bash
curl -fsSL https://<hub-host>/codex/setup.sh | bash
```

Current quick tunnel:

```bash
curl -fsSL https://clark-colleague-areas-pearl.trycloudflare.com/codex/setup.sh | bash
```

The installer prompts for the Codex gateway URL and your LiteLLM API key. When served from the hub, the gateway URL is pre-filled; press Enter to accept it.

It creates or updates:

- `~/.codex/config.toml`
- `~/.codex/llm-hub-model-catalog.json`
- `~/.local/bin/codex-llm-hub`
- `~/.local/bin/codex-llm-hub-thinking`
- `~/.config/llm-hub/codex.env` with `0600` permissions

## Use

Normal model:

```bash
codex-llm-hub
```

Thinking model:

```bash
codex-llm-hub-thinking
```

Smoke test:

```bash
codex-llm-hub exec --skip-git-repo-check "Reply with exactly ready"
```

## Troubleshooting

- `npm: command not found`: install Node.js/npm first, then rerun the installer.
- `codex: command not found`: open a new shell, or run `export PATH="$HOME/.local/bin:$PATH"`.
- `401` or auth errors: rerun the installer and enter a valid LiteLLM key.
- `type of tool must be function`: make sure the gateway URL ends in `/codex/v1`, not `/v1`.
