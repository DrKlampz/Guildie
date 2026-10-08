#!/usr/bin/env bash
# Posts a release card (or an intro card) to Discord. Skips quietly when no webhook is set.
set -uo pipefail
if [ -z "${DISCORD_WEBHOOK:-}" ]; then
  echo "DISCORD_WEBHOOK is not set; skipping the Discord post."
  exit 0
fi

REPO="${GITHUB_REPOSITORY:-repo/addon}"
TOC=$(ls ./*.toc 2>/dev/null | head -1)
NAME=""
[ -n "$TOC" ] && NAME=$(grep -m1 '^## Title:' "$TOC" | sed -E 's/^## Title:[[:space:]]*//; s/\|c[0-9a-fA-F]{8}//g; s/\|r//g; s/\r//g')
[ -z "$NAME" ] && NAME="${REPO#*/}"
BLURB=""
[ -f .github/discord-blurb.txt ] && BLURB=$(tr -d '\r' < .github/discord-blurb.txt)

WAGO=""; CURSE=""
if [ -n "$TOC" ]; then
  WAGO=$(grep -m1 '^## X-Wago-ID:' "$TOC" | sed -E 's/^## X-Wago-ID:[[:space:]]*//; s/\r//g')
  CURSE=$(grep -m1 '^## X-Curse-Project-ID:' "$TOC" | sed -E 's/^## X-Curse-Project-ID:[[:space:]]*//; s/\r//g')
fi

MODE="${DISCORD_MODE:-release}"
TAG="${GITHUB_REF_NAME:-}"
LINKS="[GitHub](https://github.com/${REPO})"
if [ "$MODE" = "release" ] && [ -n "$TAG" ]; then
  LINKS="[Release notes](https://github.com/${REPO}/releases/tag/${TAG}) · [GitHub](https://github.com/${REPO})"
fi
[ -n "$WAGO" ] && LINKS="$LINKS · [Wago](https://addons.wago.io/addons/${WAGO})"
[ -n "$CURSE" ] && LINKS="$LINKS · [CurseForge](https://www.curseforge.com/projects/${CURSE})"

if [ "$MODE" = "intro" ]; then
  TITLE="$NAME"
  DESC="$BLURB"
else
  VER="${TAG#v}"
  TITLE="$NAME $TAG is out"
  NOTES=""
  if [ -f CHANGELOG.md ]; then
    NOTES=$(tr -d '\r' < CHANGELOG.md | awk -v v="$VER" '
      /^## / { if (found) exit; h=$0; sub(/^## +v?/, "", h); sub(/[ ].*$/, "", h); if (h == v) { found=1; next } }
      found { print }' | sed '/^[[:space:]]*$/d' | cut -c1-400 | head -c 1500)
  fi
  DESC="$NOTES"
  [ -z "$DESC" ] && DESC="A new version is available."
fi

PAYLOAD=$(jq -n \
  --arg title "$TITLE" --arg desc "$DESC" --arg blurb "$BLURB" --arg links "$LINKS" --arg mode "$MODE" \
  '{username:"Addon Updates", embeds:[{
      title:$title, description:$desc, color:14725194,
      fields: ( [ (if $mode=="release" and $blurb!="" then {name:"What it is", value:$blurb} else empty end),
                  {name:"Get it", value:$links} ] )
  }]}')

CODE=$(curl -sS -o /tmp/discord_resp.txt -w '%{http_code}' -H 'Content-Type: application/json' -d "$PAYLOAD" "$DISCORD_WEBHOOK")
case "$CODE" in
  2*) echo "Posted to Discord ($CODE)." ;;
  *) echo "Discord post failed ($CODE): $(head -c 300 /tmp/discord_resp.txt)" ;;
esac
exit 0
