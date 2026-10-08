#!/usr/bin/env bash
# Keeps one Discord message per addon: "Name - tagline", screenshots, and a version/links line.
#   DISCORD_MODE=sync     (manual run) create the message, or rebuild it with fresh screenshots
#   DISCORD_MODE=release  (tag push)   edit the existing message to the new version
# Skips quietly when no webhook is set. Never fails the release.
set -uo pipefail
if [ -z "${DISCORD_WEBHOOK:-}" ]; then
  echo "DISCORD_WEBHOOK is not set; skipping the Discord update."
  exit 0
fi

REPO="${GITHUB_REPOSITORY:-owner/addon}"
MODE="${DISCORD_MODE:-release}"
IDFILE=".github/discord-message-id"
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

CONTENT="**${NAME}** - ${TAGLINE}"$'\n'"-# ${LINE}"
BASE=$(jq -n --arg c "$CONTENT" '{content:$c, flags:4, allowed_mentions:{parse:[]}}')

SHOTS=()
if [ -d "$SHOTDIR" ]; then
  while IFS= read -r f; do SHOTS+=("$f"); done < <(find "$SHOTDIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' \) | sort | head -10)
fi

ID=""
[ -f "$IDFILE" ] && ID=$(tr -d '\r\n ' < "$IDFILE")
BASEURL="${DISCORD_WEBHOOK%%\?*}"

send() { # method url payload [files...]
  local method="$1" url="$2" payload="$3"; shift 3
  if [ "$#" -gt 0 ]; then
    local args=() i=0
    for f in "$@"; do args+=(-F "files[$i]=@$f"); i=$((i+1)); done
    curl -sS -X "$method" -o /tmp/discord_resp.json -w '%{http_code}' -F "payload_json=$payload" "${args[@]}" "$url"
  else
    curl -sS -X "$method" -o /tmp/discord_resp.json -w '%{http_code}' -H 'Content-Type: application/json' -d "$payload" "$url"
  fi
}

if [ "$MODE" = "release" ]; then
  if [ -z "$ID" ]; then
    echo "No Discord message exists for this addon yet. Run the 'Release' workflow by hand once to create it."
    exit 0
  fi
  CODE=$(send PATCH "${BASEURL}/messages/${ID}" "$BASE")
  echo "Discord message edit: HTTP $CODE"
  case "$CODE" in 2*) ;; *) head -c 300 /tmp/discord_resp.json; echo ;; esac
  exit 0
fi

# sync mode
PAYLOAD="$BASE"
if [ "${#SHOTS[@]}" -gt 0 ]; then
  ATT=$(for i in "${!SHOTS[@]}"; do jq -n --argjson i "$i" --arg n "$(basename "${SHOTS[$i]}")" '{id:$i, filename:$n}'; done | jq -s '.')
  PAYLOAD=$(echo "$BASE" | jq --argjson a "$ATT" '. + {attachments:$a}')
fi
if [ -n "$ID" ]; then
  CODE=$(send PATCH "${BASEURL}/messages/${ID}" "$PAYLOAD" "${SHOTS[@]}")
  echo "Discord message rebuilt: HTTP $CODE"
else
  CODE=$(send POST "${BASEURL}?wait=true" "$PAYLOAD" "${SHOTS[@]}")
  echo "Discord message created: HTTP $CODE"
  case "$CODE" in
    2*) jq -r '.id' /tmp/discord_resp.json > "$IDFILE" ;;
  esac
fi
case "$CODE" in 2*) ;; *) head -c 300 /tmp/discord_resp.json; echo ;; esac
exit 0
