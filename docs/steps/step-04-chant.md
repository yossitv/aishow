# Step 04 — 詠唱(`aishow chant`)

## 担当領域
- `Sources/aishow/Chant/Recorder.swift`: `AVAudioEngine` で 16kHz mono、`AISHOW_MAX_RECORD_SECONDS`(既定 30)で自動停止。CLI では Enter で停止(Step 06 でホットキー離しに置換)
- `Sources/aishow/Chant/Transcriber.swift`: OpenAI `POST /v1/audio/transcriptions`(`AISHOW_STT_MODEL`、既定 `gpt-4o-transcribe`、`language=ja`)。失敗時は `whisper-1` に 1 回フォールバック。`URLSession` のみ、SDK 不使用
- CLI: `aishow chant [--file x.wav]` → 認識テキストを stdout に出す。`--file` で録音を飛ばせる(テスト用)
- 1 秒未満 / 無音は「詠唱が短すぎる」で終了コード 66

## 禁止事項
- 録音ファイルをリポジトリ配下に残さない(`recordings/` は gitignore 済み、既定は一時ディレクトリ)
- API キーをログに出さない

## 検収基準
- [ ] `aishow chant` → 日本語で話す → Enter → 認識テキストが stdout に出る
- [ ] `aishow chant --file Tests/Fixtures/audio/sample-ja.wav` が決まったテキストを返す(サンプル音声を 1 本コミット。5 秒以内・自分の声)
- [ ] `OPENAI_API_KEY` 未設定で実行 → stderr に案内、終了コード 78、クラッシュしない
- [ ] マイク権限なし → 案内を出して終了(Step 06 の .app では TCC ダイアログが出る)
