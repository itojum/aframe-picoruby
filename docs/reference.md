# リファレンス

aframe_picoruby の使い方と API をまとめたページです。はじめて使うときは [README](../README.md) のクイックスタートから読んでください。

## 目次

- [掴んで動かす](#掴んで動かす)：`grab-target` と `camera-lock`
- [要素を作る](#要素を作る)：`Entity.create` と `AFrame.scene`
- [位置・回転・大きさを変える](#位置回転大きさを変える)：回転の単位（度とラジアン）
- [日本語の文字を出す](#日本語の文字を出す)：`label`
- [イベントを受け取る](#イベントを受け取る)：`on` / `once` / `off`、コンポーネントのクラスに書く `on`
- [A-Frame のプロパティを触る](#a-frame-のプロパティを触る)：`method_missing`
- [コンポーネントを作る](#コンポーネントを作る)：`AFrame::Component`
- [コンポーネントの中で待つ](#コンポーネントの中で待つ)：`after` / `every`
- [シーン全体を見る処理を作る](#シーン全体を見る処理を作る)：`AFrame::System`
- [補間と乱数](#補間と乱数)：`AFrame::Easing` / `AFrame.random`、animation を秒で書く `AFrame.animation`
- [毎フレームの処理をどこに書くか](#毎フレームの処理をどこに書くか)
- [API 一覧](#api-一覧)

## 掴んで動かす

`grab-target` 属性を付けた図形は、`require "aframe"` するだけでマウスで掴めるようになります（`AFrame::Grabbable` が `grab-target` というコンポーネントを登録します。A-Frame にはハンドトラッキング用の `grabbable` というコンポーネントがもともとあるので、名前を分けています）。`raycaster` の `objects` には、掴む図形を選ぶセレクター（README のクイックスタートでは `.my-grabbable`）を書きます。`<a-scene camera-lock>` は、図形を掴んでいる間に視点が回らないようにする System です（`camera: a-camera; raycaster: [raycaster]` で対象を変えられます）。掴める（`enabled` な）`grab-target` の上で押したときだけ視点を止めます。

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
  shape.on(:grab) { puts "grab" }
  shape.on(:release) { puts "#{shape.position.x}, #{shape.position.y}, #{shape.position.z}" }
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
- マウスで掴んでいる最中は、`grab_distance` で ray の起点からの距離を変えられます。[`examples/grab/`](../examples/grab/) では、ホイールで図形を近づけたり遠ざけたりしています

```ruby
AFrame::Grabbable.instances.each do |item|          # grab-target のコンポーネントの全部
  item.grab_distance += 0.5 if item.following_ray?  # マウスで掴んでいる最中のもの
end
```

- 掴んでいる間の色と `animation` は、`grab-target` が要素の `color` と `animation` を直接変えています。別のコンポーネントに分けると設定の書き方が変わってしまうので、今はこの形にしています。自分で見た目を変えたいときは `grab_color: none; pause_animation: false` にして、`grab` / `release` イベントか `grabbed` の状態（`el.is("grabbed")`）を使ってください
- 離すきっかけになる `window` の `mouseup` は、`grab-target` と同じ名前の System が1つだけ受け取っていて、そこから全部の `grab-target` を離します

## 要素を作る

```ruby
group = AFrame::Entity.create("a-entity", id: "group", position: [0, 0, -3])
AFrame::Entity.create("a-box", parent: group, position: [0, 1, 0], color: "tomato",
                      animation: { property: "rotation", to: "0 360 0", loop: true, dur: 2000 })
AFrame::Entity.create("a-sphere", parent: "#group", position: [1, 1, 0], radius: 0.3)

group = AFrame::Entity.find("#group")   # 1つだけ探す。見つからなければ nil
```

- `parent:` には Entity、JS の要素、セレクターの文字列を渡せます。セレクターが見つからなければ例外になり、要素は作りません

- 値は A-Frame の属性の文字列に直して渡します：配列と座標の Hash（`{ x:, y:, z: }`）は `"0 1 0"`、そのほかの Hash は `"property: rotation; to: 0 360 0; ..."`、そのほかは `to_s`
- コンポーネントを既定値のまま付けるときは、属性より前に Symbol で並べます（HTML の `<a-entity swim grab-target>` と同じ）。名前の `_` は属性名と同じく `-` に直します（`:grab_target` → `grab-target`）。文字列で渡すと、属性名と同じく書いたまま使います（`"grab-target"`）

  ```ruby
  AFrame::Entity.create("a-entity", :swim, :grab_target, gltf_model: "#whale-shark", scale: 0.5)
  ```

  書き分けのルールは「Symbol は既定値で付ける、Hash は設定、それ以外は値」です。`true` はいつも `"true"` として渡します（`visible: true` は `visible="true"`）
- 省略形：`scale: 0.5` は3軸とも同じ倍率（`"0.5 0.5 0.5"`）にします（そのまま渡すと A-Frame は x だけと読み、`0.5 1 1` になります）
- Hash の値に `;` が入っていると（`label: { value: "a; b" }`）、`;` が区切りと読まれて切れてしまうので、そのときは文字列にまとめずにプロパティごとに渡します（A-Frame が知っているコンポーネントのとき）
- `entity.set_attribute(:label, :value, "つかんだ！")` のように3つ渡すと、コンポーネントのプロパティを1つだけ変えます（ほかのプロパティはそのまま。`;` を含む文字も渡せます）
- Symbol の属性名の `_` は `-` に直します（`look_controls:` → `look-controls`）。同じコンポーネントを複数付けるときの `__` はそのまま残します（`animation__spin:`）
- 作った直後から使えます。A-Frame の読み込みが終わる（`hasLoaded` が true になる）のは、イベントループの次の番です

### 作った要素を書き換える

`set_attribute` でコンポーネントのプロパティを書き換えるときは、変えたいプロパティだけを Hash で渡します。渡さなかったプロパティは、そのまま残ります（A-Frame の `setAttribute` にオブジェクトを渡したときと同じです）。

```ruby
hint.set_attribute(:label, value: "つかんだ！")                     # value だけ変える
hint.set_attribute(:label, value: "つかんだ！", color: "#ffeeaa")   # 2つ変える
hint.set_attribute(:label, :value, "つかんだ！")                    # 1つだけなら3つ渡す形でもよい
```

- 2つ以上変えるときも、呼び出しは1回で済みます（コンポーネントの `update` も1回だけ呼ばれます）
- `;` を含む値もそのまま渡せます（`value: "a; b"`）
- Ruby で書いたコンポーネントでも同じです

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

- ブロックの中では、A-Frame が知っているタグ（標準のもの＋`AFRAME.registerPrimitive` で足したもの）と `entity` を、`a-` を取った名前のメソッドで作れます（`a-gltf-model` → `gltf_model`）。属性は `Entity.create` と同じ書き方で、既定値のまま付けるコンポーネントも Symbol で書けます（`entity :swim, gltf_model: "#whale-shark"`）
- 一覧にない名前は `NoMethodError` になります。一覧にないタグは `tag "a-foo", ...` で作ります
- 名前が Builder や Ruby に元からあるメソッド（`tag` / `created` / `initialize` / `puts` / `print` / `loop` など）とかぶるタグには、メソッドを作りません。`registerPrimitive("a-loop", ...)` のようなタグは `tag "a-loop", ...` で作ってください（`loop` と書くと Ruby の `loop` が呼ばれます）
- ブロックを付けると、その要素の子を作れます。各メソッドは作った `Entity` を返し、`AFrame.scene` は一番外側で作った要素の配列を返します
- `AFrame.scene(parent: "#group") { ... }` で、作る場所を `a-scene` 以外にできます（`Entity.create` の `parent:` と同じ）
- ブロックは `instance_eval` で動くので、外側のローカル変数は使えますが、外側の `self` のメソッド（トップレベルで定義したメソッドなど）は呼べません

## 位置・回転・大きさを変える

位置・回転・大きさは、属性で書く方法と、`Entity#position` / `#rotation` / `#scale` で `object3D` を直接書き換える方法があります。**回転だけは、この2つで単位が違います。**

| 書き方 | 回転の単位 | 例（Y 軸で 90 度） |
|---|---|---|
| 属性（HTML、`Entity.create`、`set_attribute`） | 度 | `rotation: [0, 90, 0]` |
| `Entity#rotation`（THREE.Euler） | ラジアン | `el.rotation.y = Math::PI / 2` |

```ruby
box = AFrame::Entity.create("a-box", rotation: [0, 90, 0])   # 度

# コンポーネントや System の中では deg_to_rad / rad_to_deg が使えます
class Turn < AFrame::Component
  register

  def tick(time, delta)
    el.rotation.y += deg_to_rad(90 * delta_seconds)          # 1秒に 90 度
  end
end

AFrame::Entity.create("a-box", :turn, position: [1, 1, -3])   # turn を付けた箱が回る

# コンポーネントの外では、度に Math::PI / 180 を掛けます
box.on(:click) { box.rotation.y += 45 * Math::PI / 180 }    # クリックするたびに 45 度
```

- `el.rotation.y = 90` と書くと、90 ラジアン（約 5157 度）回ります。度で考えるときは `deg_to_rad` を通してください
- 位置（m）と大きさ（倍率）は、どちらの書き方でも単位は同じです

位置と大きさは、`Entity.create` と同じ形で `=` を使って書き換えられます。`object3D` を直接書き換えるので、毎フレーム呼んでも軽いです。

```ruby
el.position = [0, 1.5, -2]       # position.set(0, 1.5, -2) と同じ
el.position = { y: 2 }           # 書かなかった軸はそのまま
el.scale = 0.5                   # 3軸とも 0.5（Entity.create の scale: 0.5 と同じ）
el.scale = [1, 2, 1]
```

- `Entity.create` の直後など、まだ読み込まれていない要素に書くと、読み込みが終わってから書き換えます（先に書くと A-Frame が属性の値で上書きするため）。それまでは `el.position` を読んでも前の値です
- 受け付けるのは `[x, y, z]` と `{ x:, y:, z: }`（どれかの軸だけでも可）で、`scale=` だけは数1つ（3軸とも同じ）も受け付けます。それ以外を渡すと `ArgumentError` になります
- 回転には `rotation=` がありません（単位をどうするかは [#87](https://github.com/itojum/aframe-picoruby/issues/87) で考えています）。`el.rotation.set(x, y, z)`（ラジアン）か `set_attribute(:rotation, [x, y, z])`（度）を使ってください
- `Entity.create` した直後は、A-Frame がまだ要素を読み込んでいないので、`Entity#rotation` などに書いても、読み込みのときに属性の値で上書きされます。作った直後に向きを決めるときは、属性（`rotation: [0, 45, 0]`）で渡してください
- どちらで書き換えても、もう一方にも反映されます（`object3D` を書き換えたあとに `getAttribute("rotation")` を読むと度で返ります）。毎フレーム動かすときは、属性の文字列を作らずに済む `Entity#rotation` などのほうが軽いです

## 日本語の文字を出す

A-Frame の `text` のフォントには日本語の文字がないので、日本語を出すには `label` コンポーネントを使います。端末のフォントで canvas に描いて、要素の mesh として出します（canvas は DOM に置きません）。

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
- [`examples/grab/`](../examples/grab/) では、箱の上の札が、掴むと「つかんだ！」、離すと「持てるよ」に変わります（箱に付けた `grab-hint` コンポーネントが `grab` / `release` イベントを受け取っているだけで、コンポーネントどうしは直接触っていません）

## イベントを受け取る

`Entity#on` でイベントを受け取ります。イベント名は Symbol でも文字列でもよく、そのまま使います（`:grab`、`"model-loaded"`）。ブロックはイベントを受け取っても、受け取らなくてもかまいません。

```ruby
listener = shark.on(:grab) { hint.set_attribute(:label, :value, "つかんだ！") }
shark.on(:release) { |event| p event[:detail][:cursorEl] }
shark.once("model-loaded") { puts "読み込んだ" }   # 1回だけ

shark.off(listener)   # この listener だけやめる
```

- `on` / `once` は、受け取るのをやめるための値を返します。やめるときは、その値を `off` に渡します。同じイベントを受け取っているほかの処理（別のコンポーネントなど）はそのまま残ります
- `once` は最初のイベントで受け取るのをやめます。それより前なら `off` でやめられます
- ブロックは、イベントを配り終えた後に呼びます。`preventDefault` などイベントを配っている最中に呼ぶ必要があるときは、`shark.js.addEventListener("click", sync: true) { |event| ... }` を使います

### コンポーネントの中で受け取る

コンポーネントが受け取るイベントは、クラスに `on` で書けます（A-Frame の `events` にあたるもの。[`examples/grab/`](../examples/grab/)）。

```ruby
class GrabHint < AFrame::Component
  register           # "grab-hint"
  schema hint: "", grabbed: "つかんだ！", idle: "持てるよ"

  on(:grab) { show data.grabbed }
  on(:release) { |event| show data.idle }

  private

  def show(text)
    AFrame::Entity.find(data.hint)&.set_attribute(:label, :value, text)
  end
end
```

```html
<a-box grab-target grab-hint="hint: #box-hint"></a-box>
```

- イベントは、コンポーネントを付けた要素から受け取ります
- ブロックはインスタンスの中で動くので、`el` / `data` / private メソッドが使えます。イベントは `Entity#on` と同じく、受け取っても受け取らなくてもかまいません
- 要素が動き始めたとき（`play`）につなぎ、`pause` したときと、コンポーネントを外したとき（`remove`）に外します。`pause` している間のイベントは受け取りません
- `multiple: true` のコンポーネントでは、インスタンスごとにつなぎます。親クラスに書いた `on` も受け取ります
- ブロックで例外が出ても、コンソールに出すだけです（ほかの `on` はそのまま動きます）

## A-Frame のプロパティを触る

`Entity` にないメソッドは、そのまま JS の要素に渡します（PicoRuby.wasm の `JS::Object` と同じく、プロパティの読み書きかメソッド呼び出しになります）。

```ruby
box = AFrame::Entity.all("#box").first
box.object3D.castShadow = true
box.emit("hello")
box.addEventListener("click") { |event| puts "click" }
```

- `Entity` 自身のメソッド（`color` / `position` など）と、Ruby の `Object` のメソッド（`class` / `hash` / `send` など）は渡しません。そのときは `entity.js.hash` のように `js` を使います
- `?` や `!` で終わる名前は JS に渡せず、`NoMethodError` になります

## コンポーネントを作る

JS の `AFRAME.registerComponent` にあたるものを Ruby のクラスで書けます（[`examples/spin/`](../examples/spin/)）。

```ruby
class SpinBox < AFrame::Component
  register           # 名前はクラス名から "spin-box"
  schema speed: 30   # { type: :number, default: 30 } と同じ

  def tick(time, delta)
    el.rotation.y += deg_to_rad(data.speed * delta_seconds)
  end
end
```

```html
<a-box spin-box="speed: 90"></a-box>
```

- `schema` は A-Frame の schema と同じ形です（Symbol でも文字列でもよい）。Hash でない値は既定値（`{ default: 値 }`）として扱い、型は A-Frame が既定値から決めます（数値 → number、true / false → boolean、配列 → array、それ以外 → string）。`schema radius: 8, label: "fish", speed: { type: :number, default: 15 }` のように混ぜて書けます。座標（vec3 など）の既定値は Hash になるので、`{ type: :vec3, default: { x: 0, y: 0, z: 0 } }` と書きます。`schema type: :number, default: 1` のように一番上に `type` か `default` を書くと、プロパティが1つだけのコンポーネントになり、`data` は値そのものになります（そのため `type` / `default` という名前のプロパティは省略形で書けません）
- `register` の名前を省略すると、クラス名を kebab-case にした名前になります（`SpinBox` → `spin-box`、`CameraLock` → `camera-lock`）。大文字が続くところはまとめ（`XRHand` → `xr-hand`）、`_` は `-` に直します（`Spin_Box` → `spin-box`。Symbol の属性名と同じ）。モジュールの中のクラスは最後の名前だけを使います（`Game::SpinBox` → `spin-box`）。クラス名と違う名前にしたいときは `register "grab-target"` のように書きます。System の `register` も同じです
- `register` より前に書いた要素にも、後から作った要素（`Entity.create(..., spin_box: { speed: 90 })`）にも付きます
- 上書きできるのは `init` / `update(old_data)` / `tick(time, delta)` / `remove` です。`initialize` は上書きしないでください
- `el` は要素の `Entity`、`data` は属性を読んだ結果（`data.speed`）、`component` は JS のコンポーネントです
- `tick(time, delta)` の `delta` は A-Frame と同じくミリ秒です。秒あたりの速さで動かすときは `delta_seconds`（`delta / 1000.0` と同じ）を使うと、`/ 1000`（整数の割り算）の書き間違いを避けられます。System でも使えます
- フックは A-Frame の中から同期で呼ぶので、中で `await` は使えません。例外を出してもコンソールに出すだけです
- `tick` はフレームごとにまとめて呼びます（`Scene.run` を呼ばなくても動きます。`Scene.on_tick` の処理より先に呼びます）。要素を `pause` している間は呼ばれません
- `register multiple: true` にすると、1つの要素に `spin-box__fast` / `spin-box__slow` のように複数付けられます（A-Frame の `multiple`）。それぞれが別のインスタンスで、`id` で `__` の後ろ（`"fast"`）を読めます。Ruby からは `spin_box__fast: { speed: 180 }` と書きます

## コンポーネントの中で待つ

「n 秒たったら〜する」「n 秒ごとに〜する」は、コンポーネントの `after` / `every` で書けます。

```ruby
class Crosser < AFrame::Component
  register

  def init
    @blink = every(0.5) { el.visible = !el.visible }   # 0.5 秒ごと
  end

  def rest
    el.visible = false
    @timer = after(random(3, 11)) { start_crossing }  # 一度だけ
  end

  def start_crossing
    el.visible = true
  end

  def stop_blinking
    @blink.cancel
  end
end
```

- 時間はコンポーネントの `tick` と同じく A-Frame のフレームで進みます（`setTimeout` は使いません）。要素やシーンを `pause` している間は止まり、VR 中も同じように進みます。`tick` を書いていないコンポーネントでも動きます
- コンポーネントが消えると（要素を消す、属性を外す）、残っているタイマーは捨てます
- 戻り値（`AFrame::Timer`）の `cancel` で取り消せます
- ブロックは、そのフレームの `tick` の前に呼びます。`every` は1フレームに1回までで、重いフレームなどで間に合わなかった分は飛ばします
- ブロックの中で例外が出てもコンソールに出すだけで、`every` は続きます

## シーン全体を見る処理を作る

コンポーネントが要素1つずつに付くのに対して、System はシーンに1つだけあり、全体を見る処理を書けます（[`examples/garden/`](../examples/garden/)）。

```ruby
class Garden < AFrame::System
  register
  schema max: 8                    # <a-scene garden="max: 20"> で変えられる

  def tick(time, delta)
    flowers = Flower.instances     # 生きている Flower コンポーネントの全部（作った順）
    flowers.first.el.js.remove if flowers.size > data.max
  end
end
```

- 書き方は `AFrame::Component` と同じです：`register` / `schema` と、フック `init` / `update(old_data)` / `tick(time, delta)` / `pause` / `play`。A-Frame の System は消えないので `remove` はありません
- `el` は `a-scene` の Entity、`data` は `a-scene` に書いた属性（`garden="max: 20"`）です
- 1フレームの中では、コンポーネントの `tick` を全部呼んだ後に System の `tick` を呼び、その後に `Scene.on_tick` の処理を呼びます（A-Frame と同じ順）
- `pause` / `play` は、シーンを `pause` / `play` したときに呼びます（A-Frame は System の `pause` / `play` を呼ばないので、`a-scene` のイベントから呼んでいます）
- コンポーネントクラスの `instances`（`Flower.instances`）で、そのコンポーネントの生きているインスタンスを配列で取れます

## 補間と乱数

動きを付けるときによく使う関数を用意しています。

```ruby
class Bob < AFrame::Component
  register
  schema duration: 2

  def init
    @t = 0.0
    @height = random(0.5, 1.5)   # 0.5 以上 1.5 未満の小数
  end

  def tick(time, delta)
    @t = [@t + delta_seconds / data.duration, 1.0].min
    el.position.y = @height * AFrame::Easing.ease_in_out_sine(@t)
  end
end
```

- `AFrame::Easing` には `linear` と、`ease_in_` / `ease_out_` / `ease_in_out_` に `sine` / `quad` / `cubic` を付けたものがあります。0 から 1 の `t` を渡すと、0 から 1 の値を返します。名前は A-Frame の `animation` コンポーネントの `easing`（`easeInOutSine`）に合わせています
- 式は広く使われているもの（Penner の式）です。A-Frame の `animation` は同じ名前の曲線を近似して描くので、途中で最大 0.035 ほど違います（始めと終わりは同じ）
- 設定から選ばせるときは `AFrame::Easing.send(data.easing, t)` と書けます（`schema easing: "ease_out_cubic"`）
- `AFrame.random(min, max)` は min 以上 max 未満の小数を返します。コンポーネントと System と `AFrame.scene` のブロックの中では `random(min, max)` と書けます。PicoRuby.wasm の `rand` は小数や範囲を受け付けない（`rand(3.0)` はいつも `0.0`、`rand(3..11)` はエラー）ので、こちらを使ってください
- [`examples/garden/`](../examples/garden/) では、花が `ease_out_cubic` で伸び、伸びる高さと時間を `random` で決めています

### A-Frame の animation を秒で書く（AFrame.animation）

決まった動きを繰り返すだけなら、A-Frame の `animation` コンポーネントに任せると、Ruby の処理は要りません。`AFrame.animation` は、その値を秒と `AFrame::Easing` と同じ名前で作ります。

```ruby
AFrame.scene do
  sway = AFrame.animation(:rotation, to: [3, 0, -4], dur: random(2.5, 4),
                          alternate: true, easing: :ease_in_out_sine)
  entity animation: sway do
    box width: 0.8, position: [0.4, 0, 0]
  end

  # 同じ要素に複数付けるときは、属性の名前を animation__名前 にする
  box animation__spin: AFrame.animation(:rotation, to: [0, 360, 0], dur: 4, loop: true, easing: :linear)
end
```

- 最初の引数は動かすプロパティです（`:rotation` / `:position` / `:scale` / `"material.color"` など）。`rotation` は属性と同じく度です
- `to:` / `from:` は属性と同じ形（`[x, y, z]`、数、色の文字列）で渡します
- `dur:` / `delay:` は秒です（小数も可）。ミリ秒に直して渡します
- `easing:` は `AFrame::Easing` と同じ名前の Symbol です（`:ease_in_out_sine` → `easeInOutSine`）。A-Frame にしかない曲線（`easeOutElastic` など）は、Symbol（`:ease_out_elastic`）か A-Frame の名前の文字列で渡します
- `loop:` は `true` か回数です。`alternate: true` は行って戻る動き（`dir: alternate`）で、`loop:` を書かなければ繰り返します
- ほかのキーワードは、名前を A-Frame の形（`start_events:` → `startEvents`）に直してそのまま渡します
- 戻り値は Hash なので、`Entity.create` や `set_attribute` にも渡せます

## 毎フレームの処理をどこに書くか

フレームごとの処理は、まずコンポーネント（`AFrame::Component` の `tick`）か System（`AFrame::System` の `tick`）に書いてください。A-Frame の書き方（ECS）と同じで、処理がどの要素・どのシーンのものかがはっきりし、要素を消せば処理も止まります。

- 要素ごとの動き（回す、伸ばす、追いかける）→ コンポーネントの `tick`
- シーン全体を見る処理（数える、間引く、まとめて動かす）→ System の `tick`
- `AFrame::Scene.on_tick { |time, delta| ... }` は、クラスを書くほどでもない小さな試しのコード向けの逃げ道です。コンポーネントや System の外に処理が散らばるので、長く使うコードではコンポーネントか System に移してください

### 重くなったとき

`data` や `el.position` などの JS の値は、読み書きするたびに JS と Ruby の間を行き来します。1回あたりは小さく、手元の Chromium で測ると、`data.xxx` を1回読むのに約 0.7µs でした（コンポーネント200個が毎フレーム3回ずつ読んで、1フレームあたり約 0.4ms）。数十個のコンポーネントなら気にしなくてかまいません。

コンポーネントを数百個置いて、毎フレーム何度も `data` を読むときは、`update` で Ruby の変数に写しておき、`tick` ではそれを使うと軽くなります（`update` は属性が変わったときに呼ばれるので、写した値も追いつきます）。

```ruby
class Swim < AFrame::Component
  register
  schema speed: 1.0, amp: 0.5

  def update(old_data)
    @speed = data.speed
    @amp = data.amp
  end

  def tick(time, delta)
    el.position.y = Math.sin(time / 1000.0 * @speed) * @amp
  end
end
```

## API 一覧

| API | 内容 |
|---|---|
| `AFrame::Scene.ready(selector = "a-scene")` | シーンを探し、読み込みが終わるまで待つ。見つからなければ例外 |
| `AFrame::Scene.element` | `ready` で見つけた `a-scene` 要素 |
| `AFrame::Scene.on_tick { \|time, delta\| }` | 小さな試し向け。ふだんはコンポーネントか System の `tick` に書く。毎フレーム呼ぶ処理を登録する（引数はミリ秒。省略してよい）。A-Frame の `tick` の中で、そのフレームを描く前に呼ぶので、変更はそのフレームに出る。中で `await` は使えない。例外を出してもコンソールに出すだけで、ほかの処理は呼ばれる |
| `AFrame::Scene.run` | A-Frame の描画ループに合わせて `on_tick` の処理を呼び続ける（戻ってこない）。VR 中も止まらない。シーンを `pause` している間は呼ばれない |
| `AFrame::Scene.start` | `run` と同じく `on_tick` の処理を呼び始めるが、すぐに戻ってくる |
| `AFrame::Entity.all(selector)` / `Entity.new(js)` | A-Frame 要素の薄いラッパー。`color` / `color=` / `position` / `position=` / `rotation` / `scale` / `scale=` / `visible` / `visible=` / `set_position(x, y, z)` / `pause_animation` / `play_animation` / `js`。ほかのメソッドは JS の要素に渡す（`box.object3D.castShadow`） |
| `Entity#position` / `#rotation` / `#scale` | `object3D` の `position`（THREE.Vector3）/ `rotation`（THREE.Euler、**ラジアン**。属性の `rotation` は度）/ `scale`（THREE.Vector3）をそのまま返す。書き換えると要素が動く（`el.position.x = 1`、`el.rotation.y += 0.1`）。`set_position(x, y, z)` は `position.set(x, y, z)` と同じ |
| `Entity#position=` / `#scale=` | `[x, y, z]` か `{ x:, y:, z: }`（書かなかった軸はそのまま）で `object3D` の位置・大きさを書き換える。`scale=` は数1つで3軸とも同じ倍率。読み込み前の要素には、読み込みが終わってから書く |
| `Entity#visible` / `#visible=` | `object3D.visible` を読み書きする（`el.visible = false` で隠す）。`visible` 属性は書き換えないので、HTML に書いた値はそのまま。毎フレーム切り替えても軽い |
| `AFrame::Entity.find(selector)` | 最初に見つかった要素を Entity で返す。見つからなければ `nil`（`querySelector` と同じ） |
| `Entity#on(event) { }` / `#once(event) { }` / `#off(listener)` | イベントを受け取る。`on` / `once` は `off` に渡す値を返す。`off` はその処理だけやめる。ブロックの引数（イベント）は省略してよい |
| `Component#after(seconds) { }` / `#every(seconds) { }` | コンポーネントの時間（一時停止で止まる）で、一度だけ / くり返しブロックを呼ぶ。`AFrame::Timer` を返し、`timer.cancel` で取り消す。コンポーネントが消えると捨てる |
| `AFrame::Easing.ease_in_out_sine(t)` など | 補間。`linear` と `ease_in_` / `ease_out_` / `ease_in_out_` × `sine` / `quad` / `cubic`。0〜1 を受け取り 0〜1 を返す |
| `AFrame.random(min, max)` | min 以上 max 未満の小数。コンポーネント・System・`AFrame.scene` の中では `random(min, max)` |
| `AFrame.animation(property, to:, from:, dur:, delay:, easing:, loop:, alternate:, **others)` | A-Frame の `animation` コンポーネントの値を作る。時間は秒、`easing` は `AFrame::Easing` と同じ名前の Symbol。`alternate: true` は往復して繰り返す |
| `AFrame.scene(parent: nil) { }` | ブロックの中で `box` / `sphere` / `entity` / `tag "a-foo"` などを呼んで要素を作る。一番外側で作った Entity の配列を返す |
| `AFrame::Entity.create(tag, *components, parent: nil, **attributes)` | 要素を作り（`components` の Symbol は既定値のまま付けるコンポーネント）、`parent`（Entity、JS の要素、セレクターの文字列。省略時は `a-scene`）の子にして、Entity で返す。セレクターが見つからなければ例外 |
| `Entity#set_attribute(name, value)` / `Entity#set_attribute(name, property, value)` / `Entity#append(child)` | 属性を設定する（コンポーネントに Hash を渡すと、渡したプロパティだけ変えてほかは残す）/ コンポーネントのプロパティを1つだけ変える / 子を付け替える（`appendChild`） |
| `class X < AFrame::Component` / `register(name = nil, multiple: false)`（名前を省略するとクラス名から） / `schema(hash)` / `on(event) { \|event\| ... }` | Ruby で A-Frame のコンポーネントを定義する。`init` / `update(old_data)` / `tick(time, delta)` / `remove` を上書きし、`el` / `data` / `id` / `delta_seconds` / `random` / `after` / `every` / `deg_to_rad` / `rad_to_deg` を使う |
| `class X < AFrame::System` / `register(name = nil)` / `schema(hash)` | Ruby で A-Frame の System を定義する。`init` / `update(old_data)` / `tick(time, delta)` / `pause` / `play` を上書きし、`el`（a-scene）/ `data` / `delta_seconds` / `random` を使う |
| `X.instances`（X は Component のサブクラス） | そのコンポーネントの生きているインスタンスの配列（作った順） |
| `grab-target` 属性（`AFrame::Grabbable`） | 付けた要素をマウスや VR コントローラー（`laser-controls` など）で掴んで動かせるようにする。設定は `grab_color` / `pause_animation` / `enabled` / `raycaster`。掴むと `grab`、離すと `release` のイベントを出し、掴んでいる間は `grabbed` の状態になる |
| `AFrame::Grabbable.instances` / `#grab_distance` / `#grab_distance=` / `#following_ray?` / `#grabbed?` | `grab-target` のコンポーネントの一覧と、マウスで掴んでいる図形の ray の起点からの距離（負の値は 0 になる） |
| `label` 属性（`AFrame::Label`） | 日本語を含む文字を、角の丸い板に描いて出す。設定は `value` / `height` / `color` / `background` / `font` |
| `camera-lock` 属性（`AFrame::CameraLock`、a-scene に付ける System） | 掴める `grab-target` の上でマウスを押したときに `look-controls` を止め、離したときに戻す。設定は `camera`（既定 `a-camera`）と `raycaster`（既定 `[raycaster]`） |
| `AFrame::CameraLock.install(camera: "a-camera", raycaster: "[raycaster]")` | 前の書き方との互換のために残している。`a-scene` に `camera-lock` 属性を付けるだけ |
