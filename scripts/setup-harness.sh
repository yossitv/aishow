#!/usr/bin/env bash
# TrueForge(ローカル)に OpenAI モデルプロバイダと Bright Data ホスト型 MCP を登録する(冪等)。
# 使い方: make harness を別ターミナルで起動してから  ./scripts/setup-harness.sh [GROUPS]
#   GROUPS 省略時は Bright Data の base tools のみ(search_engine / scrape_as_markdown / discover)。
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && { set -a; . ./.env; set +a; }
: "${OPENAI_API_KEY:?OPENAI_API_KEY が未設定(.env を確認)}"
: "${BRIGHTDATA_API_KEY:?BRIGHTDATA_API_KEY が未設定(.env を確認)}"
TF="${TRUEFORGE_URL:-http://localhost:8790}"
MODEL="${AISHOW_MODEL:-gpt-5.2}"
GROUPS_PARAM="${1:-}"

curl -fsS "$TF/api/v1/auth/me" >/dev/null || { echo "TrueForge に接続できません($TF)。make harness で起動してください" >&2; exit 69; }

# --- OpenAI provider(既存なら再登録しない)---
if curl -fsS "$TF/api/v1/settings/model-providers" | python3 -c 'import sys,json; d=json.load(sys.stdin); items=d.get("data",d) if isinstance(d,dict) else d; sys.exit(0 if any((i.get("manifest",i).get("type")=="openai") for i in items) else 1)' 2>/dev/null; then
  echo "openai provider: already registered"
else
  curl -fsS -X POST "$TF/api/v1/settings/model-providers" -H "Content-Type: application/json" \
    -d "{\"manifest\":{\"type\":\"openai\",\"auth\":{\"api_key\":\"${OPENAI_API_KEY}\"},\"models\":[{\"name\":\"${MODEL}\",\"model_id\":\"${MODEL}\",\"properties\":{}},{\"name\":\"gpt-4.1\",\"model_id\":\"gpt-4.1\",\"properties\":{}}]}}" >/dev/null
  echo "openai provider: registered (${MODEL}, gpt-4.1)"
fi

# --- Bright Data remote MCP(トークン更新に備えて作り直す)---
URL="https://mcp.brightdata.com/mcp?token=${BRIGHTDATA_API_KEY}"
[ -n "$GROUPS_PARAM" ] && URL="${URL}&groups=${GROUPS_PARAM}"
curl -fsS -X DELETE "$TF/api/v1/settings/mcp-servers/brightdata" >/dev/null 2>&1 || true
resp=$(curl -fsS -X POST "$TF/api/v1/settings/mcp-servers" -H "Content-Type: application/json" \
  -d "{\"manifest\":{\"name\":\"brightdata\",\"description\":\"Bright Data hosted MCP (live web data)\",\"type\":\"remote\",\"url\":\"${URL}\"}}")
echo "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin).get("data",{}); print("brightdata mcp:", d.get("name"), "auth:", d.get("auth_status",{}).get("status"))'
echo "OK. 次: .build/debug/aishow summon --dry-run --chant \"...\""
