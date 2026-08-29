#!/usr/bin/env bash
# TrueForge(localhost:8790)に OpenAI プロバイダと Bright Data remote MCP を登録する(冪等)。
# 使い方: scripts/harness-setup.sh [path/to/.env]   ※ TrueForge 起動後(make harness)に実行
# 必要な .env: OPENAI_API_KEY=...、BRIGHTDATA_API_KEY=...(または旧形式の "#…token=<key>" 行)
set -euo pipefail
ENV_FILE="${1:-.env}"
B="${TRUEFORGE_URL:-http://localhost:8790}/api/v1"

[ -f "$ENV_FILE" ] || { echo "no .env at $ENV_FILE" >&2; exit 64; }
OPENAI_API_KEY=$(grep -E '^OPENAI_API_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"'"'"' ')
BRIGHTDATA_API_KEY=$(grep -E '^BRIGHTDATA_API_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"'"'"' ' || true)
[ -n "$BRIGHTDATA_API_KEY" ] || BRIGHTDATA_API_KEY=$(grep -o 'token=[^&[:space:]]*' "$ENV_FILE" | head -1 | cut -d= -f2 || true)
[ -n "$OPENAI_API_KEY" ] || { echo "OPENAI_API_KEY missing in $ENV_FILE" >&2; exit 64; }

curl -sf -m 5 "$B/auth/me" >/dev/null || { echo "TrueForge not reachable at $B (make harness)" >&2; exit 69; }

# 1. OpenAI provider(PUT = create or replace)
curl -sf -X PUT "$B/settings/model-providers" -H "Content-Type: application/json" -d @- >/dev/null <<JSON
{"manifest":{"type":"openai","auth":{"api_key":"$OPENAI_API_KEY"},
 "models":[{"name":"gpt-5.2","model_id":"gpt-5.2","properties":{}},
           {"name":"gpt-5","model_id":"gpt-5","properties":{}},
           {"name":"gpt-4.1","model_id":"gpt-4.1","properties":{}}]}}
JSON
echo "✔ model provider: openai (gpt-5.2 / gpt-5 / gpt-4.1)"

# 2. Bright Data hosted MCP(remote 専用。stdio は TrueForge が受け付けない)
if [ -n "$BRIGHTDATA_API_KEY" ]; then
  if curl -sf -m 5 "$B/settings/mcp-servers/brightdata" >/dev/null 2>&1; then
    echo "✔ mcp server: brightdata (already registered)"
  else
    curl -sf -X POST "$B/settings/mcp-servers" -H "Content-Type: application/json" -d @- >/dev/null <<JSON
{"manifest":{"name":"brightdata","description":"Bright Data Web MCP (hosted)","type":"remote",
 "url":"https://mcp.brightdata.com/mcp?token=$BRIGHTDATA_API_KEY"}}
JSON
    echo "✔ mcp server: brightdata (registered)"
  fi
  echo -n "  tools: "; curl -sf -m 60 "$B/mcp-servers/brightdata/tools" | python3 -c "import sys,json; print(', '.join(t['name'] for t in json.load(sys.stdin)['data']))"
else
  echo "⚠ BRIGHTDATA_API_KEY not found — skipping Bright Data MCP (website_form 呪文の千里眼が使えません)"
fi
echo "done. next: .build/debug/aishow summon --dry-run"
