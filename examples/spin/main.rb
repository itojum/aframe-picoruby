require "aframe"

# <a-box spin-box="speed: 90"> を、毎秒 speed 度ずつ Y 軸で回す
class SpinBox < AFrame::Component
  register "spin-box"
  schema speed: 30

  def tick(time, delta)
    el.rotation.y += deg_to_rad(data.speed * delta / 1000)
  end
end

AFrame::Scene.ready

# Ruby から作った要素にも付けられる
AFrame::Entity.create("a-box", position: [0, 0.5, -2], scale: [0.5, 0.5, 0.5],
                      color: "#7BC8A4", spin_box: { speed: 360 })
