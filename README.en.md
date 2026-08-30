# Aishow (詠唱)

> Say it, and the agent appears.

Aishow is a voice-summoned AI agent for macOS. Open a company's contact form, hold the **⌘ key**, and say in Japanese what you want. A local **TrueForge** agent is summoned, figures out which site you are on, researches the company live through **Bright Data**, and writes a short English message in your voice — with the sources it used. **Nothing touches your clipboard or the page until you approve.** After approval the text is pasted at your cursor. It never clicks Send. That stays human.

Built solo in one day for the **Agent Harness Hackathon** (WeMakeDevs × TrueFoundry × Qodo × Bright Data, San Francisco, 2026-08-29).

**Qodo proof (Best Code Quality track):** every step shipped as a PR reviewed by Qodo before merge. [PR #5](https://github.com/yossitv/aishow/pull/5) flagged the High-severity *"Streamed proposal content discarded"* bug that would have killed the demo; it was fixed in [PR #7](https://github.com/yossitv/aishow/pull/7) together with the other High findings from [#2](https://github.com/yossitv/aishow/pull/2)–[#6](https://github.com/yossitv/aishow/pull/6). Full list in [Development process](#development-process).

日本語版 README は [README.ja.md](README.ja.md)。

```
hotkey + voice ─▶ scan what's in front of you ─▶ detect the workflow ─▶ TrueForge agent (local)
                                                                              │
                        ┌─────────────────────────────────────────────────────┼───────────────────────┐
                        ▼                                                     ▼                       ▼
                 website_form (contact / demo / sales)               linkedin_dm · casual_en       translate
                 Bright Data MCP researches the site                 email_en
                 → OpenAI writes a cold message with sources
                 → approval gate → paste at cursor (no Send)
```

## Why

As a Japanese engineer at a US startup, every cold outreach through a company's website form cost me ~15 minutes: research the company, draft in English, fix the translation, paste. And most cold DMs that land in *my* inbox are lazy, unresearched spam — I refuse to send those. I wanted an agent that researches first, writes in my voice, shows me its sources, and asks before the one irreversible step.

## How it works

Every run goes through six stages. Their in-app names come from the summoning metaphor the UI uses.

| # | Stage | Name in UI | What happens |
|---|---|---|---|
| 1 | **Scan** | 索敵 | The instant the hotkey goes down — *before* any Aishow UI appears — the app captures the frontmost app, window title, browser URL and page title, the selected text, and whether a form `<textarea>` / focused input exists. |
| 2 | **Detect** | 呪文書 (Spellbook) | A pure, fixture-tested function `detect()` maps that context to one of five workflows (see [Workflow detection](#workflow-detection)). No LLM involved; it is instant and deterministic. |
| 3 | **Chant** | 詠唱 | Push-to-talk recording (16 kHz mono WAV) → OpenAI `gpt-4o-transcribe` (`language: ja`, fallback `whisper-1`). |
| 4 | **Summon** | 召喚 | The workflow name, the context pack (JSON) and the transcript are sent as a turn to a **TrueForge** session (one persistent session per target domain). The agent calls **Bright Data MCP** tools to research the site and returns `{sources, text, note}`. The SSE event stream drives a live *now / waiting / done* status line. |
| 5 | **Pact** | 契約 | Approval gate. Shows the workflow (`website_form @ acme.com`), the cited source URLs, the editable message, the paste target, and a warning if the frontmost app changed since the scan. Approve · edit & approve · reject (with a reason that is sent back to the same session for regeneration, up to 2 retries). |
| 6 | **Cast** | 発動 | Save clipboard → write text → activate target app → verify it is frontmost → `⌘V` → restore clipboard after 300 ms. **Never sends Enter/Return.** Appends a line to `~/.aishow/log.jsonl` (app, window, character count — never the text itself). |

### Where each sponsor tool does real work

| Tool | Role in Aishow |
|---|---|
| **TrueForge** (TrueFoundry) | The agent runtime — not a wrapper around a chat call. Aishow creates/updates a saved agent `aishow` over the HTTP API (`/api/v1/agents`) with instructions assembled from `harness/spells/*.md`, model `openai/gpt-5.2`, and the `brightdata` MCP server attached. One **session per target domain** is persisted in `~/.aishow/sessions.json` so re-casting on the same company continues the conversation server-side (sessions survive app restarts and are revalidated on 404). The client consumes the **SSE turn stream** (`turn.created`, `model.message.delta`, `model.message`, `tool.response`, `tool.approval_required`, `turn.done`) for live status. TrueForge spawned a **sub-agent** for the research and offloaded oversized tool responses automatically. The wire protocol was reverse-engineered from a live instance and `/api/v1/openapi.json` and documented in [`harness/trueforge-api.md`](harness/trueforge-api.md). |
| **Bright Data** | The agent's "far sight" (千里眼). Bright Data's hosted Web MCP (`https://mcp.brightdata.com/mcp`) is registered in TrueForge as a remote MCP server by `scripts/setup-harness.sh`. The `website_form` spell has the agent call `scrape_as_markdown` on `/`, `/about`, `/products`, `/blog|/news` and `search_engine` for `"{domain}" news 2026`, then cite at least one concrete fact with its URL. If the site yields nothing, the agent must say so (`note`) and return an empty `text` — it is not allowed to send an unresearched message. Scraper configuration (what to fetch per workflow, what never to fetch — no login walls, no paywalls, no personal data — and the pinned `bdata scraper run/heal/approve` usage) is versioned in [`CLAUDE.md`](CLAUDE.md). |
| **Qodo** | Every step = one branch = one PR = `/agentic_review` before merge. [`.pr_agent.toml`](.pr_agent.toml) encodes project rules: irreversible actions (paste, send, scraper approve) must sit behind an approval gate; no secrets in code; clipboard must be restored on every failure path; OS-level actions must re-check the frontmost app; `detect()` must stay a pure, fixture-tested function. All High findings were fixed before merge. |
| **OpenAI** | Reasoning and generation (through TrueForge, `gpt-5.2`) and speech-to-text (`gpt-4o-transcribe`). Aishow never calls OpenAI directly for generation — that goes through the harness by design; STT is the one exception. |

## Quick start

**Requirements:** macOS 14+, Swift 5.10 toolchain (Xcode 15.3+), Node.js 22.14+ (for TrueForge), an OpenAI API key, a Bright Data API key.

```bash
# 1. Secrets (read from the environment or a .env file; never committed)
cat > .env <<'EOF'
OPENAI_API_KEY=sk-...
BRIGHTDATA_API_KEY=...
EOF

# 2. Start the harness in a separate terminal (TrueForge, SQLite, no auth) → http://localhost:8790
make harness

# 3. Register the OpenAI model provider and Bright Data's hosted MCP in TrueForge (idempotent)
./scripts/setup-harness.sh            # optional arg: Bright Data tool GROUPS, e.g. ./scripts/setup-harness.sh code

# 4. Build and test
swift build && swift test

# 5. Run the menu-bar app (hold ⌘ and speak)
make app && open dist/Aishow.app      # or `make install` → ~/Applications/Aishow.app with persistent permissions
```

On first launch macOS asks for **Microphone**, **Accessibility** (global hotkey, ⌘C/⌘V synthesis) and **Automation** (AppleScript to read browser URLs). The menu-bar *Status…* panel shows which are missing and deep-links to the right System Settings pane. Hotkey monitoring starts automatically once Accessibility is granted (2 s polling) — no restart needed.

The `aishow` agent is created/updated in TrueForge automatically on the first `summon`, from `harness/spells/*.md`.

### Try it step by step from the CLI

Each stage is a subcommand so you can verify one thing at a time.

```bash
.build/debug/aishow scan                                       # Scan + Detect → JSON {pack, site}
.build/debug/aishow chant                                      # record until Enter → Japanese transcript
.build/debug/aishow chant --file Tests/Fixtures/audio/sample-ja.wav
echo "hello" | .build/debug/aishow cast --app com.apple.TextEdit  # paste (use only with approved text)
.build/debug/aishow summon --chant "この会社に、うちの音声SDKの話でコールドメッセージ"   # full pipeline, approval y/e/n
.build/debug/aishow summon --dry-run --chant "..."             # stop at the proposal, never paste
.build/debug/aishow flame --seconds 4                          # preview the recording flame border
.build/debug/aishow version
```

Exit codes: `64` usage, `65` target app not frontmost, `66` chant too short (< 1 s), `69` TrueForge unreachable, `77` permission missing, `78` `OPENAI_API_KEY` missing.

## The menu-bar app

`Aishow.app` is a menu-bar–only app (`LSUIElement`, wand icon, no Dock icon).

- **Hotkey** — default **hold ⌘** (either Command key, held alone for 0.35 s), push-to-talk. Settings also offer right-⌘ only, **Fn (🌐) long-press** (requires "Press 🌐 key: Do Nothing" in System Settings), `Option+Space`, or `Control+Option+Space`. Stored in `UserDefaults` `hotKeyModifiers` (`cmd` · `rcmd` · `lcmd` · `fn` · `option` · `control+option`).
- **Flame border** (焔) — while you are speaking, the edges of every screen are wrapped in animated fire (`CAEmitterLayer`, click-through, non-activating). Respects *Reduce Motion* (static glow) and can be turned off from the menu or `defaults write com.openhome.aishow flameOverlayEnabled -bool false`.
- **HUD** — a floating panel shows the pipeline in real time: `now` (e.g. `scrape_as_markdown …`), `waiting` (nothing / your approval), `done` (last completed step with time). `×` cancels, `⏎` approves.
- **Approval popover** — sources, editable text, paste target, and a stale-target guard: if the frontmost app is no longer the one you scanned, the button changes to *Paste anyway* and needs a second click.
- **Settings** — UI language (English / 日本語, live switch), hotkey, translate target language (auto or 15 languages, passed to the `translate` spell as `target_language`), and **microphone device** (pin the built-in mic so AirPods don't drop to the HFP profile while recording).
- **Liquid Glass** — all panels use `glassEffect` on macOS 26+ and fall back to `ultraThinMaterial` on macOS 14–15; honours *Reduce Transparency*.

Set `AISHOW_STUB=1` to run the app against a stub summoner (1 s delay, fixed text) when you want to test the UI without TrueForge.

## Workflow detection

`detect()` in `Sources/AishowCore/Detect.swift` evaluates these rules top-down; first match wins. Raw values equal the spell file names in `harness/spells/` (asserted by a test).

| Condition | `site.kind` | Workflow (spell) |
|---|---|---|
| host is `linkedin.com` (exact or subdomain) and path starts with `/in/` or `/messaging/` | `linkedin` | `linkedin_dm` |
| app is Slack / Discord / Microsoft Teams / Messages | `chat` | `casual_en` |
| app is Mail, or host is `mail.google.com` | `mail` | `email_en` |
| browser (Chrome, Arc, Brave, Edge, Safari, Chromium, Vivaldi, Firefox) **and** URL path contains `contact` · `inquiry` · `get-in-touch` · `demo` · `sales` · `support` · `talk-to`, **or** the page has `<form textarea>` | `website_form` | `website_form` |
| any other browser page | `browser` | `translate` |
| anything else | `general` | `translate` |

A spoofed host such as `evil-linkedin.com` is explicitly rejected by a test. Fixtures live in `Tests/Fixtures/context/*.json`.

## Safety invariants

These are enforced in code and in the Qodo review rules:

1. **Irreversible actions only after approval.** `cast` receives approved text only; the agent is instructed to return JSON, never to paste.
2. **Never Send.** No Enter/Return keystroke is ever synthesized. Submitting the form is the human's job.
3. **Clipboard always restored**, including on every failure path.
4. **Scan before showing UI**, so the frontmost app is the one the user was actually in; re-verified at approval and again before `⌘V`.
5. **Secrets only in env / `.env`**, never logged. The cast log stores character counts, not text.
6. **Research or refuse.** The `website_form` spell requires at least one cited fact; if the site cannot be researched the agent returns an empty message with a note instead of a generic one.
7. **Generation goes through the harness.** The Swift side does I/O and routing only; it never bypasses TrueForge to call the model directly (STT excepted).

## Configuration

Environment variables (from the process environment, else a `.env` found in `$AISHOW_HOME`, the cwd, `~/.aishow/`, the repo root relative to the binary, or `~/Documents/GitHub/aishow`):

| Variable | Default | Purpose |
|---|---|---|
| `OPENAI_API_KEY` | — | Speech-to-text (required for `chant`) |
| `BRIGHTDATA_API_KEY` | — | Used by `scripts/setup-harness.sh` to register the hosted MCP |
| `TRUEFORGE_URL` | `http://localhost:8790` | Harness base URL |
| `TRUEFORGE_TOKEN` | — | Optional bearer token (not needed locally) |
| `AISHOW_MODEL` | `openai/gpt-5.2` | Model name in the agent manifest |
| `AISHOW_MCP_SERVERS` | `brightdata` | Comma-separated MCP server names to attach |
| `AISHOW_STT_MODEL` | `gpt-4o-transcribe` | STT model (falls back to `whisper-1`) |
| `AISHOW_MAX_RECORD_SECONDS` | `30` | CLI recording cap |
| `AISHOW_STUB` | — | `1` → stub summoner for UI testing |
| `AISHOW_HOME` | — | Override for locating `.env` and `harness/spells` |
| `EDITOR` | `vi` | Editor for the CLI `e` (edit) choice |

Files under `~/.aishow/`: `sessions.json` (domain → TrueForge session id), `log.jsonl` (cast log). `UserDefaults` (`com.openhome.aishow`): `hotKeyModifiers`, `flameOverlayEnabled`, `uiLanguage`, `translateTargetLanguage`, `microphoneDeviceUID`.

`make` targets: `build`, `test`, `run ARGS=...`, `app` (release build → `dist/Aishow.app`, spells bundled into `Contents/Resources/harness`, `.env` excluded), `install` (copy to `~/Applications` and relaunch), `reset-tcc`, `harness`, `clean`. `make app` signs with a Keychain identity ending in "Local Dev" when present — an identifier-based signature keeps the Accessibility grant valid across rebuilds, unlike ad-hoc signing.

## Repository layout

```
Sources/AishowCore/      pure logic, no OS deps, unit-tested — ContextPack, Detect, Workflow
Sources/aishow/
  Commands/              scan · chant · cast · summon · flame subcommands
  Scan/                  Frontmost, BrowserURL, PageProbe, Selection (osascript / CGEvent, 3 s timeouts)
  Chant/                 Recorder, PushToTalkRecorder, Transcriber, AudioInputDevices, Env
  Summon/                TrueForgeClient (HTTP + SSE), TrueForgeSummon, SessionStore, SpellBook, Proposal, Pact
  Cast/                  Paster, CastLog
  App/                   MenuBarApp, HotKey, HUDPanel, StatusView, ApprovalView, SettingsView,
                         FlameOverlay, Glass, Permissions, Pipeline, L10n
harness/
  spells/                _common.md + one spell per workflow (the agent's instructions)
  trueforge-api.md       TrueForge HTTP/SSE protocol as verified against a live instance
  SETUP.md · tools.md    harness setup notes; schemas for custom tools (paste_to_cursor, scraper_heal/approve)
scripts/                 setup-harness.sh (register model + MCP), Info.plist.template, kanban.py
Tests/                   XCTest for AishowCore; fixtures for context packs and a Japanese audio sample
docs/                    idea.md (requirements), steps/ (one work order per PR), demo.md, kanban.xlsx
CLAUDE.md                development rules + versioned Bright Data scraper configuration
.pr_agent.toml           Qodo review configuration and project guidelines
```

No third-party Swift dependencies — `Foundation`, `AppKit`, `SwiftUI`, `AVFoundation`, `URLSession` only.

## A real run (2026-08-29)

Chrome on `https://brightdata.com/contact`, chant: 「この会社に、うちの音声SDKの話でコールドメッセージ」 → detected `website_form @ brightdata.com` → `gpt-5.2` on TrueForge made **14 Bright Data MCP calls** and returned:

> **sources**: https://docs.brightdata.com/datasets/scrapers/concepts/web-scraper-api-vs-diy
>
> **text**: I noticed Bright Data's Web Scraper API highlights 1000+ pre-built, maintained scrapers—impressive coverage. We've built a voice SDK that helps teams add fast, reliable speech UX (streaming STT/TTS, latency tuning, and tooling) to products and internal apps. If voice could complement any of your dashboards or developer tooling, I'd love to share a quick 15-minute overview—who's best to speak with?

Voice → approval pane took about a minute for `website_form` (dominated by live research); `translate` / `casual_en` return in a few seconds.

## Development process

The build was split into work orders (`docs/steps/`), each with scope, prohibitions and machine-checkable acceptance criteria. One step = one branch = one PR = Qodo `/agentic_review`; High findings fixed before merge.

| PR | Step | Notes |
|---|---|---|
| [#1](https://github.com/yossitv/aishow/pull/1) | 01 harness | TrueForge API investigation, spells, setup notes |
| [#2](https://github.com/yossitv/aishow/pull/2) | 02 scan / detect | High: AppleScript calls could hang → 3 s timeout |
| [#3](https://github.com/yossitv/aishow/pull/3) | 03 cast | High: activating the target defeated the frontmost-mismatch guard |
| [#4](https://github.com/yossitv/aishow/pull/4) | 04 chant | High: API key validated too late (after recording) |
| [#5](https://github.com/yossitv/aishow/pull/5) | 05 summon | High: **streamed proposal content discarded** — TrueForge puts text in `model.message.delta` / `turn.done.state.output.content`, not in `model.message` |
| [#6](https://github.com/yossitv/aishow/pull/6) | 06 menu bar | High: missing `Combine` import |
| [#7](https://github.com/yossitv/aishow/pull/7) | 07 wiring | Fixes for all High findings above; cwd-independent path resolution; hotkey re-entrancy guard |
| [#8](https://github.com/yossitv/aishow/pull/8), [#9](https://github.com/yossitv/aishow/pull/9) | docs | kanban, demo script, setup script |
| [#10](https://github.com/yossitv/aishow/pull/10) | S07 glass | Liquid Glass popover with macOS 14 fallback |
| [#11](https://github.com/yossitv/aishow/pull/11) | 08 hotkey / HUD | ⌘/Fn long-press, HUD, cancel/approve keys, Settings, English UI, recording fix |

What we learned about TrueForge along the way (all documented in `harness/trueforge-api.md`): the wire format is snake_case; errors arrive inside `turn.done` with HTTP 200; MCP servers are **remote-URL only** (no stdio), which is why Bright Data is attached through its hosted endpoint and why the approval gate lives in the app rather than as a TrueForge tool approval; and approvals in the protocol are allow/deny only, so "edit then approve" is resolved client-side.

## Status and known limitations

- `website_form` is the fully developed spell; `linkedin_dm`, `casual_en`, `email_en` and `translate` share the pipeline but have minimal instructions.
- The structured Bright Data **Scraper Studio collector** and the `heal → approve` self-healing loop are designed (`CLAUDE.md`, `harness/tools.md`) but not exercised live — the demo uses the MCP base tools `scrape_as_markdown` / `search_engine`.
- The custom tools `paste_to_cursor` / `scraper_heal` / `scraper_approve` are specified as schemas only; TrueForge accepts remote MCP servers exclusively, so they would need a small HTTP MCP server. Today pasting is done by the app after approval, and `require_approval_for_tools` on the Bright Data connector is empty.
- Page probing (`<form textarea>`, focused input) works in Chromium-based browsers; Safari and Firefox fall back to URL-path rules.
- `scan` always prints JSON (the `--json` flag in the help text is accepted but not required).
- macOS only. Chant is Japanese-first (`language: ja`); output language is English except for `translate`.

## Documentation

- [docs/idea.md](docs/idea.md) — requirements and design rationale
- [docs/steps/](docs/steps/README.md) — work orders, one per PR
- [docs/demo.md](docs/demo.md) — 3-minute demo script
- [harness/SETUP.md](harness/SETUP.md) — TrueForge / OpenAI / Bright Data setup
- [harness/trueforge-api.md](harness/trueforge-api.md) — verified TrueForge HTTP / SSE protocol
- [CLAUDE.md](CLAUDE.md) — development rules and scraper configuration

## Vocabulary

Caster (you) · Chant (voice) · Scan (context) · Spellbook (workflow selection) · Summon (TrueForge session) · Far Sight (Bright Data) · Pact (approval) · Cast (paste) · Flame (recording indicator).

## License

MIT
