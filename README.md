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
  <a-entity position="0 0 4">
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
<a-entity position="0 0 4">
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
  item.on_release { |entity| puts "#{entity.position.x}, #{entity.position.y}, #{entity.position.z}" }
end
```

- `entity.position` は親から見た位置です。コントローラーで離した図形はシーンの直下に戻り、マウスで掴む図形はもともとシーンの直下に置く前提なので、どちらもワールド座標になります（マウスで掴む図形を、回転や移動のある親の中に置いた場合はワールド座標になりません）
- 中で `await` を使えます。待っている間も、ほかの図形を掴む・離す処理や毎フレームの処理は止まりません
- 同時に離れた図形がいくつあっても、先に全部を離してからフックを呼びます。フックが例外を出してもコンソールに出すだけで、ほかのフックは呼ばれます

### 掴み方を変える

```ruby
items = AFrame::Grabbable.attach_all(".my-grabbable",
  grab_color: "#ffff00",    # 掴んでいる間の色。nil なら色を変えない（既定は "#ffffff"）
  pause_animation: false)   # 掴んでいる間も animation を止めない（既定は true）

item = items.first
item.enabled = false        # 掴めなくする。掴んでいる最中なら離す（on_release も呼ぶ）
item.grab_distance += 0.5   # マウスで掴んでいる最中に、ray の起点からの距離を変える
item.detach                 # 掴めなくし、イベントリスナーを外し、Grabbable.items から取り除く（元に戻せない）
```

`examples/grab/` では、マウスで掴んでいる間にホイールで図形を近づけたり遠ざけたりできます。

### Ruby から要素を作る

```ruby
group = AFrame::Entity.create("a-entity", id: "group", position: [0, 0, -3])
AFrame::Entity.create("a-box", parent: group, position: [0, 1, 0], color: "tomato",
                      animation: { property: "rotation", to: "0 360 0", loop: true, dur: 2000 })
AFrame::Entity.create("a-sphere", parent: "#group", position: [1, 1, 0], radius: 0.3)

group = AFrame::Entity.find("#group")   # 1つだけ探す。見つからなければ nil
```

- `parent:` には Entity、JS の要素、セレクターの文字列を渡せます。セレクターが見つからなければ例外になり、要素は作りません

- 値は A-Frame の属性の文字列に直して渡します：配列と座標の Hash（`{ x:, y:, z: }`）は `"0 1 0"`、そのほかの Hash は `"property: rotation; to: 0 360 0; ..."`、そのほかは `to_s`
- Symbol の属性名の `_` は `-` に直します（`look_controls:` → `look-controls`）。同じ部品を複数付けるときの `__` はそのまま残します（`animation__spin:`）
- 作った直後から使えます。A-Frame の読み込みが終わる（`hasLoaded` が true になる）のは、イベントループの次の番です

### A-Frame のプロパティを触る

`Entity` にないメソッドは、そのまま JS の要素に渡します（PicoRuby.wasm の `JS::Object` と同じく、プロパティの読み書きかメソッド呼び出しになります）。

```ruby
box = AFrame::Entity.all("#box").first
box.object3D.visible = false
box.emit("hello")
box.addEventListener("click") { |event| puts "click" }
```

- `Entity` 自身のメソッド（`color` / `position` など）と、Ruby の `Object` のメソッド（`class` / `hash` / `send` など）は渡しません。そのときは `entity.js.hash` のように `js` を使います
- `?` や `!` で終わる名前は JS に渡せず、`NoMethodError` になります

### Ruby で部品（コンポーネント）を作る

JS の `AFRAME.registerComponent` にあたるものを Ruby のクラスで書けます（`examples/spin/`）。

```ruby
class SpinBox < AFrame::Component
  register "spin-box"
  schema speed: 30   # { type: :number, default: 30 } と同じ

  def tick(time, delta)
    el.rotation.y += deg_to_rad(data.speed * delta / 1000)
  end
