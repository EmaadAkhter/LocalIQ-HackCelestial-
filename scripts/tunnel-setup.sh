#!/usr/bin/env bash
set -euo pipefail

# One-time Cloudflare Tunnel setup for localiq.tavesglobal.com and
# jenkins.tavesglobal.com.
#
# Prerequisite: `cloudflared tunnel login` (browser; pick tavesglobal.com).
#
# Mirrors ~/Developer/sih/scripts/tunnel-setup.sh. Subdomains, not the apex:
# tavesglobal.com is a live Vercel site and keeps its own A record.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CF="${CLOUDFLARED:-$HOME/.local/bin/cloudflared}"
NAME="${TUNNEL_NAME:-localiq}"
DOMAIN="${DOMAIN:-tavesglobal.com}"
CFG="$ROOT/infra/cloudflared/config.yml"
DEST="$ROOT/infra/cloudflared"

[ -f "$HOME/.cloudflared/cert.pem" ] || {
  echo "Not logged in. Run:  $CF tunnel login" >&2; exit 1; }

mkdir -p "$DEST"

"$CF" tunnel list | awk '{print $2}' | grep -qx "$NAME" || "$CF" tunnel create "$NAME"

ID=$("$CF" tunnel list --output json \
     | python3 -c "import json,sys;print(next(t['id'] for t in json.load(sys.stdin) if t['name']=='$NAME'))")
echo "tunnel $NAME = $ID"

cp "$HOME/.cloudflared/$ID.json" "$DEST/$ID.json"
chmod 600 "$DEST/$ID.json"

# Fill the placeholder on a fresh checkout, then pin credentials-file to this
# checkout's copy (absolute path; cloudflared resolves it from its own cwd).
if grep -q TUNNEL_ID "$CFG"; then
  sed -i '' "s/TUNNEL_ID/$ID/g" "$CFG"
fi
python3 - "$CFG" "$DEST/$ID.json" <<'PY'
import re, sys
cfg, creds = sys.argv[1], sys.argv[2]
text = open(cfg).read()
text = re.sub(r'^credentials-file:.*$', f'credentials-file: {creds}', text, flags=re.M)
open(cfg, 'w').write(text)
PY

"$CF" tunnel route dns --overwrite-dns "$NAME" "localiq.$DOMAIN"
"$CF" tunnel route dns --overwrite-dns "$NAME" "jenkins.$DOMAIN"

echo
echo "DNS routed:"
echo "  localiq.$DOMAIN -> tunnel $NAME"
echo "  jenkins.$DOMAIN -> tunnel $NAME"
echo "Now:  ./scripts/tunnel.sh"
