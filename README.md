# Standalone LiteLLM Simple Quality Gateway

Docker-based LiteLLM proxy for aggregating direct providers, free routers, and credit-backed gateways behind one OpenAI-compatible API. The catalog exposes four simple aliases and orders deployments by community preference, reliability, and cost.

## What Runs

- `litellm`: OpenAI-compatible proxy and LiteLLM UI on `http://localhost:4000`
- remote Postgres: durable LiteLLM database for virtual keys, teams, users, spend, and metadata
- `redis`: shared router state, auth cache, and optional response cache

Redis is an internal Docker service and is not published to the host. A local Postgres container is still available through the optional `local-db` Compose profile for development.

## Setup

```bash
cd litellm-stack
cp .env.example .env
```

Generate strong secrets and replace the placeholder values in `.env`:

```bash
python -c "import secrets; print('sk-' + secrets.token_urlsafe(32))"
```

Set your remote Postgres connection string:

```bash
DATABASE_URL=postgresql://user:password@remote-postgres-host:5432/litellm?sslmode=require
```

URL-encode the password if it contains special characters such as `@`, `:`, `/`, `?`, or `#`.
For Neon/Supabase-style databases, use the direct Postgres URL rather than the pooled/PgBouncer URL because LiteLLM runs Prisma migrations during startup.

Set the provider keys you want to use in `.env`:

```bash
GROQ_API_KEY=gsk_...
MISTRAL_API_KEY=...
GEMINI_API_KEY=...
CEREBRAS_API_KEY=...
CEREBRAS_API_BASE=https://api.cerebras.ai/v1
OLLAMA_API_KEY=...
OLLAMA_API_BASE=https://ollama.com/v1
OPENROUTER_API_KEY=...
OPENROUTER_API_BASE=https://openrouter.ai/api/v1
OR_SITE_URL=http://localhost:4000
OR_APP_NAME=LiteLLM Simple Quality Gateway
```

Vercel AI Gateway and Lightning AI Gateway are enabled in the catalog because they can provide premium model access, but they may consume free credits or paid balance:

```bash
VERCEL_AI_GATEWAY_API_KEY=...
VERCEL_AI_GATEWAY_API_BASE=https://ai-gateway.vercel.sh/v1
LIGHTNING_AI_API_KEY=...
LIGHTNING_AI_API_BASE=https://lightning.ai/api/v1
```

Set these Langfuse keys to enable LiteLLM request tracing:

```bash
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_OTEL_HOST=https://cloud.langfuse.com
```

Use `https://us.cloud.langfuse.com` instead if your Langfuse project is in the US region.

Start the stack:

```bash
docker compose --env-file .env up -d
docker compose ps
docker compose logs -f litellm
```

For Portainer, use `portainer-stack.yml` and follow `PORTAINER.md`.

To use the bundled local Postgres instead of a remote database, point `DATABASE_URL` at the Compose service and enable the profile:

```bash
DATABASE_URL=postgresql://litellm:change-this-postgres-password@postgres:5432/litellm
docker compose --profile local-db --env-file .env up -d
```

When switching an existing stack from bundled Postgres to remote Postgres, clean up the old local Postgres container first:

```bash
docker compose --profile local-db --env-file .env down
docker compose --env-file .env up -d
```

This stops the old local Postgres container without deleting its volume. Add `-v` to `down` only if you intentionally want to delete local Postgres and Redis data.

Stop it without deleting data:

```bash
docker compose down
```

Delete all persisted LiteLLM/Postgres/Redis data:

```bash
docker compose down -v
```

## Public Model Aliases

Clients should call these four aliases instead of provider-specific model IDs:

- `rough-use`: summarization, rewriting, story generation, and everyday prompts. Ordered as Gemini Flash/Lite, GPT-OSS on Groq/Cerebras/Ollama, Mistral Large, then OpenRouter free routes.
- `coding`: code generation, debugging, refactors, and agentic coding. Ordered as Cerebras/Ollama GLM 4.7, Devstral, Codestral, Qwen Coder, Groq Qwen, DeepSeek free, then OpenRouter's free router.
- `smart-mini`: cheap/free small-model work. Ordered as Gemini Flash-Lite, Vercel GPT/Qwen nano-class models, Lightning GPT-5 Nano, Groq/Ollama GPT-OSS 20B, then OpenRouter GPT-OSS 20B free.
- `smart-large`: stronger low-cost reasoning/general work. Ordered as Gemini 3.5/2.5 Flash, Cerebras/Ollama GLM 4.7, DeepSeek/Kimi/MiniMax gateways, GPT-OSS, Nemotron free, then OpenRouter's free router.

