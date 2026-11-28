require "aframe"

AFrame::Scene.ready
# 掴んでいる間に視点が回らないのは、index.html の <a-scene camera-lock> による

# grab-target 属性を付けた図形（index.html）は、そのまま掴める。
# 掴んだ・離したは grab / release イベントで分かる
AFrame::Entity.all("[grab-target]").each do |shape|
  shape.on(:grab) { puts "grab #{shape.tagName}" }
  shape.on(:release) do
    puts "release #{shape.tagName} at #{shape.position.x.round(2)}, #{shape.position.y.round(2)}, #{shape.position.z.round(2)}"
  end
end

# 箱の上の札（label 部品）の文字を、掴んだとき・離したときに変える
box = AFrame::Entity.find("a-box[grab-target]")
hint = AFrame::Entity.find("#box-hint")
box.on(:grab) { hint.set_attribute(:label, :value, "つかんだ！") }
box.on(:release) { hint.set_attribute(:label, :value, "持てるよ") }

# マウスで掴んでいる間は、ホイールで図形を近づける・遠ざける
JS.global.addEventListener("wheel") do |event|
  AFrame::Grabbable.instances.each do |item|
    next unless item.following_ray?

    item.grab_distance = item.grab_distance + event[:deltaY] * 0.005
  end
end

AFrame::Scene.run
