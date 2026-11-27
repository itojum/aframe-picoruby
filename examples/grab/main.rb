require "aframe"

AFrame::Scene.ready
AFrame::CameraLock.install

# grab-target 属性を付けた図形（index.html）は、そのまま掴める。
# 掴んだ・離したは grab / release イベントで分かる
AFrame::Entity.all("[grab-target]").each do |shape|
  shape.addEventListener("grab") { |event| puts "grab #{shape.tagName}" }
  shape.addEventListener("release") do |event|
    puts "release #{shape.tagName} at #{shape.position.x.round(2)}, #{shape.position.y.round(2)}, #{shape.position.z.round(2)}"
  end
end

# マウスで掴んでいる間は、ホイールで図形を近づける・遠ざける
JS.global.addEventListener("wheel") do |event|
  AFrame::Grabbable.instances.each do |item|
    next unless item.following_ray?

    item.grab_distance = item.grab_distance + event[:deltaY] * 0.005
  end
end

AFrame::Scene.run
