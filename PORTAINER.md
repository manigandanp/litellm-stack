# Portainer Deployment

Use `portainer-stack.yml` for a standalone Portainer Docker environment (recommended for small VMs). Use `portainer-swarm-stack.yml` only if your Portainer endpoint deploys Docker Swarm services. Both stacks run LiteLLM and Redis only; LiteLLM uses your remote Postgres database through `DATABASE_URL`.

If Portainer shows errors like `failed to create service`, `tasks will be created`, `Ignoring unsupported options: restart`, or `Only networks scoped to the swarm can be used`, your endpoint is deploying a Swarm stack. Use `portainer-swarm-stack.yml`, or leave Swarm mode and use the standalone stack (see below).

## Use Standalone Docker (No Swarm)

Swarm has noticeable memory overhead (raft + ingress mesh + service DNS). On VMs with 1-2 GB RAM, prefer standalone Docker with `portainer-stack.yml`.

On the Docker host, leave Swarm if it was previously initialized:

```bash
docker info --format '{{.Swarm.LocalNodeState}}'
# Expected: inactive
# If active:
docker swarm leave --force
```

Then in Portainer:

1. Open **Environments** -> your environment -> **Update environment** to refresh the detected mode. The environment should now show as standalone Docker (no "Swarm" badge).
2. If Portainer still treats the environment as Swarm, remove and re-add it.

After Portainer reports standalone mode, deploy `portainer-stack.yml`.

## Low-Memory Hosts (1 GB RAM)

`portainer-stack.yml` ships with conservative resource limits defined as env vars in `portainer.env.example`:

```env
REDIS_MAXMEMORY=64mb
REDIS_MEM_LIMIT=128m
REDIS_MEM_RESERVATION=64m
REDIS_CPUS=0.25
LITELLM_MEM_LIMIT=700m
LITELLM_MEM_RESERVATION=400m
LITELLM_CPUS=0.75
```

These keep the stack within ~830 MB committed (700 + 128) on a 1 GB instance. Make sure the host has swap configured to absorb LiteLLM startup spikes:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Raise the limits on larger VMs. LiteLLM happily uses 1-2 GB of RAM if you give it.

## Clean Up Before Switching Stack Types

If you previously tried `portainer-stack.yml` on a Swarm endpoint, a leftover bridge network like `litellm_litellm` will still exist and Swarm will refuse to attach services to it. Remove the old stack and any leftover non-overlay networks before redeploying:

1. In Portainer, delete the existing `litellm` stack (Stacks -> select stack -> Remove).
2. On the Docker host (or via Portainer "Networks" view), remove any leftover bridge networks created by the previous attempt:

```bash
docker network ls --filter "name=litellm"
docker network rm litellm_litellm || true
docker network rm litellm_overlay_net || true
```

The Swarm stack creates its overlay network as `<stack>_overlay_net` (e.g. `litellm_overlay_net`) to avoid colliding with any leftover `litellm_litellm` network from earlier standalone attempts.

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
