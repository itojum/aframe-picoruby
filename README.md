# aframe_picoruby

[A-Frame](https://aframe.io/) のシーンを [PicoRuby.wasm](https://github.com/picoruby/picoruby/tree/master/mrbgems/picoruby-wasm) の Ruby で操作するための小さなライブラリです。
マウスで図形を掴んで動かす処理（[`examples/grab/`](examples/grab/)）を、JavaScript の A-Frame コンポーネントを書かずに Ruby だけで実装できます。

## クイックスタート

ライブラリは分割したファイルのまま配布しています。`require "aframe"` の中の `require "aframe/..."` は
[importmap-picoruby](https://github.com/itojum/importmap-picoruby) が解決するため、**importmap-picoruby が必須**です
（`<script type="text/ruby" src="...">` で `lib/aframe.rb` を直接読み込むだけでは動きません）。

```html
<script src="https://aframe.io/releases/1.8.0/aframe.min.js"></script>

<a-scene camera-lock>
  <a-entity position="0 0 4">
    <a-camera look-controls wasd-controls>
      <a-entity cursor="rayOrigin: mouse" raycaster="objects: .my-grabbable"></a-entity>
    </a-camera>
  </a-entity>
  <a-box class="my-grabbable" grab-target position="0 1.5 -2" color="#4CC3D9"></a-box>
</a-scene>

<script type="text/ruby-importmap">
{ "imports": { "aframe": "https://cdn.jsdelivr.net/npm/aframe_picoruby@0.0.1/lib/aframe.rb" } }
</script>
<script type="text/ruby" src="https://cdn.jsdelivr.net/npm/importmap-picoruby@0/loader.rb"></script>
<script type="text/ruby-app" src="main.rb"></script>
<script src="https://cdn.jsdelivr.net/npm/@picoruby/wasm-wasi@4.0.6-head.20261119/dist/init.iife.js"></script>
```

```ruby
# main.rb
require "aframe"

AFrame::Scene.ready          # a-scene の読み込みを待つ
AFrame::Scene.run            # フレームループ（戻ってこない）
```

`grab-target` 属性を付けた図形は、`require "aframe"` するだけでマウスや VR コントローラーで掴めるようになります。`<a-scene camera-lock>` は、図形を掴んでいる間に視点が回らないようにする System です。詳しくは[リファレンスの「掴んで動かす」](docs/reference.md#掴んで動かす)を見てください。

> npm への公開前は、importmap の `aframe` に手元の `lib/aframe.rb` の URL（例：`/lib/aframe.rb`）を指定してください。

## できること

| できること | 書き方 |
|---|---|
| 図形をマウスや VR コントローラーで掴んで動かす | [`grab-target` / `camera-lock`](docs/reference.md#掴んで動かす) |
| Ruby から要素を作る | [`AFrame::Entity.create` / `AFrame.scene`](docs/reference.md#要素を作る) |
| 位置・回転・大きさを変える（回転は属性が度、`Entity#rotation` がラジアン） | [`position` / `rotation` / `scale`](docs/reference.md#位置回転大きさを変える) |
| 日本語の文字を出す | [`label`](docs/reference.md#日本語の文字を出す) |
| 図形の端を回転の中心にする | [`anchor`](docs/reference.md#回転の中心を端にするanchor) |
| イベントを受け取る | [`on` / `once` / `off`](docs/reference.md#イベントを受け取る) |
| A-Frame のプロパティやメソッドをそのまま使う | [`Entity` から JS へ渡す](docs/reference.md#a-frame-のプロパティを触る) |
| コンポーネントを Ruby で書く | [`AFrame::Component`](docs/reference.md#コンポーネントを作る) |
| コンポーネントの中で「n 秒後」「n 秒ごと」に処理する | [`after` / `every`](docs/reference.md#コンポーネントの中で待つ) |
| シーン全体を見る処理（System）を Ruby で書く | [`AFrame::System`](docs/reference.md#シーン全体を見る処理を作る) |
| 補間と乱数を使う | [`AFrame::Easing` / `AFrame.random`](docs/reference.md#補間と乱数) |

毎フレームの処理をどこに書くかの目安と、すべての API の一覧も[リファレンス](docs/reference.md)にあります。

## examples

| デモ | 内容 |
|---|---|
| [`examples/grab/`](examples/grab/) | マウスや VR コントローラーで図形を掴んで動かす。掴むと札（`label`）の文字が変わる |
| [`examples/spin/`](examples/spin/) | Ruby で定義したコンポーネントで図形を回す |
| [`examples/garden/`](examples/garden/) | Ruby で定義した System で花を植えて間引く。花は easing で伸びる |
| [`examples/scene/`](examples/scene/) | `AFrame.scene` でシーンを組み立てる |

## 使っているもの

| もの | 版 |
|---|---|
| A-Frame | 1.8.0 |
| importmap-picoruby | 0 系 |
| PicoRuby.wasm (`@picoruby/wasm-wasi`) | `4.0.6-head.20261119` |

すべて CDN から読み込みます。ビルドや `node_modules` は不要です。

## 開発

```bash
ruby script/server
```

http://localhost:3000 で `examples/` が、`/lib` で `lib/` が配信されます（キャッシュなし）。

```
lib/
├── aframe.rb            … require を並べるだけのエントリ
└── aframe/
    ├── version.rb       … AFrame::VERSION
    ├── easing.rb        … 補間（AFrame::Easing）と乱数（AFrame.random）
    ├── scene.rb         … シーンの読み込み待ちとフレームループ
    ├── entity.rb        … A-Frame 要素の薄いラッパー
    ├── component.rb     … Ruby で書く A-Frame のコンポーネント
    ├── timer.rb         … コンポーネントの after / every のタイマー（AFrame::Timer）
    ├── system.rb        … Ruby で書く A-Frame の System
    ├── builder.rb       … AFrame.scene（ブロックで要素を作る）
    ├── camera_lock.rb   … 掴んでいる間の視点固定（camera-lock の System）
    ├── grabbable.rb     … 図形を掴んで動かすコンポーネント（grab-target）
    ├── label.rb         … 日本語の文字を出すコンポーネント（label）
    └── anchor.rb        … 回転の中心を図形の端にするコンポーネント（anchor）
docs/
└── reference.md         … 使い方と API の一覧
examples/
├── index.html
├── grab/                … マウスで図形を掴んで動かすデモ
├── spin/                … Ruby で定義したコンポーネントで図形を回すデモ
├── garden/              … Ruby で定義した System で花を植えて間引くデモ
└── scene/               … AFrame.scene でシーンを組み立てるデモ
```

## License

MIT