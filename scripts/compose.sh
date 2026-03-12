# DEVCONTAINER_JSON is injected by nix at build time (see modules/bridge.nix)
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

# Step 0: resolve compose file path from devcontainer.json
# dockerComposeFile may be a string or an array — normalise to first element.
COMPOSE_RELATIVE=$(jq -r '
  if .dockerComposeFile | type == "array" then .dockerComposeFile[0]
  else .dockerComposeFile // empty
  end' "$DEVCONTAINER_JSON")

if [ -z "$COMPOSE_RELATIVE" ]; then
  # No compose file — export containerEnv as-is, no port rewriting
  echo "[nix-devcontainer] No dockerComposeFile — exporting containerEnv as-is"
  while IFS= read -r entry; do
    VAR=$(echo "$entry" | jq -r '.key')
    VAL=$(echo "$entry" | jq -r '.value')
    declare -x "$VAR=$VAL"
    echo "  $VAR"
  done < <(jq -c '.containerEnv // {} | to_entries[]' "$DEVCONTAINER_JSON")
  return 0
fi

COMPOSE_FILE="$(realpath "$DEVCONTAINER_DIR/$COMPOSE_RELATIVE")"
# Convention: docker-compose.yml → docker-compose.nix.yml
NIX_COMPOSE_FILE="${COMPOSE_FILE%.yml}.nix.yml"

REWRITE_RULES="[]"

if [ -f "$NIX_COMPOSE_FILE" ]; then
  echo "[nix-devcontainer] Starting services with nix overlay..."
  docker compose -f "$COMPOSE_FILE" -f "$NIX_COMPOSE_FILE" up -d --quiet-pull

  # Use yq to parse the nix overlay directly — docker compose config would reject
  # the overlay as invalid (no image: field) since it only adds port bindings.
  echo "[nix-devcontainer] Host ports:"
  while IFS=$'\t' read -r SERVICE CONTAINER_PORT; do
    [ -z "$SERVICE" ] || [ -z "$CONTAINER_PORT" ] && continue
    HOST_PORT=$(_ndc_wait_for_port -f "$COMPOSE_FILE" -f "$NIX_COMPOSE_FILE" \
      port "$SERVICE" "$CONTAINER_PORT") || {
      echo "  ${SERVICE}:${CONTAINER_PORT} — timeout waiting for container (skipped)"
      continue
    }
    REWRITE_RULES=$(echo "$REWRITE_RULES" | jq \
      --arg from "${SERVICE}:${CONTAINER_PORT}" --arg to "localhost:${HOST_PORT}" \
      '. + [{from: $from, to: $to}]')
    echo "  ${SERVICE}:${CONTAINER_PORT} → localhost:${HOST_PORT}"
  done < <(yq -r '
    .services | to_entries[] |
    .key as $svc |
    .value.ports[]? |
    split(":") | last as $port |
    [$svc, $port] | @tsv
  ' "$NIX_COMPOSE_FILE")
else
  echo "[nix-devcontainer] Starting base services..."
  docker compose -f "$COMPOSE_FILE" up -d --quiet-pull
fi

# Export containerEnv from devcontainer.json with rewrite rules applied
echo "[nix-devcontainer] Exporting environment:"
while IFS= read -r entry; do
  VAR=$(echo "$entry" | jq -r '.key')
  VAL=$(echo "$entry" | jq -r '.value')
  REWRITTEN=$(echo "$VAL" | jq -r --argjson rules "$REWRITE_RULES" \
    '$rules | reduce .[] as $r (.; gsub($r.from; $r.to))')
  declare -x "$VAR=$REWRITTEN"
  if [ "$REWRITTEN" != "$VAL" ]; then
    echo "  $VAR (rewritten)"
  else
    echo "  $VAR"
  fi
done < <(jq -c '.containerEnv // {} | to_entries[]' "$DEVCONTAINER_JSON")
