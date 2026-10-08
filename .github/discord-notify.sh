#!/usr/bin/env bash
# Keeps one Discord message per addon in the addons channel: "Name - tagline", screenshots,
# and a version/links line. Uses a bot (DISCORD_BOT_TOKEN) and DISCORD_CHANNEL_ID.
#   DISCORD_MODE=sync     (manual run) create the message, or rebuild it with fresh screenshots
#   DISCORD_MODE=release  (tag push)   edit the message to the new version (creates it if missing)
# Skips quietly when not configured. Never fails the release.
set -uo pipefail
if [ -z "${DISCORD_BOT_TOKEN:-}" ] || [ -z "${DISCORD_CHANNEL_ID:-}" ]; then
  echo "DISCORD_BOT_TOKEN / DISCORD_CHANNEL_ID not set; skipping the Discord update."
  exit 0
fi

API="https://discord.com/api/v10"
AUTH="Authorization: Bot ${DISCORD_BOT_TOKEN}"
REPO="${GITHUB_REPOSITORY:-owner/addon}"
MODE="${DISCORD_MODE:-release}"
SHOTDIR=".github/discord"

TOC=$(ls ./*.toc 2>/dev/null | head -1)
NAME=""
[ -n "$TOC" ] && NAME=$(grep -m1 '^## Title:' "$TOC" | sed -E 's/^## Title:[[:space:]]*//; s/\|c[0-9a-fA-F]{8}//g; s/\|r//g; s/\r//g')
[ -z "$NAME" ] && NAME="${REPO#*/}"
TAGLINE=""
[ -f .github/discord-blurb.txt ] && TAGLINE=$(tr -d '\r' < .github/discord-blurb.txt | head -1)

WAGO=""; CURSE=""
if [ -n "$TOC" ]; then
  WAGO=$(grep -m1 '^## X-Wago-ID:' "$TOC" | sed -E 's/^## X-Wago-ID:[[:space:]]*//; s/\r//g')
  CURSE=$(grep -m1 '^## X-Curse-Project-ID:' "$TOC" | sed -E 's/^## X-Curse-Project-ID:[[:space:]]*//; s/\r//g')
fi

if [ "$MODE" = "release" ]; then TAG="${GITHUB_REF_NAME:-}"; else TAG=$(git describe --tags --abbrev=0 2>/dev/null || true); fi
LINE=""
[ -n "$TAG" ] && LINE="$TAG"
add() { if [ -n "$LINE" ]; then LINE="$LINE · $1"; else LINE="$1"; fi; }
[ -n "$WAGO" ] && add "[Wago](https://addons.wago.io/addons/${WAGO})"
[ -n "$CURSE" ] && add "[CurseForge](https://www.curseforge.com/projects/${CURSE})"
add "[GitHub](https://github.com/${REPO})"

HEAD="**${NAME}** - ${TAGLINE}"
CONTENT="${HEAD}"$'\n'"-# ${LINE}"
BASE=$(jq -n --arg c "$CONTENT" '{content:$c, flags:4, allowed_mentions:{parse:[]}}')

SHOTS=()
if [ -d "$SHOTDIR" ]; then
  while IFS= read -r f; do SHOTS+=("$f"); done < <(find "$SHOTDIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' \) | sort | head -10)
fi

call() { # method path [payload [files...]]
  local method="$1" path="$2" payload="${3:-}"; shift; shift; shift 2>/dev/null || true
  if [ "$#" -gt 0 ]; then
    local args=() i=0
    for f in "$@"; do args+=(-F "files[$i]=@$f"); i=$((i+1)); done
    curl -sS -X "$method" -H "$AUTH" -o /tmp/discord_resp.json -w '%{http_code}' -F "payload_json=$payload" "${args[@]}" "${API}${path}"
  elif [ -n "$payload" ]; then
    curl -sS -X "$method" -H "$AUTH" -H 'Content-Type: application/json' -o /tmp/discord_resp.json -w '%{http_code}' -d "$payload" "${API}${path}"
  else
    curl -sS -X "$method" -H "$AUTH" -o /tmp/discord_resp.json -w '%{http_code}' "${API}${path}"
  fi
}
fail() { echo "Discord error (HTTP $1): $(head -c 300 /tmp/discord_resp.json)"; echo "Check that the bot is in the server and can view, read history, send messages and attach files in the channel."; exit 0; }

# who am I
CODE=$(call GET /users/@me); case "$CODE" in 2*) ;; *) fail "$CODE";; esac
ME=$(jq -r '.id' /tmp/discord_resp.json)

# find this addon's message (written by this bot, starting with the bold name)
MID=""; BEFORE=""
for _ in 1 2 3 4 5; do
  CODE=$(call GET "/channels/${DISCORD_CHANNEL_ID}/messages?limit=100${BEFORE}"); case "$CODE" in 2*) ;; *) fail "$CODE";; esac
  MID=$(jq -r --arg me "$ME" --arg h "**${NAME}** - " '[.[] | select(.author.id==$me and (.content|startswith($h)))][0].id // empty' /tmp/discord_resp.json)
  [ -n "$MID" ] && break
  COUNT=$(jq 'length' /tmp/discord_resp.json)
  [ "$COUNT" -lt 100 ] && break
  BEFORE="&before=$(jq -r '.[-1].id' /tmp/discord_resp.json)"
done

withatt() {
  if [ "${#SHOTS[@]}" -gt 0 ]; then
    local ATT; ATT=$(for i in "${!SHOTS[@]}"; do jq -n --argjson i "$i" --arg n "$(basename "${SHOTS[$i]}")" '{id:$i, filename:$n}'; done | jq -s '.')
    echo "$BASE" | jq --argjson a "$ATT" '. + {attachments:$a}'
  else echo "$BASE"; fi
}

if [ -n "$MID" ]; then
  if [ "$MODE" = "sync" ]; then
    CODE=$(call PATCH "/channels/${DISCORD_CHANNEL_ID}/messages/${MID}" "$(withatt)" "${SHOTS[@]}")
  else
    CODE=$(call PATCH "/channels/${DISCORD_CHANNEL_ID}/messages/${MID}" "$BASE")   # keeps the screenshots
  fi
  case "$CODE" in 2*) echo "Updated the Discord message for ${NAME}.";; *) fail "$CODE";; esac
else
  CODE=$(call POST "/channels/${DISCORD_CHANNEL_ID}/messages" "$(withatt)" "${SHOTS[@]}")
  case "$CODE" in 2*) echo "Posted a new Discord message for ${NAME}.";; *) fail "$CODE";; esac
fi
exit 0
