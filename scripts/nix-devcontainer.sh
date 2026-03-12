DEVCONTAINER_JSON="$1"
DEVCONTAINER_DIR="$(dirname "$DEVCONTAINER_JSON")"

# Wait up to 30 seconds for a container port to be mapped and return the host port.
# docker compose port only succeeds once the container is running.
_ndc_wait_for_port() {
  local compose_args=("$@")
  local retries=30
  local port=""
  while [ "$retries" -gt 0 ]; do
    port=$(docker compose "${compose_args[@]}" 2>/dev/null | cut -d: -f2)
    if [ -n "$port" ]; then
      echo "$port"
      return 0
    fi
    retries=$((retries - 1))
    sleep 1
  done
  return 1
}

# Resolve compose file path from devcontainer.json.
# dockerComposeFile may be a string or an array — normalise to first element.
COMPOSE_RELATIVE=$(jq -r '
  if .dockerComposeFile | type == "array" then .dockerComposeFile[0]
  else .dockerComposeFile // empty
  end' "$DEVCONTAINER_JSON")

if [ -z "$COMPOSE_RELATIVE" ]; then
  # No compose file — emit containerEnv as-is, no port rewriting
  echo "[nix-devcontainer] No dockerComposeFile — exporting containerEnv as-is" >&2
  while IFS= read -r entry; do
    VAR=$(echo "$entry" | jq -r '.key')
    VAL=$(echo "$entry" | jq -r '.value')
    printf 'export %s=%q\n' "$VAR" "$VAL"
    echo "  $VAR" >&2
  done < <(jq -c '.containerEnv // {} | to_entries[]' "$DEVCONTAINER_JSON")
  exit 0
fi

COMPOSE_FILE="$(realpath "$DEVCONTAINER_DIR/$COMPOSE_RELATIVE")"
# Convention: docker-compose.yml → docker-compose.nix.yml
NIX_COMPOSE_FILE="${COMPOSE_FILE%.yml}.nix.yml"

REWRITE_RULES="[]"

if [ -f "$NIX_COMPOSE_FILE" ]; then
  echo "[nix-devcontainer] Starting services with nix overlay..." >&2
  docker compose -f "$COMPOSE_FILE" -f "$NIX_COMPOSE_FILE" up -d --quiet-pull >&2

  # Use yq to parse the nix overlay directly — docker compose config rejects
  # overlay-only files that have no image: field.
  echo "[nix-devcontainer] Host ports:" >&2
  while IFS=$'\t' read -r SERVICE CONTAINER_PORT; do
    [ -z "$SERVICE" ] || [ -z "$CONTAINER_PORT" ] && continue
    HOST_PORT=$(_ndc_wait_for_port -f "$COMPOSE_FILE" -f "$NIX_COMPOSE_FILE" \
      port "$SERVICE" "$CONTAINER_PORT") || {
      echo "  ${SERVICE}:${CONTAINER_PORT} — timeout waiting for container (skipped)" >&2
      continue
    }
    REWRITE_RULES=$(echo "$REWRITE_RULES" | jq \
      --arg from "${SERVICE}:${CONTAINER_PORT}" --arg to "localhost:${HOST_PORT}" \
      '. + [{from: $from, to: $to}]')
    echo "  ${SERVICE}:${CONTAINER_PORT} → localhost:${HOST_PORT}" >&2
  done < <(yq -r '
    .services | to_entries[] |
    .key as $svc |
    .value.ports[]? |
    split(":") | last as $port |
    [$svc, $port] | @tsv
  ' "$NIX_COMPOSE_FILE")
else
  echo "[nix-devcontainer] Starting base services..." >&2
  docker compose -f "$COMPOSE_FILE" up -d --quiet-pull >&2
fi

# Emit containerEnv from devcontainer.json with rewrite rules applied.
# stdout only — captured by eval in the shellHook.
echo "[nix-devcontainer] Exporting environment:" >&2
while IFS= read -r entry; do
  VAR=$(echo "$entry" | jq -r '.key')
  VAL=$(echo "$entry" | jq -r '.value')
  REWRITTEN=$(echo "$VAL" | jq -r --argjson rules "$REWRITE_RULES" \
    '$rules | reduce .[] as $r (.; gsub($r.from; $r.to))')
  printf 'export %s=%q\n' "$VAR" "$REWRITTEN"
  if [ "$REWRITTEN" != "$VAL" ]; then
    echo "  $VAR (rewritten)" >&2
  else
    echo "  $VAR" >&2
  fi
done < <(jq -c '.containerEnv // {} | to_entries[]' "$DEVCONTAINER_JSON")
