# aframe_picoruby

[A-Frame](https://aframe.io/) のシーンを [PicoRuby.wasm](https://github.com/picoruby/picoruby/tree/master/mrbgems/picoruby-wasm) の Ruby で操作するための小さなライブラリです。
マウスで図形を掴んで動かす処理（`examples/grab/`）を、JavaScript の A-Frame コンポーネントを書かずに Ruby だけで実装できます。

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

`grab-target` 属性を付けた図形は、`require "aframe"` するだけでマウスで掴めるようになります（`AFrame::Grabbable` が `grab-target` という部品を登録します。A-Frame にはハンドトラッキング用の `grabbable` という部品がもともとあるので、名前を分けています）。`raycaster` の `objects` には、掴む図形を選ぶセレクター（ここでは `.my-grabbable`）を書きます。`<a-scene camera-lock>` は、図形を掴んでいる間に視点が回らないようにする System です（`camera: a-camera; raycaster: [raycaster]` で対象を変えられます）。掴める（`enabled` な）`grab-target` の上で押したときだけ視点を止めます。

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

掴んだ図形は `grab`、離した図形は `release` のイベントを出します（`detail.cursorEl` は掴んだカーソル）。掴んでいる間は、要素が `grabbed` の状態になります（`el.is("grabbed")`）。

```ruby
AFrame::Entity.all("[grab-target]").each do |shape|
  shape.addEventListener("grab") { |event| puts "grab" }
  shape.addEventListener("release") { |event| puts "#{shape.position.x}, #{shape.position.y}, #{shape.position.z}" }
end
```

- `position` は親から見た位置です。コントローラーで離した図形はシーンの直下に戻り、マウスで掴む図形はもともとシーンの直下に置く前提なので、どちらもワールド座標になります（マウスで掴む図形を、回転や移動のある親の中に置いた場合はワールド座標になりません）
- 同時に離れた図形がいくつあっても、先に全部を離してから `release` を出します

### 掴み方を変える

設定は `grab-target` 属性に書きます（属性を書き換えれば、途中でも変わります）。

```html
<a-box grab-target="grab_color: #ffff00; pause_animation: false"></a-box>
```

```ruby
AFrame::Entity.create("a-box", grab_target: { grab_color: "none" })
```

| 設定 | 既定 | 内容 |
|---|---|---|
| `grab_color` | `#ffffff` | 掴んでいる間の色。`none` なら色を変えない |
| `pause_animation` | `true` | 掴んでいる間、`animation` を止める |
| `enabled` | `true` | `false` で掴めなくする。掴んでいる最中なら離す（`release` も出す） |
| `raycaster` | `[raycaster]` | マウスで掴んだ図形が追う ray の、`raycaster` を持つ要素のセレクター |

- 掴めなくするのをやめるには `removeAttribute("grab-target")` で外します（掴んでいる最中なら離します）
- マウスで掴んでいる最中は、`grab_distance` で ray の起点からの距離を変えられます。`examples/grab/` では、ホイールで図形を近づけたり遠ざけたりしています

```ruby
AFrame::Grabbable.instances.each do |item|          # grab-target の部品の全部
  item.grab_distance += 0.5 if item.following_ray?  # マウスで掴んでいる最中のもの
end
```

- 掴んでいる間の色と `animation` は、`grab-target` が要素の `color` と `animation` を直接変えています。別の部品に分けると設定の書き方が変わってしまうので、今はこの形にしています。自分で見た目を変えたいときは `grab_color: none; pause_animation: false` にして、`grab` / `release` イベントか `grabbed` の状態（`el.is("grabbed")`）を使ってください
- 離すきっかけになる `window` の `mouseup` は、`grab-target` と同じ名前の System が1つだけ聞いていて、そこから全部の `grab-target` を離します

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
- 省略形：`scale: 0.5` は3軸とも同じ倍率（`"0.5 0.5 0.5"`）にします（そのまま渡すと A-Frame は x だけと読み、`0.5 1 1` になります）。プロパティが複数ある部品に `true` を渡すと、既定値のまま付けます（`swim: true` は `swim=""` と同じ）。プロパティが1つの部品（`visible: true` など）や、知らない名前には `"true"` のまま渡します

  ```ruby
  AFrame::Entity.create("a-entity", gltf_model: "#whale-shark", scale: 0.5, swim: true)
  ```
- Hash の値に `;` が入っていると（`label: { value: "a; b" }`）、`;` が区切りと読まれて切れてしまうので、そのときは文字列にまとめずにプロパティごとに渡します（A-Frame が知っている部品のとき）
- `entity.set_attribute(:label, :value, "つかんだ！")` のように3つ渡すと、部品のプロパティを1つだけ変えます（ほかのプロパティはそのまま。`;` を含む文字も渡せます）
- Symbol の属性名の `_` は `-` に直します（`look_controls:` → `look-controls`）。同じ部品を複数付けるときの `__` はそのまま残します（`animation__spin:`）
- 作った直後から使えます。A-Frame の読み込みが終わる（`hasLoaded` が true になる）のは、イベントループの次の番です

### ブロックでまとめて作る（AFrame.scene）

```ruby
AFrame.scene do
  entity position: [0, 1.6, -3] do
    box color: "#4CC3D9", spin_box: { speed: 45 }
    6.times do |i|
      sphere position: [i * 0.5, 1, 0], radius: 0.2, color: "hsl(#{i * 60}, 80%, 60%)"
    end
    tag "a-gltf-model", src: "#fish"
  end
end
```

- ブロックの中では、A-Frame が知っているタグ（標準のもの＋`AFRAME.registerPrimitive` で足したもの）と `entity` を、`a-` を取った名前のメソッドで作れます（`a-gltf-model` → `gltf_model`）。属性は `Entity.create` と同じ書き方です
- 一覧にない名前は `NoMethodError` になります。一覧にないタグは `tag "a-foo", ...` で作ります
- 名前が Builder や Ruby に元からあるメソッド（`tag` / `created` / `initialize` / `puts` / `print` / `loop` など）とかぶるタグには、メソッドを作りません。`registerPrimitive("a-loop", ...)` のようなタグは `tag "a-loop", ...` で作ってください（`loop` と書くと Ruby の `loop` が呼ばれます）
- ブロックを付けると、その要素の子を作れます。各メソッドは作った `Entity` を返し、`AFrame.scene` は一番外側で作った要素の配列を返します
- `AFrame.scene(parent: "#group") { ... }` で、作る場所を `a-scene` 以外にできます（`Entity.create` の `parent:` と同じ）
- ブロックは `instance_eval` で動くので、外側のローカル変数は使えますが、外側の `self` のメソッド（トップレベルで定義したメソッドなど）は呼べません

### 日本語の文字を出す（label）

A-Frame の `text` のフォントには日本語の文字がないので、日本語を出すには `label` 部品を使います。端末のフォントで canvas に描いて、要素の mesh として出します（canvas は DOM に置きません）。

```html
<a-entity position="0 2.5 -2" label="value: 持てるよ; height: 0.3"></a-entity>
```

```ruby
hint = AFrame::Entity.create("a-entity", position: [0, 2.5, -2], label: { value: "持てるよ", height: 0.3 })
hint.set_attribute(:label, :value, "つかんだ！")   # 文字だけ変える
```

| 設定 | 既定 | 内容 |
|---|---|---|
| `value` | `""` | 出す文字 |
| `height` | `0.3` | 板の高さ（m）。幅は文字数から決まる |
| `color` | `#ffffff` | 文字の色 |
| `background` | `rgba(0, 0, 0, 0.55)` | 板の色（角の丸い板） |
| `font` | `bold 96px sans-serif` | canvas に描くフォント（CSS の書き方）。px が大きいほど細かく描く |

- `value` / `color` / `background` / `font` を変えると描き直し、`height` だけなら大きさだけ変えます。要素を消すと、テクスチャなども破棄します
- 端末に入っているフォントで描くので、ネットにつながっていなくても出せます。Quest のブラウザに日本語フォントがあるか、近づいたときにぼやけないかは、まだ実機で確かめていません
- `examples/grab/` では、箱の上の札が、掴むと「つかんだ！」、離すと「持てるよ」に変わります（`grab` / `release` イベントを聞いているだけで、部品どうしは直接触っていません）

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
- `tick` はフレームごとにまとめて呼びます（`Scene.run` を呼ばなくても動きます。`Scene.on_tick` の処理より先に呼びます）。要素を `pause` している間は呼ばれません
- `register "spin-box", multiple: true` にすると、1つの要素に `spin-box__fast` / `spin-box__slow` のように複数付けられます（A-Frame の `multiple`）。それぞれが別のインスタンスで、`id` で `__` の後ろ（`"fast"`）を読めます。Ruby からは `spin_box__fast: { speed: 180 }` と書きます

### シーン全体を見る処理を作る（AFrame::System）

部品が要素1つずつに付くのに対して、System はシーンに1つだけあり、全体を見る処理を書けます（`examples/garden/`）。

```ruby
class Garden < AFrame::System
  register "garden"
  schema max: 8                    # <a-scene garden="max: 20"> で変えられる

  def tick(time, delta)
    flowers = Flower.instances     # 生きている Flower 部品の全部（作った順）
    flowers.first.el.js.remove if flowers.size > data.max
  end
end
```

- 書き方は `AFrame::Component` と同じです：`register` / `schema` と、フック `init` / `update(old_data)` / `tick(time, delta)` / `pause` / `play`。A-Frame の System は消えないので `remove` はありません
- `el` は `a-scene` の Entity、`data` は `a-scene` に書いた属性（`garden="max: 20"`）です
- 1フレームの中では、部品の `tick` を全部呼んだ後に System の `tick` を呼び、その後に `Scene.on_tick` の処理を呼びます（A-Frame と同じ順）
- `pause` / `play` は、シーンを `pause` / `play` したときに呼びます（A-Frame は System の `pause` / `play` を呼ばないので、`a-scene` のイベントから呼んでいます）
- 部品クラスの `instances`（`Flower.instances`）で、その部品の生きているインスタンスを配列で取れます

### 毎フレームの処理をどこに書くか

フレームごとの処理は、まず部品（`AFrame::Component` の `tick`）か System（`AFrame::System` の `tick`）に書いてください。A-Frame の書き方（ECS）と同じで、処理がどの要素・どのシーンのものかがはっきりし、要素を消せば処理も止まります。

- 要素ごとの動き（回す、伸ばす、追いかける）→ 部品の `tick`
- シーン全体を見る処理（数える、間引く、まとめて動かす）→ System の `tick`
- `AFrame::Scene.on_tick { |time, delta| ... }` は、クラスを書くほどでもない小さな試しのコード向けの逃げ道です。部品や System の外に処理が散らばるので、長く使うコードでは部品か System に移してください

> npm への公開前は、importmap の `aframe` に手元の `lib/aframe.rb` の URL（例：`/lib/aframe.rb`）を指定してください。

## API

| API | 内容 |
|---|---|
| `AFrame::Scene.ready(selector = "a-scene")` | シーンを探し、読み込みが終わるまで待つ。見つからなければ例外 |
| `AFrame::Scene.element` | `ready` で見つけた `a-scene` 要素 |
| `AFrame::Scene.on_tick { \|time, delta\| }` | 小さな試し向け。ふだんは部品か System の `tick` に書く。毎フレーム呼ぶ処理を登録する（引数はミリ秒。省略してよい）。A-Frame の `tick` の中で、そのフレームを描く前に呼ぶので、変更はそのフレームに出る。中で `await` は使えない。例外を出してもコンソールに出すだけで、ほかの処理は呼ばれる |
| `AFrame::Scene.run` | A-Frame の描画ループに合わせて `on_tick` の処理を呼び続ける（戻ってこない）。VR 中も止まらない。シーンを `pause` している間は呼ばれない |
| `AFrame::Scene.start` | `run` と同じく `on_tick` の処理を呼び始めるが、すぐに戻ってくる |
| `AFrame::Entity.all(selector)` / `Entity.new(js)` | A-Frame 要素の薄いラッパー。`color` / `color=` / `position` / `rotation` / `scale` / `set_position(x, y, z)` / `pause_animation` / `play_animation` / `js`。ほかのメソッドは JS の要素に渡す（`box.object3D.visible`） |
| `Entity#position` / `#rotation` / `#scale` | `object3D` の `position`（THREE.Vector3）/ `rotation`（THREE.Euler、ラジアン）/ `scale`（THREE.Vector3）をそのまま返す。書き換えると要素が動く（`el.position.x = 1`、`el.rotation.y += 0.1`）。`set_position(x, y, z)` は `position.set(x, y, z)` と同じ |
| `AFrame::Entity.find(selector)` | 最初に見つかった要素を Entity で返す。見つからなければ `nil`（`querySelector` と同じ） |
| `AFrame.scene(parent: nil) { }` | ブロックの中で `box` / `sphere` / `entity` / `tag "a-foo"` などを呼んで要素を作る。一番外側で作った Entity の配列を返す |
| `AFrame::Entity.create(tag, parent: nil, **attributes)` | 要素を作り、`parent`（Entity、JS の要素、セレクターの文字列。省略時は `a-scene`）の子にして、Entity で返す。セレクターが見つからなければ例外 |
| `Entity#set_attribute(name, value)` / `Entity#set_attribute(name, property, value)` / `Entity#append(child)` | 属性を設定する / 部品のプロパティを1つだけ変える / 子を付け替える（`appendChild`） |
| `class X < AFrame::Component` / `register(name, multiple: false)` / `schema(hash)` | Ruby で A-Frame の部品を定義する。`init` / `update(old_data)` / `tick(time, delta)` / `remove` を上書きし、`el` / `data` / `id` / `deg_to_rad` / `rad_to_deg` を使う |
| `class X < AFrame::System` / `register(name)` / `schema(hash)` | Ruby で A-Frame の System を定義する。`init` / `update(old_data)` / `tick(time, delta)` / `pause` / `play` を上書きし、`el`（a-scene）/ `data` を使う |
| `X.instances`（X は Component のサブクラス） | その部品の生きているインスタンスの配列（作った順） |
| `grab-target` 属性（`AFrame::Grabbable`） | 付けた要素をマウスや VR コントローラー（`laser-controls` など）で掴んで動かせるようにする。設定は `grab_color` / `pause_animation` / `enabled` / `raycaster`。掴むと `grab`、離すと `release` のイベントを出し、掴んでいる間は `grabbed` の状態になる |
| `AFrame::Grabbable.instances` / `#grab_distance` / `#grab_distance=` / `#following_ray?` / `#grabbed?` | `grab-target` の部品の一覧と、マウスで掴んでいる図形の ray の起点からの距離（負の値は 0 になる） |
| `label` 属性（`AFrame::Label`） | 日本語を含む文字を、角の丸い板に描いて出す。設定は `value` / `height` / `color` / `background` / `font` |
| `camera-lock` 属性（`AFrame::CameraLock`、a-scene に付ける System） | 掴める `grab-target` の上でマウスを押したときに `look-controls` を止め、離したときに戻す。設定は `camera`（既定 `a-camera`）と `raycaster`（既定 `[raycaster]`） |
| `AFrame::CameraLock.install(camera: "a-camera", raycaster: "[raycaster]")` | 前の書き方との互換のために残している。`a-scene` に `camera-lock` 属性を付けるだけ |

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
    ├── system.rb        … Ruby で書く A-Frame の System
    ├── builder.rb       … AFrame.scene（ブロックで要素を作る）
    ├── camera_lock.rb   … 掴んでいる間の視点固定（camera-lock の System）
    ├── grabbable.rb     … 図形を掴んで動かす部品（grab-target）
    └── label.rb         … 日本語の文字を出す部品（label）
examples/
├── index.html
├── grab/                … マウスで図形を掴んで動かすデモ
├── spin/                … Ruby で定義した部品で図形を回すデモ
├── garden/              … Ruby で定義した System で花を植えて間引くデモ
└── scene/               … AFrame.scene でシーンを組み立てるデモ
```

## License

MIT
