require "aframe"

# <a-box spin-box="speed: 90"> を、毎秒 speed 度ずつ Y 軸で回す
class SpinBox < AFrame::Component
  register "spin-box"
  schema speed: 30

  def tick(time, delta)
    el.rotation.y += deg_to_rad(data.speed * delta_seconds)
  end
end

AFrame::Scene.ready

colors = ["#EF2D5E", "#FFC65D", "#7BC8A4", "#4CC3D9", "#93648D", "#F16745"]

AFrame.scene do
  # 中央の箱と、そのまわりを回る6つの球
  entity position: [0, 1.6, -3] do
    box color: "#4CC3D9", spin_box: { speed: 45 }
    entity spin_box: { speed: -30 } do
      6.times do |i|
        angle = Math::PI * 2 * i / 6
        sphere position: [Math.cos(angle) * 1.5, 0, Math.sin(angle) * 1.5],
               radius: 0.2, color: colors[i]
      end
    end
  end

  # 一覧にないタグは tag で作る
  tag "a-entity", id: "floor-group" do
    plane position: [0, 0, -3], rotation: [-90, 0, 0], width: 8, height: 8, color: "#16213e"
  end

  text value: "AFrame.scene", position: [0, 3.2, -3], align: "center", color: "#ffffff", width: 6
end
