# Codex CLI Setup

Use this to connect Codex CLI to this local LLM hub.

## Prerequisites

- A LiteLLM API key from the hub admin.
- The hub setup URL.
- Node.js/npm if Codex CLI is not already installed.

The installer can install `@openai/codex` automatically when `npm` is present. It does not install Node/npm itself.

## Setup

Linux, macOS, or WSL:

```bash
curl -fsSL https://<hub-host>/codex/setup.sh | bash
```

Windows PowerShell:

```powershell
irm https://<hub-host>/codex/setup.ps1 | iex
```

Current quick tunnel on Linux, macOS, or WSL:

```bash
curl -fsSL https://clark-colleague-areas-pearl.trycloudflare.com/codex/setup.sh | bash
```

Current quick tunnel on Windows PowerShell:

```powershell
irm https://clark-colleague-areas-pearl.trycloudflare.com/codex/setup.ps1 | iex
```

The installer prompts for the Codex gateway URL and your LiteLLM API key. When served from the hub, the gateway URL is pre-filled; press Enter to accept it.

It creates or updates:

- `~/.codex/config.toml`
- `~/.codex/llm-hub-model-catalog.json`
- `codex-llm-hub` and `codex-llm-hub-thinking` helper commands
- Linux/macOS key file: `~/.config/llm-hub/codex.env` with `0600` permissions
- Windows key file: `%LOCALAPPDATA%\llm-hub\codex.env.ps1`

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
- Windows cannot find `codex-llm-hub`: open a new PowerShell window so the updated user `Path` is loaded.
- `401` or auth errors: rerun the installer and enter a valid LiteLLM key.
- `type of tool must be function`: make sure the gateway URL ends in `/codex/v1`, not `/v1`.
