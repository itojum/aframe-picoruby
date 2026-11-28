require "aframe"

# <a-box spin-box="speed: 90"> を、毎秒 speed 度ずつ Y 軸で回す
class SpinBox < AFrame::Component
  register                       # "spin-box"
  schema speed: 30

  def tick(time, delta)
    el.rotation.y += deg_to_rad(data.speed * delta_seconds)
  end
end

AFrame::Scene.ready

colors = ["#EF2D5E", "#FFC65D", "#7BC8A4", "#4CC3D9", "#93648D", "#F16745"]

# AFrame.scene の中で box や sphere と同じように呼べる部品。
# position: などコンポーネントの名前は外側の entity に付き、height: / color: はブロックに渡る。
# children の場所に、呼び出し側のブロックで作ったものが入る
AFrame.part :lamp do |height: 1.2, color: "#FFC65D"|
  cylinder position: [0, height / 2, 0], height: height, radius: 0.04, color: "#888888"
  entity position: [0, height, 0] do
    sphere radius: 0.12, color: color
    children
  end
end

AFrame.scene do
  # 中央の箱と、そのまわりを回る6つの球
  entity position: [0, 1.6, -3] do
    box color: "#4CC3D9", spin_box: { speed: 45 }
    entity spin_box: { speed: -30 } do
      # around で、半径 1.5 の輪の上に6つ並べる（i は 0〜5）
      around 6, radius: 1.5 do |i|
        sphere radius: 0.2, color: colors[i]
      end
    end
  end

  # 部品を使う。2つ目は、電球の上に小さな箱を載せる
  lamp position: [-2.2, 0, -3]
  lamp(position: [2.2, 0, -3], height: 1.6, color: "#7BC8A4") do
    box position: [0, 0.2, 0], scale: 0.12, color: "#ffffff", spin_box: { speed: 90 }
  end

  # 一覧にないタグは tag で作る
  tag "a-entity", id: "floor-group" do
    plane position: [0, 0, -3], rotation: [-90, 0, 0], width: 8, height: 8, color: "#16213e"
  end

  text value: "AFrame.scene", position: [0, 3.2, -3], align: "center", color: "#ffffff", width: 6
end
