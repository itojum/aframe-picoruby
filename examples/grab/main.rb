require "aframe"

AFrame::Scene.ready
AFrame::CameraLock.install
items = AFrame::Grabbable.attach_all(".my-grabbable")

# マウスで掴んでいる間は、ホイールで図形を近づける・遠ざける
JS.global.addEventListener("wheel") do |event|
  items.each do |item|
    next unless item.following_ray?

    item.grab_distance = item.grab_distance + event[:deltaY] * 0.005
  end
end

AFrame::Scene.run
