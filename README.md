# Local LLM Hub

This repo runs a temporary remote-access LLM hub for the local Qwen3.6-27B
`llama.cpp` worker. Users get one browser link for Open WebUI, and API clients
can use the same link under `/v1`.

Current flow:

```text
Users / API clients
  -> Cloudflare quick tunnel
  -> Caddy on 127.0.0.1:8090
  -> Open WebUI on 127.0.0.1:3000
  -> LiteLLM on 127.0.0.1:4010
  -> llama.cpp on 127.0.0.1:8081
```

## Services

- `qwen36-llama.service`: persistent local Qwen3.6-27B model worker
- `litellm`: OpenAI-compatible router on `http://localhost:4010/v1`
- `open-webui`: patched/pinned browser chat UI on `http://localhost:3000`
- `searxng`: private local metasearch backend on `http://127.0.0.1:8082`
- `caddy`: local gateway on `http://localhost:8090`
- `cloudflared`: temporary `trycloudflare.com` quick tunnel to Caddy
- `postgres`: LiteLLM database for future virtual keys and usage tracking

The quick tunnel exposes:

- `/` -> Open WebUI
- `/v1/*` -> LiteLLM

## Secrets

Runtime secrets live in `.env`, which is intentionally ignored by Git.

- `WEBUI_ADMIN_EMAIL` and `WEBUI_ADMIN_PASSWORD`: Open WebUI admin login
- `LITELLM_MASTER_KEY`: API key for LiteLLM/OpenAI-compatible requests
- `POSTGRES_PASSWORD`: LiteLLM database password
- `WEBUI_SECRET_KEY`: Open WebUI session/signing secret

Do not share the LiteLLM master key broadly. For pilot users, create LiteLLM
virtual keys with `scripts/litellm-key` instead of handing out the master key.

## Model Worker

The local model worker is installed as a systemd user service:

```bash
systemctl --user status qwen36-llama.service
systemctl --user restart qwen36-llama.service
journalctl --user -u qwen36-llama.service -f
```

The tracked service template is in `systemd/qwen36-llama.service`. The installed
copy is:

```text
/home/adventor/.config/systemd/user/qwen36-llama.service
```

The worker is intentionally bound to `127.0.0.1:8081`.

The local `llama.cpp` checkout is kept outside this repo:

```text
/home/adventor/simon/llama.cpp
```

Git remotes for that checkout:

```text
origin   git@github.com:simonli357/llama.cpp.git
upstream https://github.com/ggml-org/llama.cpp.git
```

The known-good runtime source is pinned on the fork branch
`local/qwen36-rtx5090-tested` at:

```text
f42e29fdf199481effd31f281bf095ec6067757b
```

`llama.cpp` is not a submodule yet. This keeps `llm-hub` focused on
orchestration while still preserving the exact tested source in the fork.

## Start The Hub

```bash
cd /home/adventor/simon/llm-hub
docker compose up -d
```

Watch startup and copy the temporary public URL:

```bash
docker compose logs -f cloudflared
```

You can print the current quick-tunnel URL with:

```bash
docker compose logs --no-color cloudflared \
  | grep -o 'https://[-a-z0-9]*\.trycloudflare\.com' \
  | tail -1
```

## Stop The Hub

```bash
cd /home/adventor/simon/llm-hub
docker compose down
```

## Browser Use

Open the Caddy gateway locally:

```text
http://localhost:8090/
```

For the temporary public preview, open the `https://*.trycloudflare.com` URL from
the `cloudflared` logs.

Log in with the admin email/password from `.env`. Signup is disabled by default.
Create pilot users manually in Open WebUI, or briefly enable signup for a pilot
round and disable it immediately after.

## API Use

Use the LiteLLM OpenAI-compatible endpoint:

```text
http://localhost:8090/v1
https://<quick-tunnel>.trycloudflare.com/v1
```

For coding agents such as Codex, Claude Code, and OpenClaw, see
`AGENT_API.md`. The production API plan is one LiteLLM virtual key per user or
per agent, with the browser UI and agent API split across separate hostnames:

