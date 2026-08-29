#!/usr/bin/env bash
# TrueForge(ローカル)に Bright Data のホスト型 MCP を remote コネクタとして登録する。
# 使い方: make harness を別ターミナルで起動してから  ./scripts/register-brightdata.sh [GROUPS]
#   GROUPS 省略時は base tools のみ(search_engine / scrape_as_markdown / discover)。website_form 呪文はこれで足りる。
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && { set -a; . ./.env; set +a; }
: "${BRIGHTDATA_API_KEY:?BRIGHTDATA_API_KEY が未設定(.env を確認)}"
TF="${TRUEFORGE_URL:-http://localhost:8790}"
GROUPS_PARAM="${1:-}"
URL="https://mcp.brightdata.com/mcp?token=${BRIGHTDATA_API_KEY}"
[ -n "$GROUPS_PARAM" ] && URL="${URL}&groups=${GROUPS_PARAM}"

curl -fsS "$TF/api/v1/auth/me" >/dev/null || { echo "TrueForge に接続できません($TF)。make harness で起動してください" >&2; exit 69; }

# 既存があれば削除して作り直す(トークン更新に対応)
curl -fsS -X DELETE "$TF/api/v1/settings/mcp-servers/brightdata" >/dev/null 2>&1 || true
resp=$(curl -fsS -X POST "$TF/api/v1/settings/mcp-servers" -H "Content-Type: application/json" \
  -d "{\"manifest\":{\"name\":\"brightdata\",\"description\":\"Bright Data hosted MCP (live web data)\",\"type\":\"remote\",\"url\":\"${URL}\"}}")
# トークンを含む URL は表示しない
echo "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin).get("data",{}); print("registered:", d.get("name"), "auth:", d.get("auth_status",{}).get("status"))'
echo "次: .build/debug/aishow summon --dry-run --chant \"...\"(ensureAgent が mcp_servers=[brightdata] でエージェントを更新します)"
