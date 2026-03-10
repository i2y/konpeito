---
layout: default
title: チュートリアル
parent: "日本語 (Japanese)"
nav_order: 1
---

# チュートリアル

このチュートリアルでは、Konpeito のインストールから実際のコードを動かすところまでを一通り体験します。

## 1. インストール

### 前提条件

| 依存 | バージョン | 用途 |
|------|-----------|------|
| Ruby | 4.0.1+ | 必須（コンパイラ本体の実行） |
| LLVM | 20 | CRuby ネイティブバックエンド、mruby バックエンド |
| Java | 21+ | JVM バックエンド |
| mruby | 3.x | mruby バックエンド |

LLVM、Java、mruby は使うバックエンドに応じて必要になります。いずれか1つだけでも動きます。

### Konpeito のインストール

```bash
gem install konpeito
```

### LLVM 20 のインストール（CRuby バックエンド用）

**macOS:**
```bash
brew install llvm@20
ln -sf /opt/homebrew/opt/llvm@20/lib/libLLVM-20.dylib /opt/homebrew/lib/
gem install ruby-llvm
```

**Ubuntu / Debian:**
```bash
sudo apt install llvm-20 clang-20
gem install ruby-llvm
```

**Fedora:**
```bash
sudo dnf install llvm20 clang20
gem install ruby-llvm
```

### Java 21 のインストール（JVM バックエンド用）

**macOS:**
```bash
brew install openjdk@21
```

**Ubuntu / Debian:**
```bash
sudo apt install openjdk-21-jdk
```

**Fedora:**
```bash
sudo dnf install java-21-openjdk-devel
```

### 環境チェック

```bash
konpeito doctor              # CRuby バックエンドを確認
konpeito doctor --target jvm # JVM バックエンドを確認
```

必要なツールがすべてインストールされていれば、緑のチェックマークが表示されます。以下の2つの WARNING は正常なので無視して構いません:

- **ASM tool: WARNING** — JVM バックエンド用のバイトコードアセンブラです。初回の JVM ビルド時に自動でビルドされるため、事前の対応は不要です。
- **Config: WARNING** — カレントディレクトリに `konpeito.toml` が見つからないという意味です。プロジェクトをまだ作成していない場合は正常です。`konpeito init` で作成するか、ソースファイルを直接 `konpeito build` に渡せば問題ありません。

---

## 2. Hello World

### CRuby バックエンド（ネイティブ拡張）

```ruby
# hello.rb
module Hello
  def self.greet(name)
    "Hello, #{name}!"
  end
end
```

```bash
konpeito build hello.rb   # → hello.bundle (macOS) / hello.so (Linux)
```

Ruby から使う:
```ruby
require_relative "hello"
puts Hello.greet("World")   # => "Hello, World!"
```

コンパイルされた拡張は標準の CRuby C 拡張です。C で書かれた gem と同じように、どの Ruby プロセスからでもロードできます。モジュールで囲むことでトップレベルの名前空間を汚さないようにします — 拡張ライブラリではこのパターンが推奨です。

### JVM バックエンド（スタンドアロン JAR）

```ruby
# hello_jvm.rb
puts "Hello from Konpeito!"
```

```bash
konpeito build --target jvm --run hello_jvm.rb
```

初回ビルド時は "Building ASM tool" というメッセージが出ます。これは一度きりのセットアップです。

出力例:
```
     Compiling hello_jvm.rb (jvm)
Building ASM tool (first-time setup)...
ASM tool ready.
Running: java -jar hello_jvm.jar
Hello from Konpeito!
      Finished in 0.9s -> hello_jvm.jar (36 KB)
```

生成された JAR はスタンドアロン — 実行マシンに Ruby は不要です。

---

## 3. Konpeito の仕組み

Konpeito がコードをコンパイルするとき、各操作は2つのカテゴリに分類されます:

- **ネイティブ** — コンパイラが型を解決し、ネイティブ CPU 命令（例: LLVM: `add i64`, `fadd double`, `getelementptr`）または型付き JVM バイトコード（例: `iadd`, `dadd`）を出力。Ruby のメソッド探索オーバーヘッドなし。
- **動的フォールバック** — 型が特定できない場合、`rb_funcallv`（LLVM）または `invokedynamic`（JVM）にフォールバック。通常の Ruby と同じ速度で動作。コンパイラが警告を出すので、どこが境界かわかります。