```text
https://llm.your-domain.com
https://api.your-domain.com
```

Example local model list:

```bash
curl -s http://localhost:4010/v1/models \
  -H "Authorization: Bearer $(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
```

Available model names:

- `qwen3.6-27b`: normal non-thinking mode.
- `qwen3.6-27b-thinking`: same local model with llama.cpp thinking enabled.

Example local chat request through Caddy:

```bash
curl -s http://localhost:8090/v1/chat/completions \
  -H "Authorization: Bearer $(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"Reply with exactly: ready"}],"max_tokens":8,"temperature":0,"stream":false}'
```

Example reasoning request:

```bash
curl -s http://localhost:8090/v1/chat/completions \
  -H "Authorization: Bearer $(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.6-27b-thinking","messages":[{"role":"user","content":"What is 17*23? Answer with only the number."}],"max_tokens":1400,"temperature":0,"stream":false}'
```

The thinking alias reserves a `1024` token reasoning budget, so set
`max_tokens` high enough to leave room for the final answer.

Image prompts use OpenAI-compatible `image_url` content blocks. The local
worker loads `mmproj-F16.gguf` through the systemd service, so image
understanding stays local.

Quick tunnels do not support SSE reliably, so use `"stream": false` during this
temporary stage.

## File Inputs

Open WebUI is built from a pinned upstream image plus a small local patch:

```text
open-webui/Dockerfile
open-webui/patch_file_context.py
```

Small text/code uploads up to `128 KiB` are injected as raw full context so the
model can inspect the actual source, including HTML/JS/CSS that normal document
extraction may strip. Larger files and non-text formats continue through Open
WebUI retrieval/RAG.

The patched image is tagged locally as:

```text
llm-hub-open-webui:0.9.2-file-context
```

## Web Search

Open WebUI web search is enabled with a private local SearXNG container:

```text
Open WebUI -> http://127.0.0.1:8082/search -> SearXNG
```

SearXNG is bound to loopback only. Users do not access it directly; they use the
web-search control inside Open WebUI. Search queries leave the machine through
the public search engines SearXNG queries, but no external LLM provider is used.

Useful checks:

```bash
curl -s 'http://127.0.0.1:8082/search?q=Open%20WebUI&format=json' \
  | python3 -m json.tool
```

## Health Checks

```bash
curl -s http://127.0.0.1:8081/v1/models
curl -s 'http://127.0.0.1:8082/search?q=test&format=json'
curl -s http://127.0.0.1:8090/
docker compose ps
```

Check logs:

```bash
docker compose logs -f litellm
docker compose logs -f open-webui
docker compose logs -f cloudflared
tail -f /home/adventor/simon/logs/qwen36-server.log
```

## Add More Models Later

1. Run the new backend worker on a stable local/private URL.
2. Add a new `model_list` entry to `litellm_config.yaml`.
3. Restart LiteLLM:

   ```bash
   docker compose restart litellm
   ```

4. Verify:

   ```bash
   curl -s http://localhost:8090/v1/models \
     -H "Authorization: Bearer $(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
   ```

## Production Upgrade

This Stage 1 setup uses a temporary `trycloudflare.com` quick tunnel. Before
real multi-user use:

- Move to a named Cloudflare Tunnel on a real Cloudflare-managed domain.
- Route `https://llm.your-domain.com` to Open WebUI for browser users.
- Route `https://api.your-domain.com` directly to LiteLLM for coding agents and
  API clients.
- Add Cloudflare Access with an email allowlist for the browser UI.
- Keep browser users behind both Cloudflare Access and Open WebUI auth.
- Give API users LiteLLM virtual keys only. Do not require Cloudflare Access
  service-token headers on the API hostname unless every target client supports
  custom Access headers.
- Use Cloudflare DNS, WAF, and rate-limiting controls around the public API
  hostname as needed.
- Keep llama.cpp bound to localhost or a private network only.

## Important

`trycloudflare.com` quick tunnels are temporary previews. They are not protected by Cloudflare Access and should only be shared with trusted pilot users.
