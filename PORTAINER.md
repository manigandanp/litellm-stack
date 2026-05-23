# Portainer Deployment

Use `portainer-stack.yml` for a standalone Portainer Docker environment. Use `portainer-swarm-stack.yml` if your Portainer endpoint deploys Docker Swarm services. Both stacks run LiteLLM and Redis only; LiteLLM uses your remote Postgres database through `DATABASE_URL`.

If Portainer shows errors like `failed to create service`, `tasks will be created`, `Ignoring unsupported options: restart`, or `Only networks scoped to the swarm can be used`, your endpoint is deploying a Swarm stack. Use `portainer-swarm-stack.yml`.

## Recommended Deployment

Use Portainer's Git repository stack mode when possible:

1. Go to **Stacks** -> **Add stack**.
2. Choose **Repository**.
3. Set the compose path:
   - Standalone Docker endpoint: `litellm-stack/portainer-stack.yml`
   - Docker Swarm endpoint: `litellm-stack/portainer-swarm-stack.yml`
4. Add environment variables from `litellm-stack/portainer.env.example`.
5. Deploy the stack.

With Git repository deployment, the standalone stack default config mount usually works:

```env
LITELLM_CONFIG_PATH=./litellm/config.yaml
```

The Swarm stack uses a Docker config loaded from `./litellm/config.yaml`, so it should also be deployed from repository mode.

## Web Editor Deployment

If you paste `portainer-stack.yml` into Portainer's web editor, the relative `./litellm/config.yaml` path will not exist unless you create it on the Docker host. Put the config on the host and set an absolute path:

```env
LITELLM_CONFIG_PATH=/opt/litellm/config.yaml
```

Then copy this repo's `litellm/config.yaml` to that host path before deploying the stack.

For Swarm web-editor deployment, create a Docker config named `litellm_config` in Portainer from the contents of `litellm/config.yaml`, then change the bottom of `portainer-swarm-stack.yml` to:

```yaml
configs:
  litellm_config:
    external: true
```

## Required Variables

Set these variables in Portainer's stack environment section:

```env
LITELLM_MASTER_KEY=sk-change-this-master-key
LITELLM_SALT_KEY=sk-change-this-salt-key
DATABASE_URL=postgresql://user:password@remote-postgres-host:5432/litellm?sslmode=require
REDIS_PASSWORD=change-this-redis-password
```

For Neon or Supabase, prefer the direct Postgres connection string instead of a pooled/PgBouncer URL because LiteLLM runs Prisma migrations during startup. URL-encode database passwords that contain special characters such as `@`, `:`, `/`, `?`, or `#`.

## Provider Variables

Paste the optional provider variables from `portainer.env.example` and fill in the keys you want to use. Blank provider keys are acceptable for stack validation, but model calls for that provider will fail until the key is set.

If Portainer exposes LiteLLM behind a public hostname, set `OR_SITE_URL` to that external URL for OpenRouter attribution:

```env
OR_SITE_URL=https://litellm.example.com
```

## Deploy Checks

After deployment:

```bash
curl http://YOUR_HOST:4000/health/liveliness
curl http://YOUR_HOST:4000/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

LiteLLM logs should show application startup complete. The first startup can take longer because LiteLLM applies database migrations.
