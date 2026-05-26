#!/usr/bin/env bash
# Deploy the current local project to the classmazing Netlify site.
# Requires .deploy.env with NETLIFY_TOKEN and NETLIFY_SITE_ID (gitignored).
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .deploy.env ]; then
  echo "Error: .deploy.env not found. Create it with NETLIFY_TOKEN and NETLIFY_SITE_ID." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .deploy.env
set +a

: "${NETLIFY_TOKEN:?NETLIFY_TOKEN not set in .deploy.env}"
: "${NETLIFY_SITE_ID:?NETLIFY_SITE_ID not set in .deploy.env}"

ZIP="/tmp/classmazing-deploy.zip"
rm -f "$ZIP"
zip -r "$ZIP" . -x ".git/*" ".gitignore" "*.DS_Store" "*.zip" "deploy.sh" ".deploy.env" -q

echo "Deploying $(du -h "$ZIP" | cut -f1) to classmazing.com..."

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $NETLIFY_TOKEN" \
  -H "Content-Type: application/zip" \
  --data-binary "@$ZIP" \
  "https://api.netlify.com/api/v1/sites/$NETLIFY_SITE_ID/deploys")

DEPLOY_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")

if [ -z "$DEPLOY_ID" ]; then
  echo "Deploy failed:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# Poll until ready (usually <5 seconds for small static sites)
for i in 1 2 3 4 5 6 7 8 9 10; do
  STATE=$(curl -s -H "Authorization: Bearer $NETLIFY_TOKEN" \
    "https://api.netlify.com/api/v1/sites/$NETLIFY_SITE_ID/deploys/$DEPLOY_ID" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','?'))")
  if [ "$STATE" = "ready" ]; then
    echo "Deploy $i: ready ✓"
    echo "Live at https://classmazing.com"
    exit 0
  fi
  echo "  $i: $STATE"
  sleep 2
done

echo "Deploy still processing after 20s — check https://app.netlify.com" >&2
exit 1
