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
- `open-webui`: browser chat UI on `http://localhost:3000`
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
virtual keys later instead of handing out the master key.

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

Example local model list:

```bash
curl -s http://localhost:4010/v1/models \
  -H "Authorization: Bearer $(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
```

Example local chat request through Caddy:

```bash
curl -s http://localhost:8090/v1/chat/completions \
  -H "Authorization: Bearer $(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"Reply with exactly: ready"}],"max_tokens":8,"temperature":0,"stream":false}'
```

Quick tunnels do not support SSE reliably, so use `"stream": false` during this
temporary stage.

## Health Checks

```bash
curl -s http://127.0.0.1:8081/v1/models
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
- Add Cloudflare Access with an email allowlist.
- Keep browser users behind both Cloudflare Access and Open WebUI auth.
- Give API users LiteLLM virtual keys, and prefer Cloudflare Access service
  tokens in front of `/v1`.
- Keep llama.cpp bound to localhost or a private network only.

## Important

`trycloudflare.com` quick tunnels are temporary previews. They are not protected by Cloudflare Access and should only be shared with trusted pilot users.
