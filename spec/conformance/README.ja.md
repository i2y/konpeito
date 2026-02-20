# Konpeito コンフォーマンステスト

Ruby/spec にインスパイアされた、Konpeito の Ruby 互換性テストスイート。Ruby（リファレンス）、Native（LLVM）、JVM の3バックエンド間で出力を比較し、動作の差異を検出する。

## 設計方針

Konpeito は `eval` / `define_method` / `instance_eval` 等のメタプログラミングをサポートしないため、mspec の DSL を直接使用できない。代わりに **Opal モデル**を採用し、最小限のアサーションフレームワークと出力比較で互換性を検証する。

- テストファイル自体が Konpeito でコンパイル可能な Ruby コード
- 各テストは `run_tests` 関数内から呼び出される
- `PASS:` / `FAIL:` / `SUMMARY:` 行の stdout 出力を比較

## ディレクトリ構成

```
spec/conformance/
├── README.md                  # 英語版 README
├── README.ja.md               # 日本語版 README
├── runner.rb                  # テスト実行スクリプト（CRuby で実行）
├── lib/
│   ├── konpeito_spec.rb       # アサーションフレームワーク（Konpeito コンパイル可能）
│   └── runner/
│       ├── discovery.rb       # テストファイル探索
│       ├── executor.rb        # 各バックエンドでの実行
│       ├── comparator.rb      # 出力の比較・パース
│       ├── reporter.rb        # ターミナルレポート
│       └── tag_manager.rb     # 既知の失敗タグ管理
├── tags/
│   ├── native/                # Native バックエンドの既知の失敗
│   └── jvm/                   # JVM バックエンドの既知の失敗
└── language/
    ├── if_spec.rb             # if/unless/elsif
    ├── while_spec.rb          # while/until
    ├── case_spec.rb           # case/when
    ├── break_spec.rb          # break
    ├── next_spec.rb           # next
    ├── logical_operators_spec.rb  # && ||
    ├── method_spec.rb         # def, return, args, keyword args
    ├── variables_spec.rb      # local, $global, compound assignment
    ├── block_spec.rb          # yield, block_given?, Array iteration
    ├── string_spec.rb         # String#+, length, upcase, downcase, include? 等
    ├── integer_float_spec.rb  # Integer/Float 算術、比較、abs, even? 等
    ├── string_interpolation_spec.rb  # "Hello #{name}" 文字列補間
    ├── array_spec.rb          # Array#[], []=, length, push, first, last 等
    ├── hash_spec.rb           # Hash#[], []=, size, keys, values, has_key? 等
    ├── range_spec.rb          # Range#to_a, include?, size, each, first, last
    ├── multi_assign_spec.rb   # a, b = [1, 2]; for ループ
    └── exception_spec.rb      # begin/rescue/else/ensure, raise
```

## 使い方

### 全バックエンドで全 spec を実行

```bash
ruby spec/conformance/runner.rb
```

### バックエンド指定

```bash
ruby spec/conformance/runner.rb --native-only
ruby spec/conformance/runner.rb --jvm-only
```

### パターン指定（ファイル名の部分一致）

```bash
ruby spec/conformance/runner.rb if           # if_spec.rb のみ
ruby spec/conformance/runner.rb method       # method_spec.rb のみ
```

### オプション

| オプション | 説明 |
|-----------|------|
| `--native-only` | Native バックエンドのみ |
| `--jvm-only` | JVM バックエンドのみ |
| `--verbose`, `-v` | コンパイル・実行コマンド等の詳細出力 |
| `--no-color` | カラー出力を無効化 |

### Rake タスク

```bash
bundle exec rake conformance          # 全バックエンド
bundle exec rake conformance:native   # Native のみ
bundle exec rake conformance:jvm      # JVM のみ
```

## テストファイルの書き方

```ruby
require_relative "../lib/konpeito_spec"

def test_example
  result = 1 + 2
  assert_equal(3, result, "1 + 2 equals 3")
end

def run_tests
  spec_reset
  test_example
  spec_summary
end

run_tests
```

### 利用可能なアサーション

| メソッド | 説明 |
|---------|------|
| `assert_equal(expected, actual, desc)` | `expected == actual` を検証 |
| `assert_true(value, desc)` | 値が truthy であることを検証 |
| `assert_false(value, desc)` | 値が falsy であることを検証 |
| `assert_nil(value, desc)` | 値が `nil` であることを検証 |
| `spec_reset` | カウンタをリセット |
| `spec_summary` | `SUMMARY:` 行を出力 |