end
```

```html
<a-box spin-box="speed: 90"></a-box>
```

- `schema` は A-Frame の schema と同じ形です（Symbol でも文字列でもよい）。Hash でない値は既定値（`{ default: 値 }`）として扱い、型は A-Frame が既定値から決めます（数値 → number、true / false → boolean、配列 → array、それ以外 → string）。`schema radius: 8, label: "fish", speed: { type: :number, default: 15 }` のように混ぜて書けます。座標（vec3 など）の既定値は Hash になるので、`{ type: :vec3, default: { x: 0, y: 0, z: 0 } }` と書きます。`schema type: :number, default: 1` のように一番上に `type` か `default` を書くと、プロパティが1つだけの部品になり、`data` は値そのものになります（そのため `type` / `default` という名前のプロパティは省略形で書けません）
- `register` より前に書いた要素にも、後から作った要素（`Entity.create(..., spin_box: { speed: 90 })`）にも付きます
- 上書きできるのは `init` / `update(old_data)` / `tick(time, delta)` / `remove` です。`initialize` は上書きしないでください
- `el` は要素の `Entity`、`data` は属性を読んだ結果（`data.speed`）、`component` は JS の部品です
- フックは A-Frame の中から同期で呼ぶので、中で `await` は使えません。例外を出してもコンソールに出すだけです
- `tick` は `Scene.on_tick` からまとめて呼びます（`Scene.run` を呼ばなくても動きます）。要素を `pause` している間は呼ばれません
- `register "spin-box", multiple: true` にすると、1つの要素に `spin-box__fast` / `spin-box__slow` のように複数付けられます（A-Frame の `multiple`）。それぞれが別のインスタンスで、`id` で `__` の後ろ（`"fast"`）を読めます。Ruby からは `spin_box__fast: { speed: 180 }` と書きます

> npm への公開前は、importmap の `aframe` に手元の `lib/aframe.rb` の URL（例：`/lib/aframe.rb`）を指定してください。

## API

| API | 内容 |
|---|---|
| `AFrame::Scene.ready(selector = "a-scene")` | シーンを探し、読み込みが終わるまで待つ。見つからなければ例外 |
| `AFrame::Scene.element` | `ready` で見つけた `a-scene` 要素 |
| `AFrame::Scene.on_tick { \|time, delta\| }` | 毎フレーム呼ぶ処理を登録する（引数はミリ秒。省略してよい）。A-Frame の `tick` の中で、そのフレームを描く前に呼ぶので、変更はそのフレームに出る。中で `await` は使えない。例外を出してもコンソールに出すだけで、ほかの処理は呼ばれる |
| `AFrame::Scene.run` | A-Frame の描画ループに合わせて `on_tick` の処理を呼び続ける（戻ってこない）。VR 中も止まらない。シーンを `pause` している間は呼ばれない |
| `AFrame::Scene.start` | `run` と同じく `on_tick` の処理を呼び始めるが、すぐに戻ってくる |
| `AFrame::Entity.all(selector)` / `Entity.new(js)` | A-Frame 要素の薄いラッパー。`color` / `color=` / `position` / `rotation` / `scale` / `set_position(x, y, z)` / `pause_animation` / `play_animation` / `js`。ほかのメソッドは JS の要素に渡す（`box.object3D.visible`） |
| `Entity#position` / `#rotation` / `#scale` | `object3D` の `position`（THREE.Vector3）/ `rotation`（THREE.Euler、ラジアン）/ `scale`（THREE.Vector3）をそのまま返す。書き換えると要素が動く（`el.position.x = 1`、`el.rotation.y += 0.1`）。`set_position(x, y, z)` は `position.set(x, y, z)` と同じ |
| `AFrame::Entity.find(selector)` | 最初に見つかった要素を Entity で返す。見つからなければ `nil`（`querySelector` と同じ） |
| `AFrame::Entity.create(tag, parent: nil, **attributes)` | 要素を作り、`parent`（Entity、JS の要素、セレクターの文字列。省略時は `a-scene`）の子にして、Entity で返す。セレクターが見つからなければ例外 |
| `Entity#set_attribute(name, value)` / `Entity#append(child)` | 属性を設定する / 子を付け替える（`appendChild`） |
| `class X < AFrame::Component` / `register(name, multiple: false)` / `schema(hash)` | Ruby で A-Frame の部品を定義する。`init` / `update(old_data)` / `tick(time, delta)` / `remove` を上書きし、`el` / `data` / `id` / `deg_to_rad` / `rad_to_deg` を使う |
| `AFrame::Grabbable.attach_all(selector, raycaster: "[raycaster]", grab_color: "#ffffff", pause_animation: true)` | 要素をマウスや VR コントローラー（`laser-controls` など）で掴んで動かせるようにする。掴んでいる間は `grab_color` になり（`nil` なら変えない）、`pause_animation` が true なら `animation` が止まる |
| `Grabbable#enabled=` / `#enabled?` | 掴める・掴めないを切り替える。掴んでいる最中に false にすると離し、`on_release` を呼ぶ |
| `Grabbable#grab_distance` / `#grab_distance=` | マウスで掴んでいる図形の、ray の起点からの距離（負の値は 0 になる） |
| `Grabbable#detach` | 掴めなくし、`mousedown` のリスナーを外し、`Grabbable.items` から取り除く（掴んでいる最中なら離す）。後から `enabled = true` にしても掴めない |
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
    ├── component.rb     … Ruby で書く A-Frame の部品
    ├── camera_lock.rb   … 掴んでいる間の視点固定
    └── grabbable.rb     … 図形を掴んで動かす
examples/
├── index.html
├── grab/                … マウスで図形を掴んで動かすデモ
└── spin/                … Ruby で定義した部品で図形を回すデモ
```

## License

MIT
