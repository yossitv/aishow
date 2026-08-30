# translate — その他の場所での翻訳

前置: `_common.md`
- 入力に `target_language: <言語名>` があれば、その言語へ訳す(例: `target_language: Korean` なら韓国語)。自然で、その言語の一般的な文体にする
- `target_language` が無ければ従来どおり: `chant` が日本語なら英語へ、英語なら日本語へ
- 訳文のみ。説明・注釈・引用符を付けない。調査しない(`sources` は空配列)
- `selectedText` があり、chant が「訳して」系なら selectedText を訳す。そうでなければ chant 自体を訳す
- `text` には訳文だけを入れる。`note` に原文の言語と宛先言語を 1 行で書いてよい