RBS 型注釈を追加すると、動的フォールバックをネイティブディスパッチに昇格できます。速度が不要な箇所はそのままにしても問題ありません。

### Gem とランタイム依存

`require "some_gem"` を書いた場合:

- **ロードパス上にある場合（`-I` で指定）** — gem のソースも一緒にコンパイルされ、直接ディスパッチ・単相化・インライン化が適用されます。
- **ロードパス上にない場合** — `rb_require("some_gem")` が発行され、CRuby が実行時にロード。動的ディスパッチ経由ですが正しく動作します。

---

## 4. CRuby バックエンド: 実用例

### パターン1: 拡張ライブラリ

計算集約的な関数だけコンパイルし、通常の Ruby アプリから `require` して使うパターンです。

#### ステップ1: コードを書く

```ruby
# physics.rb
module Physics
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  def self.sum_distances(xs, ys, n)
    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    total
  end
end
```

#### ステップ2: RBS で型を明示する（任意）

RBS がなくても HM 推論で型は解決されますが、明示すればより強い最適化が効きます。

**方法A: インライン RBS（手軽でおすすめ）**

rbs-inline コメントで、Ruby ソース内に直接型注釈を書けます:

```ruby
# physics.rb
# rbs_inline: enabled

module Physics
  #: (Float x1, Float y1, Float x2, Float y2) -> Float
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  #: (Array[Float] xs, Array[Float] ys, Integer n) -> Float
  def self.sum_distances(xs, ys, n)
    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    total
  end
end
```

**方法B: 別ファイルの RBS**

```rbs
# physics.rbs
module Physics
  def self.distance: (Float x1, Float y1, Float x2, Float y2) -> Float
  def self.sum_distances: (Array[Float] xs, Array[Float] ys, Integer n) -> Float
end
```

#### ステップ3: コンパイル

```bash
# インライン RBS の場合（方法A）
konpeito build --inline physics.rb

# 別ファイル RBS の場合（方法B）
konpeito build physics.rb
```

`-v` をつけると、推論された型と動的フォールバック箇所が表示されます:

```bash
konpeito build -v physics.rb
```

#### ステップ4: Ruby から使う

```ruby
# app.rb — 通常の Ruby（Konpeito ではコンパイルしない）
require_relative "physics"

xs = Array.new(10000) { rand }
ys = Array.new(10000) { rand }
puts Physics.sum_distances(xs, ys, 10000)
```

```bash
ruby app.rb
```

**ネイティブになる部分:** `distance` は完全にネイティブ — `dx * dx + dy * dy` は `fmul double` + `fadd double` 命令に変換。`sum_distances` の `while` ループもネイティブカウンターループです。

**動的フォールバックになる部分:** `xs[i]` は Ruby Array への `rb_funcallv` 呼び出し（Array は CRuby オブジェクト）。ここもネイティブにしたい場合は `NativeArray[Float]` を使います:

#### NativeArray で完全ネイティブ化

`NativeArray[Float]` は unboxed の `double` 値を連続メモリに格納します。配列要素アクセスは `getelementptr` + `load` に直接変換され、メソッドディスパッチは一切発生しません。

`NativeArray` は Konpeito 固有の型なので、生成・使用するコードも Konpeito でコンパイルする必要があります。NativeArray の作成・アクセスは同じ関数スコープ内にまとめます:

```ruby
# physics_native.rb
# rbs_inline: enabled

module Physics
  #: (Float, Float, Float, Float) -> Float
  def self.distance(x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    dx * dx + dy * dy
  end

  def self.run
    n = 10000
    xs = NativeArray.new(n)
    ys = NativeArray.new(n)
    i = 0
    while i < n
      xs[i] = i * 0.0001
      ys[i] = i * 0.0002
      i = i + 1
    end

    total = 0.0
    i = 0
    while i < n - 1
      total = total + distance(xs[i], ys[i], xs[i + 1], ys[i + 1])
      i = i + 1
    end
    puts total
  end
end

Physics.run
```

