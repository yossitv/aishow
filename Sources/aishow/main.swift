import AishowCore
import Foundation

// 1 バイナリ 2 モード:
//   引数なし            → (Step 6) メニューバー常駐アプリとして起動
//   サブコマンドあり    → CLI
//
//   scan    (Step 2) 索敵: 最前面アプリ・URL・選択テキスト → ContextPack + SiteDetection を JSON 出力
//   cast    (Step 3) 発動: stdin のテキストをカーソル位置に貼り付け(クリップボード復元つき)
//   chant   (Step 4) 詠唱: push-to-talk 録音 → OpenAI STT → テキスト
//   summon  (Step 5) 召喚: TrueForge に ContextPack + 詠唱を送り、承認を経て cast

let args = Array(CommandLine.arguments.dropFirst())
let rest = Array(args.dropFirst())

if args.first == nil {
    // main.swift のトップレベルはメインスレッドで実行されるため isolation を仮定してよい。
    MainActor.assumeIsolated {
        MenuBarApp.run() // Never returns
    }
}

let status: Int32
switch args.first {
case "scan":   status = ScanCommand.run(rest)
case "cast":   status = CastCommand.run(rest)
case "chant":  status = ChantCommand.run(rest)
case "summon": status = SummonCommand.run(rest)
case "flame":
    MainActor.assumeIsolated {
        FlameCommand.run(rest) // Never returns
    }
case "version", "--version", "-v":
    print("aishow \(Aishow.version)"); status = 0
case "help", "--help", "-h":
    print("""
    aishow \(Aishow.version) — 声で詠唱すると、AI エージェントが現れて仕事をする

    usage: aishow <command> [options]
      scan [--json]                     索敵: 最前面アプリ・URL・選択テキスト → ContextPack + SiteDetection
      cast [--app A] [--window-title T] 発動: stdin のテキストをカーソル位置に貼り付け(承認後にのみ呼ぶ)
      chant [--file x.wav]              詠唱: 録音 → OpenAI STT → テキスト
      summon [--chant "..."]            召喚: scan → chant → TrueForge → 承認 → cast
      flame [--seconds N]               (検収用) 画面の縁に炎を N 秒(既定 3)表示して消える
      version / help
    """); status = 0
default:
    FileHandle.standardError.write("unknown command: \(args[0])\n".data(using: .utf8)!)
    status = 64
}
exit(status)
