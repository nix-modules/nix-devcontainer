# nix-devcontainer

A [flake-parts](https://flake.parts) module that bridges your existing `devcontainer.json` + Docker Compose setup into a local `nix develop` shell.

Think of it as `devpod up + devpod ssh` — but for nix:
- `devpod up` → `docker compose up` (services start automatically on `nix develop`)
- `devpod ssh` → you are already in your local nix shell, environment bridged in

No SSH, no container exec. You work natively. Services are just available at `$DATABASE_URL`.

---

## The problem it solves

Teams where some developers use `nix develop` locally and others use VS Code devcontainers have no clean way to share their environment without maintaining two separate setups.

**nix-devcontainer** reads the files you already have:

```
docker-compose.yml          ← devcontainer infrastructure (no host ports)
docker-compose.nix.yml      ← nix developer overlay (adds host port bindings)
devcontainer.json           ← VS Code / Codespaces config
flake.nix                   ← packages only
```

**VS Code colleague**: opens repo → Reopen in Container → nix feature installs packages from flake → full dev env.

**Nix developer**: `nix develop` → compose services start with random host ports → ports discovered → `DATABASE_URL` rewritten to `localhost:XXXXX` → packages available.

Both connect to the same postgres instance.

---

## Quick start

### 1. Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-devcontainer.url = "github:nix-modules/nix-devcontainer";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.nix-devcontainer.flakeModule ];
    systems = [ "x86_64-linux" "aarch64-darwin" ];

    perSystem = { pkgs, ... }: {
      nix-devcontainer = {
        enable = true;
        file = toString ./.devcontainer/devcontainer.json;
        packages = [ pkgs.nodejs_20 pkgs.postgresql pkgs.redis ];
      };
    };
  };
}
```

### 2. Create the nix overlay compose file

Next to your existing `docker-compose.yml`, create `docker-compose.nix.yml`:

```yaml
# Only adds host port bindings. Everything else is inherited from docker-compose.yml.
services:
  postgresql:
    ports:
      - "0:5432"   # 0 = random host port, no conflicts between projects

  redis:
    ports:
      - "0:6379"
```

### 3. nix develop

```
$ nix develop

[nix-devcontainer] Starting services with nix overlay...
[nix-devcontainer] Host ports:
  postgresql:5432 → localhost:32768
  redis:6379      → localhost:41293
[nix-devcontainer] Exporting environment:
  DATABASE_URL (rewritten)
  REDIS_URL (rewritten)
  NODE_ENV
[nix-devcontainer] Environment ready

$ echo $DATABASE_URL
postgresql://dev:dev@localhost:32768/mydb

$ psql "$DATABASE_URL"    # works, no port conflict possible
```

---

## How it works

### File layout

```
.devcontainer/
  devcontainer.json           ← VS Code config, declares dockerComposeFile and containerEnv
  docker-compose.yml          ← base infrastructure, no host ports
  docker-compose.nix.yml      ← nix overlay, adds host port bindings only
flake.nix                     ← imports nix-devcontainer module, declares packages
```

The `.nix.yml` file is the convention: `<name>.yml` → `<name>.nix.yml`. If `dockerComposeFile` in `devcontainer.json` points to `../docker-compose.yml`, the nix overlay is `../docker-compose.nix.yml`.

### What the module does

1. Reads `dockerComposeFile` from `devcontainer.json` to find the base compose file
2. Looks for `<compose-file>.nix.yml` alongside it
3. Runs `docker compose -f base.yml -f base.nix.yml up -d` to start services
4. Queries actual host ports with `docker compose port`
5. Builds rewrite rules: `serviceName:containerPort → localhost:hostPort`
6. Reads `containerEnv` from `devcontainer.json`, applies rewrites, exports to shell

### Docker Compose file merge

When `-f base.yml -f nix.yml` is used, Docker Compose merges them:
- **Lists append** — `ports:` in the nix overlay is added to the service
- **Mappings merge** — `environment:`, `volumes:`, etc. from the base are preserved

The nix overlay only needs to declare the fields it adds. Image, environment, and volumes are inherited automatically.

### Dynamic host ports

`"0:5432"` tells Docker to assign a random host port. This means:
- No hardcoded ports in any config file
- No conflicts when multiple projects are open simultaneously
- Each `nix develop` session gets its own isolated set of ports

### containerEnv rewriting

`devcontainer.json` declares service hostnames that work inside the compose network:

```json
"containerEnv": {
  "DATABASE_URL": "postgresql://dev:dev@postgresql:5432/mydb"
}
```

nix-devcontainer rewrites `postgresql:5432` → `localhost:32768` (actual host port) before exporting. Your `$DATABASE_URL` is correct everywhere — inside the container and in your local shell.

---

## Module options

```nix
nix-devcontainer = {
  enable = true;

  # Path to devcontainer.json (resolved at eval time)
  file = ./.devcontainer/devcontainer.json;

  # Packages for the local nix shell
  # Mirror what the container gets via ghcr.io/devcontainers/features/nix:1
  packages = [ pkgs.nodejs_20 pkgs.postgresql ];

  # Local-only env vars — not in devcontainer.json, not in compose
  # Useful for API keys, machine-specific overrides
  localEnv = {
    SOME_SECRET = "...";
  };
};
```

### No compose file

If `devcontainer.json` has no `dockerComposeFile`, the module exports `containerEnv` as-is without any port rewriting. Useful for environment-only devcontainers.

---

## VS Code / Codespaces integration

`devcontainer.json` references only `docker-compose.yml`. The `docker-compose.nix.yml` file is invisible to VS Code users — they never see it.

To install packages in the devcontainer, add the nix feature:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/nix:1": {
      "version": "latest",
      "flakeUri": "."
    }
  }
}
```

This installs the same packages that `nix-devcontainer.packages` provides to local developers.

---

## Exposed flake outputs

| Output | Description |
|--------|-------------|
| `devShells.default` | Enter shell: services start, env bridged |
| `packages.nix-devcontainer-bridge` | Bridge script as a runnable nix package (`nix run`) |

---

## Examples

- [`examples/basic/`](examples/basic/) — single Redis service, minimal setup
- [`examples/nodejs-postgres/`](examples/nodejs-postgres/) — Node.js app with PostgreSQL and Redis
- [`examples/golang-postgres/`](examples/golang-postgres/) — Go app with PostgreSQL, psql client, and golang-migrate