```bash
konpeito run physics_native.rb
```

> **ヒント:** `konpeito run` はコンパイル済みアーティファクトを `.konpeito_cache/run/` にキャッシュします。ソースファイルやRBSファイルが変更されていなければ、再コンパイルはスキップされます。`--no-cache` で強制再コンパイル、`--clean-run-cache` でキャッシュクリアが可能です。

> **注意:** 同じディレクトリに `physics_native.rb` と `physics_native.bundle` の両方が存在する場合、`require "./physics_native"` は `.rb` ソースファイルを先にロードします。`konpeito run` はロードパスを自動的に処理するため、この問題を回避できます。ビルドと実行を分けたい場合は、出力先を別ディレクトリにしてください:
> ```bash
> konpeito build -o build/physics_native.bundle physics_native.rb
> ruby -r ./build/physics_native -e ""
> ```

> **重要:** NativeArray はスタック上に確保されるポインタであり、CRuby のメソッドディスパッチ経由で他の関数に引数として渡すことはできません。NativeArray は必ず同じ関数スコープ内で作成・使用してください。

これで `xs[i]` と `ys[i]` もネイティブになり、ループ全体が Ruby のメソッドディスパッチを経由せずに実行されます。

### パターン2: アプリケーション全体のコンパイル

`require` チェーンを辿り、ロードパス上のすべてのファイルを単一の拡張に一括コンパイルします。

#### 例: kumiki GUI アプリ