### 制約

アサーションフレームワークは Konpeito でコンパイル可能でなければならないため、以下のみ使用可能：

- グローバル変数、関数定義、`puts`、文字列連結、`if/else`、`==`
- クラス定義、モジュール定義、メタプログラミングは不可

## 実行の仕組み

各 spec ファイルは3つの方法で実行される：

| バックエンド | 実行方法 |
|------------|---------|
| Ruby | `ruby language/if_spec.rb` |
| Native | `konpeito build -o /tmp/if_spec.bundle language/if_spec.rb` → `ruby -r /tmp/if_spec.bundle -e "run_tests"` |
| JVM | `konpeito build --target jvm -o /tmp/if_spec.jar language/if_spec.rb` → `java -jar /tmp/if_spec.jar` |

Ruby の出力をリファレンスとし、Native / JVM の出力と `PASS:` / `FAIL:` 行を比較する。

## 出力の見方

```
break_spec:
  ruby: 6 passed, 0 failed
  native: 6 passed, 0 failed [MATCH]     ← Ruby と完全一致
  jvm: 6 passed, 0 failed [MATCH]

if_spec:
  ruby: 19 passed, 0 failed
  native: 18 passed, 1 failed [DIFF (1)] ← 1件の差異あり

method_spec:
  ruby: 16 passed, 0 failed
  native: ERROR - native compilation failed ← コンパイルエラー
```

- **MATCH**: Ruby と出力が完全一致
- **DIFF (N)**: N 件の出力差異
- **ERROR**: コンパイルまたは実行時エラー

## 既知の失敗（Tags）

`tags/{native,jvm}/` ディレクトリに既知の失敗を記録する。

### 現在の状況

#### Native バックエンド（12 MATCH, 2 DIFF, 3 ERROR / 17 specs）

| Spec | Status | 原因 |
|------|--------|------|
| block_spec | MATCH | |
| break_spec | MATCH | |
| case_spec | MATCH | |
| exception_spec | MATCH | |
| if_spec | MATCH | |
| logical_operators_spec | MATCH | |
| method_spec | MATCH | |
| next_spec | MATCH | |
| range_spec | MATCH | |
| string_spec | MATCH | |
| variables_spec | MATCH | |
| while_spec | MATCH | |
| hash_spec | DIFF (1) | `Hash#[]=` の上書きが誤った値を返す |
| integer_float_spec | DIFF (6) | 負数の除算/剰余がC言語の切り捨てセマンティクス; 比較がfalseでなく0を返す |
| array_spec | ERROR | `TypeError` — compact/flatten で nil→integer 変換エラー |
| multi_assign_spec | ERROR | `NoMethodError` — 多重代入の変数が未初期化 |
| string_interpolation_spec | ERROR | SEGV — 実行時クラッシュ |

#### JVM バックエンド（8 MATCH, 1 DIFF, 8 ERROR / 17 specs）

| Spec | Status | 原因 |
|------|--------|------|
| break_spec | MATCH | |
| case_spec | MATCH | |
| hash_spec | MATCH | |
| if_spec | MATCH | |
| logical_operators_spec | MATCH | |
| method_spec | MATCH | |
| next_spec | MATCH | |
| while_spec | MATCH | |
| integer_float_spec | DIFF (2) | 負数の除算/剰余がJavaの切り捨てセマンティクス |
| array_spec | ERROR | 実行時エラー |
| block_spec | ERROR | ASM `NegativeArraySizeException`（スタックフレーム型不整合） |
| exception_spec | ERROR | 実行時エラー |
| multi_assign_spec | ERROR | 実行時エラー |
| range_spec | ERROR | 実行時エラー |
| string_interpolation_spec | ERROR | 実行時エラー |
| string_spec | ERROR | 実行時エラー |
| variables_spec | ERROR | ASM `NegativeArraySizeException` |

## 新しい spec の追加方法

1. `language/` に `<feature>_spec.rb` を作成
2. `require_relative "../lib/konpeito_spec"` を先頭に記述
3. テスト関数を定義し、`run_tests` から呼び出す
4. `ruby language/<feature>_spec.rb` で Ruby 上の動作を確認
5. `ruby spec/conformance/runner.rb <feature>` でバックエンド間比較
6. 失敗がある場合は `tags/{native,jvm}/` にタグファイルを作成
