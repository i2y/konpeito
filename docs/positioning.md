# Konpeito ポジショニング分析

## Konpeito とは何か

Ruby の漸進的型付け AOT コンパイラ。CRuby エコシステム（LLVM → .so）と Java エコシステム（JVM → .jar）の両方にアクセスできる。Castella UI フレームワーク付き。

**漸進的型付け（Gradual Typing）:** 型注釈なしでも HM 型推論が自動的に型を特定し、特定できない場合は動的ディスパッチにフォールバックする。RBS 型注釈を追加することで段階的に最適化を強化できる。TypeScript が JavaScript に対して果たす役割に近い。

## エコシステムブリッジとしての立ち位置

```
           CRuby エコシステム
               ↑
          CRuby 拡張 (.so)
               ↑
    Ruby ソースコード → Konpeito
               ↓
          JVM バイトコード (.jar)
               ↓
           Java エコシステム
```

- **LLVM バックエンド** → 既存の Rails アプリのホットパスだけ高速化して `.so` で差し込める
- **JVM バックエンド** → Java の膨大なライブラリ資産（JWM, Skija, その他何でも）にアクセスできる
- **どちらも Ruby のまま**書ける

二つの巨大エコシステムへの橋。Ruby エコシステムには既に JRuby（JVM）、Glimmer（デスクトップ GUI）、FFI gem（ネイティブ連携）等の既存ブリッジがあるが、Konpeito は AOT コンパイル + HM 型推論という異なるアプローチで同じ領域に取り組む。

## Crystal との違い

Crystal は「Ruby を捨てて新しい世界に行く」選択。Konpeito は「Ruby のまま両方の世界にアクセスする」選択。解決する問題が根本的に違う。

| 観点 | Crystal | Konpeito |
|------|---------|----------|
| 言語 | Ruby 風だが別言語 | Ruby そのもの（静的サブセット） |
| CRuby エコシステム | 使えない | CRuby 拡張 (.so) として統合可能 |
| Java エコシステム | 使えない | JVM バックエンドで全ライブラリにアクセス可能 |
| 既存 Ruby プロジェクト | 統合不可 | ホットパスだけ差し替え可能 |
| gem / C 拡張 | 使えない | CRuby 拡張として共存可能 |
| 移行コスト | ゼロから作り直し | 既存 Ruby コードを段階的にコンパイル可能 |

## Kotlin Multiplatform との比較（デスクトップアプリ）

Konpeito + Castella UI は、クロスプラットフォームデスクトップアプリを最もシンプルに書ける選択肢の一つ。

```ruby
# Konpeito + Castella DSL: カウンターアプリ
class CounterApp < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0, spacing: 8.0) {
      text "Count: #{@count}", font_size: 32.0, align: :center
      row(spacing: 8.0) {
        button(" - ") { @count -= 1 }
        button(" + ") { @count += 1 }
      }
    }
  end
end
```

| | Konpeito + Castella | Kotlin Compose | Electron | Tauri |
|--|---|---|---|---|
| 言語の簡潔さ | Ruby | Kotlin | JS/TS | Rust + JS |
| ビルドの手軽さ | 簡単 | Gradle... | 普通 | 普通 |
| バイナリサイズ | JAR サイズ | 同程度 | 巨大 | 小 |
| GPU 描画 | Skia | Skia | Chromium | WebView |
| 学習コスト | 低 | 高 | 中 | 高 |

## Python 版を作る意味はあるか

**ない。** Python エコシステムには既に各領域に成熟したツールが存在する。

| 領域 | Python（既存ツール） | Ruby（既存ツール） |
|------|---------------------|-------------------|
| AOT コンパイラ | Cython, mypyc, Numba, Nuitka | **なし → Konpeito** |
| JVM 実装 | Jython, GraalPy | JRuby（インタプリタ、AOT ではない） |
| 宣言的ネイティブ GUI | Castella（Python 版が既に同品質で動作中） | **なし → Konpeito + Castella UI** |

Konpeito の価値は「Ruby エコシステムの空白を埋めている」ことに大きく依存しており、Python にはその空白がそもそも存在しない。

## 強み

- **アプローチの独自性**: 同じ AOT + 型駆動アプローチのツールが Ruby エコシステムにない
- **エコシステムブリッジ**: CRuby と JVM の両方に Ruby のままアクセスできる（JRuby や Glimmer 等の既存ブリッジとはアプローチが異なる）
- **Castella UI**: Ruby でデスクトップアプリが現実的に書ける。Kotlin Multiplatform より学習コストが低い
- **段階的導入**: 既存 Rails アプリのホットパスだけ `.so` に差し替える、という使い方が可能
- **AI 駆動開発**: 開発の大部分を AI が担当しており、保守の持続性リスクが軽減される

## 弱み

- **市場規模**: Ruby 人口自体が縮小傾向。ネイティブ性能やデスクトップアプリを必要とする層はさらに小さい
- **YJIT との競合**: Ruby 4.0 の YJIT 進化により「Ruby のままで十分速い」ケースが増加中
- **サブセット制約**: eval / define_method / method_missing が使えない

## 総合評価

| 観点 | 評価 |
|------|------|
| 技術 | 高い。コンパイラとして真っ当に作られている |
| 独自性 | 高い。同じアプローチのツールが存在しない |
| 実用性 | 中〜高。CRuby 拡張用途は今すぐ使える |
| 市場規模 | 小さい。ただしニッチに確実な需要はある |
| 持続性 | AI 活用で現実的 |
| 将来性 | Castella UI と JVM エコシステム連携次第で化ける可能性あり |

**一言で言うと:** ニッチだが、同じアプローチの代替がない。既存ブリッジ（JRuby, Glimmer 等）とは異なる方法で同じ問題に取り組んでおり、AOT + 型駆動最適化という選択肢を Ruby エコシステムに加える。