[kumiki](https://github.com/i2y/kumiki) はクロスプラットフォームのデスクトップ UI フレームワークです。

```bash
gem install kumiki
```

```ruby
# counter.rb
require "kumiki"
include Kumiki

class CounterComponent < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    column(padding: 16.0, spacing: 8.0) {
      text "Count: #{@count}", font_size: 32.0, color: 0xFFC0CAF5, align: :center
      row(spacing: 8.0) {
        button(" - ") { @count -= 1 }
        button(" + ") { @count += 1 }
      }
    }
  end
end

frame = RanmaFrame.new("Kumiki Counter", 400, 300)
app = App.new(frame, CounterComponent.new)
app.run
```

**Option A: 全体コンパイル（kumiki のソースも含む）**

```bash
konpeito build -I /path/to/kumiki/lib counter.rb
```

`-I` で kumiki の `lib/` を指定すると、`require "kumiki"` の先にあるすべてのファイル（59ファイル）が一括コンパイルされます。直接ディスパッチ・単相化・インライン化がコード全体に適用されます。

**Option B: 自分のコードだけコンパイル**

```bash
konpeito build counter.rb
```

`-I` なしでは `counter.rb` だけがコンパイルされ（約50 KB）、kumiki は実行時に CRuby がロードします。

**実行:**

```bash
konpeito run counter.rb
```

または、`.rb` / `.bundle` の名前衝突を避けるために別ディレクトリにビルドします:

```bash
konpeito build -o build/counter.bundle counter.rb
ruby -r ./build/counter -e ""
```

- `-r ./build/counter` で拡張をロード。`Init` 関数がトップレベルコードを実行し、アプリが起動します。
- `-e ""` で空スクリプトを渡します（Ruby が stdin を待たないように）。
- `counter.rb` と同じディレクトリで `ruby -r ./counter -e ""` を使わないでください — Ruby は `.bundle` より `.rb` を先にロードするため、コンパイルされていないソースが実行されます。

---

## 5. JVM バックエンド: 実用例

### スタンドアロンプログラム

```ruby
# physics_jvm.rb
def distance(x1, y1, x2, y2)
  dx = x2 - x1
  dy = y2 - y1
  dx * dx + dy * dy
end

def sum_distances(n)
  total = 0.0
  i = 0
  while i < n
    total = total + distance(i * 1.0, 0.0, 0.0, i * 2.0)
    i = i + 1
  end
  total
end

puts sum_distances(1000)
```

```bash
konpeito build --target jvm --run physics_jvm.rb
```

JAR を生成して別途実行:

```bash
konpeito build --target jvm -o physics.jar physics_jvm.rb
java -jar physics.jar
```

### GUI アプリ（Castella UI）

JVM バックエンドでは Castella UI（Skia ベースのリアクティブ GUI フレームワーク）が使えます。

```bash
git clone https://github.com/i2y/konpeito.git
cd konpeito/examples/castella_ui
bash setup.sh    # JWM + Skija JAR をダウンロード（約30 MB、初回のみ）
bash run.sh framework_counter.rb
```

```ruby
# framework_counter.rb
class CounterApp < Component
  def initialize
    super
    @count = state(0)
  end

  def view
    label = "Count: " + @count.value.to_s
    Column(
      Text(label).font_size(32.0),
      Row(
        Button("  -  ").on_click { @count -= 1 },
        Button("  +  ").on_click { @count += 1 }
      ).spacing(8.0)
    )
  end
end

$theme = theme_tokyo_night
frame = JWMFrame.new("Counter", 400, 300)
app = App.new(frame, CounterApp.new)
app.run
```

Castella UI の詳細は [Getting Started](getting-started.md) のウィジェットカタログとテーマ一覧を参照してください。

---

## 5.5. mruby バックエンド: スタンドアロン実行ファイル

mruby バックエンドはスタンドアロン実行ファイルを生成します — 実行マシンに Ruby や Java は不要です。アプリケーション配布、ゲーム開発、Ruby がインストールされていない環境へのデプロイに最適です。

### スタンドアロン Hello World

```ruby
# hello.rb
def main
  puts "Hello from Konpeito!"
end

main
```

```bash
konpeito build --target mruby -o hello hello.rb
./hello    # => Hello from Konpeito!
```

ビルドと実行を一度に:

```bash
konpeito run --target mruby hello.rb
```

### raylib stdlib でゲーム開発

Konpeito は mruby バックエンド向けに raylib stdlib を内蔵しています。コード内で `module Raylib` を参照すると、コンパイラが RBS/C ラッパーを自動検出します — 手動セットアップは不要です。

```ruby
# catch_game.rb
module Raylib
end

def main
  screen_w = 600
  screen_h = 400

  Raylib.init_window(screen_w, screen_h, "Catch Game")
  Raylib.set_target_fps(60)

  paddle_x = screen_w / 2 - 40
  paddle_y = screen_h - 40
  paddle_speed = 400

  obj_x = Raylib.get_random_value(30, screen_w - 30)
  obj_y = 0
  obj_speed = 150.0
  score = 0

  while Raylib.window_should_close == 0
    dt = Raylib.get_frame_time

    if Raylib.key_down?(Raylib.key_left) != 0
      paddle_x = paddle_x - (paddle_speed * dt).to_i
    end
    if Raylib.key_down?(Raylib.key_right) != 0
      paddle_x = paddle_x + (paddle_speed * dt).to_i
    end

    obj_y = obj_y + (obj_speed * dt).to_i
    if obj_y > screen_h
      obj_x = Raylib.get_random_value(30, screen_w - 30)
      obj_y = 0
    end

    Raylib.begin_drawing
    Raylib.clear_background(Raylib.color_black)
    Raylib.draw_rectangle(paddle_x, paddle_y, 80, 14, Raylib.color_skyblue)
    Raylib.draw_rectangle(obj_x, obj_y, 16, 16, Raylib.color_gold)
    Raylib.draw_text("Score: #{score}", 10, 10, 20, Raylib.color_white)
    Raylib.end_drawing
  end

  Raylib.close_window
end

main
```

```bash
konpeito run --target mruby catch_game.rb
```

### クロスコンパイル

`zig cc` を使って他のプラットフォーム向けにクロスコンパイルできます:

```bash
konpeito build --target mruby \
  --cross aarch64-linux-musl \
  --cross-mruby ~/mruby-aarch64 \
  -o game game.rb
```

| オプション | 説明 |
|---|---|
| `--cross TARGET` | ターゲットトリプル（例: `x86_64-linux-gnu`） |
| `--cross-mruby DIR` | クロスコンパイル済み mruby のインストールパス |
| `--cross-libs DIR` | 追加ライブラリ検索パス |

### mruby vs CRuby バックエンド比較

| 観点 | CRuby バックエンド | mruby バックエンド |
|---|---|---|
| 出力 | .so/.bundle（拡張ライブラリ） | スタンドアロン実行ファイル |
| 実行時依存 | CRuby 4.0+ | なし |
| 用途 | ライブラリ/アプリの高速化 | 配布、ゲーム |
| raylib stdlib | 非対応 | 自動検出 |
| Thread/Mutex | 対応 | 非対応 |
| キーワード引数 | 対応 | 非対応 |
| コンパイルキャッシュ | `.konpeito_cache/run/` | `.konpeito_cache/run/` |

---

## 6. 型システム

### HM 型推論（注釈不要）

Konpeito は Hindley-Milner 型推論でほとんどの型を自動解決します:

```ruby
def double(x)
  x * 2          # 2 が Integer → x は Integer → 戻り値も Integer
end

def greet(name)
  "Hello, " + name   # String + String → String
end
```

推論された型はそのまま unboxed 最適化に使われます。RBS は不要です。

### RBS でより正確に

RBS を追加すると、コンパイラにより正確な情報を伝えられます:

**別ファイル方式:**

```rbs
# sig/math.rbs
module TopLevel
  def add: (Integer a, Integer b) -> Integer
end
```

```bash
konpeito build --rbs sig/math.rbs math.rb
```

**インライン方式（rbs-inline）:**

```ruby
# rbs_inline: enabled

#: (Integer, Integer) -> Integer
def add(a, b)
  a + b
end
```

```bash
konpeito build --inline math.rb
```

### ネイティブデータ構造

型付き高速データ構造が使えます（CRuby バックエンド）:

| 型 | 用途 | 特徴 |
|---|---|---|
| `NativeArray[T]` | 数値配列 | unboxed、連続メモリ、5-15x 高速 |
| `NativeClass` | 構造体 | unboxed フィールド、10-20x 高速 |
| `StaticArray[T, N]` | 固定長配列 | スタック割り当て、GC なし |
| `NativeHash[K, V]` | ハッシュマップ | 線形探査、4x 高速 |
| `Slice[T]` | メモリビュー | ゼロコピー、バウンドチェック付き |

```ruby
# NativeArray の例
def sum_array(n)
  arr = NativeArray.new(n)
  i = 0
  while i < n
    arr[i] = i * 1.5   # unboxed store
    i = i + 1
  end

  total = 0.0
  i = 0
  while i < n
    total = total + arr[i]   # unboxed load
    i = i + 1
  end
  total
end
```

これらの型を使うには RBS 定義が必要です。詳細は [API Reference](api-reference.md) を参照してください。

---

## 7. プロジェクト構成

`konpeito init` でプロジェクトを初期化できます:

```bash
konpeito init --target jvm my_app
cd my_app
```

```
my_app/
  konpeito.toml       # ビルド設定
  src/
    main.rb           # エントリポイント
  test/
    main_test.rb      # テストスタブ
  lib/                # JVM 依存（JAR）
  .gitignore
```

```bash
konpeito run src/main.rb    # コンパイル & 実行
konpeito test               # テスト実行
```

---

## 8. 便利なコマンド

```bash
konpeito build -v source.rb          # 推論結果と動的フォールバック箇所を表示
konpeito build -g source.rb          # DWARF デバッグ情報付きでビルド（lldb/gdb 対応）
konpeito check source.rb             # 型チェックのみ（コード生成なし）
konpeito build --profile source.rb   # プロファイリング情報付きでビルド
konpeito run --no-cache source.rb    # キャッシュを無視して強制再コンパイル
konpeito run --clean-run-cache source.rb  # runキャッシュクリア後にビルド＆実行
konpeito fmt                         # コードフォーマット（RuboCop）
konpeito deps source.rb              # 依存関係の解析・表示

# mruby バックエンド
konpeito build --target mruby -o app app.rb    # スタンドアロン実行ファイル
konpeito run --target mruby app.rb             # ビルド＆実行（キャッシュあり）
konpeito doctor --target mruby                 # mruby 環境チェック
```

---

## 次のステップ

- **[CLI Reference](cli-reference.md)** — 全コマンドとオプション
- **[API Reference](api-reference.md)** — ネイティブデータ構造、標準ライブラリ、Castella UI ウィジェット
- **[Language Specification](language-specification.md)** — 対応構文と型システムの詳細
