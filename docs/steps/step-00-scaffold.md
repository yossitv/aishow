# Step 00 — 骨組み

## 担当領域
- リポジトリ設定: `.gitignore`, `.env.example`, `LICENSE`(MIT), `.pr_agent.toml`, `CLAUDE.md`, `README.md`
- Swift Package: `AishowCore`(純粋ロジック)/ `aishow`(CLI)/ `AishowCoreTests`
- `Makefile`(build / test / run / app / harness)、`scripts/Info.plist.template`
- `docs/steps/`(本発注書群)、`harness/`(TrueForge 設定手順と呪文)

## 禁止事項
- 機能実装をしない(データ型と CLI の空殻まで)
- 外部依存パッケージを追加しない

## 検収基準
- [x] `swift build` が通る
- [x] `swift test` が通る(ContextPack の JSON 往復、Workflow の rawValue と呪文ファイル名の一致)
- [x] `.build/debug/aishow version` が `aishow 0.0.1` を出す
- [x] `git status` に `.env` / `.build/` / `dist/` が現れない
- [ ] GitHub リポジトリ public、Qodo GitHub App インストール済み(手動)
