# aframe_picoruby

[A-Frame](https://aframe.io/) のシーンを [PicoRuby.wasm](https://github.com/picoruby/picoruby/tree/master/mrbgems/picoruby-wasm) の Ruby で操作するための小さなライブラリです。
マウスで図形を掴んで動かす処理（`examples/grab/`）を、JavaScript の A-Frame コンポーネントを書かずに Ruby だけで実装できます。

## クイックスタート

ライブラリは分割したファイルのまま配布しています。`require "aframe"` の中の `require "aframe/..."` は
[importmap-picoruby](https://github.com/itojum/importmap-picoruby) が解決するため、**importmap-picoruby が必須**です
（`<script type="text/ruby" src="...">` で `lib/aframe.rb` を直接読み込むだけでは動きません）。

```html
<script src="https://aframe.io/releases/1.8.0/aframe.min.js"></script>

<a-scene>
  <a-entity position="0 1.6 4">
    <a-camera look-controls wasd-controls>
      <a-entity cursor="rayOrigin: mouse" raycaster="objects: .my-grabbable"></a-entity>
    </a-camera>
  </a-entity>
  <a-box class="my-grabbable" position="0 1.5 -2" color="#4CC3D9"></a-box>
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

AFrame::Scene.ready                            # a-scene の読み込みを待つ
AFrame::CameraLock.install                     # 図形を掴んでいる間は視点を固定する
AFrame::Grabbable.attach_all(".my-grabbable")  # 図形をマウスで掴めるようにする
AFrame::Scene.run                              # フレームループ（戻ってこない）
```

VR コントローラーでも掴みたいときは、カメラと同じリグの中で、`a-camera` より後ろにコントローラーを置きます。リグに入れるのは頭と手の位置をそろえるため、後ろに置くのは `raycaster` の既定値 `"[raycaster]"` が最初に見つかった要素（マウス用のカーソル）を指すためです。

```html
<a-entity position="0 1.6 4">
  <a-camera look-controls wasd-controls>
    <a-entity cursor="rayOrigin: mouse" raycaster="objects: .my-grabbable"></a-entity>
  </a-camera>
  <a-entity laser-controls="hand: left" raycaster="objects: .my-grabbable"></a-entity>
  <a-entity laser-controls="hand: right" raycaster="objects: .my-grabbable"></a-entity>
</a-entity>
```

マウスで掴んだ図形は毎フレーム ray を追い、コントローラーで掴んだ図形はコントローラーの子になって手と一緒に動きます。

### 掴んだとき・離したときの処理

```ruby
AFrame::Grabbable.attach_all(".my-grabbable").each do |item|
  item.on_grab    { |entity| puts "grab" }
  item.on_release { |entity| p entity.position }
end
```

- `entity.position` は親から見た位置です。コントローラーで離した図形はシーンの直下に戻り、マウスで掴む図形はもともとシーンの直下に置く前提なので、どちらもワールド座標になります（マウスで掴む図形を、回転や移動のある親の中に置いた場合はワールド座標になりません）
- 中で `await` を使えます。待っている間も、ほかの図形を掴む・離す処理や毎フレームの処理は止まりません
- 同時に離れた図形がいくつあっても、先に全部を離してからフックを呼びます。フックが例外を出してもコンソールに出すだけで、ほかのフックは呼ばれます

> npm への公開前は、importmap の `aframe` に手元の `lib/aframe.rb` の URL（例：`/lib/aframe.rb`）を指定してください。

## API

| API | 内容 |
|---|---|
| `AFrame::Scene.ready(selector = "a-scene")` | シーンを探し、読み込みが終わるまで待つ。見つからなければ例外 |
| `AFrame::Scene.element` | `ready` で見つけた `a-scene` 要素 |
| `AFrame::Scene.on_tick { }` | 毎フレーム呼ぶ処理を登録する |
| `AFrame::Scene.run` | A-Frame の描画ループに合わせて `on_tick` の処理を呼び続ける（戻ってこない）。VR 中も止まらない。シーンを `pause` している間は呼ばれない |
| `AFrame::Entity.all(selector)` / `Entity.new(js)` | A-Frame 要素の薄いラッパー。`color` / `color=` / `position` / `set_position(x, y, z)` / `pause_animation` / `play_animation` / `js` |
| `AFrame::Grabbable.attach_all(selector, raycaster: "[raycaster]")` | 要素をマウスや VR コントローラー（`laser-controls` など）で掴んで動かせるようにする。掴んでいる間は白くなり、`animation` が止まる |
| `Grabbable#on_grab { \|entity\| }` / `#on_release { \|entity\| }` | 掴んだとき・離したときに呼ぶ処理を登録する（複数登録できる）。`attach_all` が返す配列の要素に対して呼ぶ |
| `AFrame::CameraLock.install(camera: "a-camera", raycaster: "[raycaster]")` | raycaster が図形と交差しているときに押されたマウスでは `look-controls` を止める |

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
    ├── scene.rb         … シーンの読み込み待ちとフレームループ
    ├── entity.rb        … A-Frame 要素の薄いラッパー
    ├── camera_lock.rb   … 掴んでいる間の視点固定
    └── grabbable.rb     … 図形を掴んで動かす
examples/
├── index.html
└── grab/                … マウスで図形を掴んで動かすデモ
```

## License

MIT