Deployment priority is configured with `litellm_params.order`; lower values are tried first. Keep `router_settings.enable_pre_call_checks: true`, because LiteLLM uses it for ordered deployment selection.

Fallbacks are intentionally simple:

- `rough-use` -> `smart-mini` -> `smart-large`
- `coding` -> `smart-large` -> `rough-use`
- `smart-mini` -> `rough-use` -> `smart-large`
- `smart-large` -> `rough-use` -> `smart-mini`

Image generation, embeddings, and TTS are intentionally not part of this simplified chat catalog. Add them as separate aliases later if you want media or embedding endpoints.

Example client base URL:

```text
http://localhost:4000
```

Use `LITELLM_MASTER_KEY` from `.env` as the bearer token, or generate a virtual key.

## Health Checks

Container liveness:

```bash
curl http://localhost:4000/health/liveliness
```

List configured models:

```bash
curl http://localhost:4000/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

Static config checks:

```bash
python - <<'PY'
from pathlib import Path
import yaml
data = yaml.safe_load(Path("litellm/config.yaml").read_text())
print(len(data["model_list"]), "model deployments")
print(len({m["model_name"] for m in data["model_list"]}), "model groups")
PY

python tools/validate-model-catalog.py
docker compose --env-file .env.example -f docker-compose.yml config
```

After the stack is running, verify that the proxy exposes required aliases:

```bash
export LITELLM_MASTER_KEY=sk-your-litellm-key
python tools/validate-model-catalog.py --runtime
```

## Chat Completion

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "rough-use",
    "messages": [
      { "role": "user", "content": "Give me one sentence about LiteLLM fallbacks." }
    ]
  }'
```

The same endpoint also works with OpenAI-compatible SDKs:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:4000",
    api_key="sk-your-litellm-key",
)

response = client.chat.completions.create(
    model="smart-large",
    messages=[{"role": "user", "content": "Explain routing in one paragraph."}],
)
print(response.choices[0].message.content)
```

## Virtual Keys

Generate a limited client key from the master key:

```bash
curl http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "models": [
      "rough-use",
      "coding",
      "smart-mini",
      "smart-large"
    ],
    "rpm_limit": 60,
    "duration": "30d",
    "key_alias": "local-dev"
  }'
```

Use the returned key for applications instead of the master key.

## Response Caching

Redis caching is configured but defaults to opt-in to avoid caching sensitive prompts accidentally. Enable caching per request with LiteLLM cache controls when you are comfortable caching that workload.

## Langfuse Tracing

LiteLLM sends request metadata to Langfuse through the `langfuse_otel` callback. Background health checks are disabled in `litellm/config.yaml` to avoid noisy internal traces. Prompt/response body logging is currently enabled via `turn_off_message_logging: false`; change it to `true` if you want metadata-only traces.

After adding or changing Langfuse variables, restart LiteLLM:

```bash
docker compose up -d
docker compose restart litellm
```

## Add Another Provider

1. Add the provider API key to `.env.example` and your local `.env`.
2. Add one or more `model_list` entries to `litellm/config.yaml`.
3. Reuse one of the public aliases, or create a new alias.
4. Extend `router_settings.fallbacks` if the new alias should participate in cross-group fallback.
5. Restart LiteLLM:

```bash
docker compose restart litellm
```

Example OpenAI-compatible provider entry:

```yaml
- model_name: rough-use
  litellm_params:
    model: "openai/provider-model-id"
    api_base: os.environ/NEW_PROVIDER_API_BASE
    api_key: os.environ/NEW_PROVIDER_API_KEY
    rpm: 20
    max_parallel_requests: 2
    order: 3
  model_info:
    id: new-provider-balanced
    mode: chat
    base_model: "openai/provider-model-id"
    tags: ["rough-use", "new-provider"]
```

## Production Notes

- Pin `LITELLM_IMAGE` to a tested version before exposing this publicly.
- Put a reverse proxy or load balancer with TLS in front of port `4000`.
- Keep `.env` out of git.
- Use virtual keys for applications and reserve the master key for administration.
- Rotate provider keys and LiteLLM keys periodically.
- Free provider quotas and model availability change frequently; update `rpm`, `tpm`, and model IDs after provider-side changes.
- Vercel and Lightning are credit-backed gateways, not unlimited free routes. Use virtual-key budgets if other apps or users share this proxy.
- Keep media models disabled unless `/images/generations` or `/audio/speech` succeeds through the running LiteLLM image with the intended provider.
