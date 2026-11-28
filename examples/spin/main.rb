require "aframe"

# <a-box spin-box="speed: 90"> を、毎秒 speed 度ずつ axis（既定は Y）軸で回す。
# multiple: true なので、spin-box__x のように1つの要素へ複数付けられる
class SpinBox < AFrame::Component
  register multiple: true        # "spin-box"
  schema speed: 30, axis: "y"

  def tick(time, delta)
    el.rotation[data.axis] += deg_to_rad(data.speed * delta_seconds)
  end
end

AFrame::Scene.ready

# Ruby から作った要素にも付けられる
AFrame::Entity.create("a-box", position: [0, 0.5, -2], scale: [0.5, 0.5, 0.5],
                      color: "#7BC8A4", spin_box: { speed: 360 })

# 2つ付ける：Y 軸で速く、X 軸でゆっくり
AFrame::Entity.create("a-box", position: [0, 2.8, -2], scale: [0.5, 0.5, 0.5], color: "#B07AFF",
                      spin_box__fast: { speed: 180 }, spin_box__slow: { speed: 20, axis: "x" })
