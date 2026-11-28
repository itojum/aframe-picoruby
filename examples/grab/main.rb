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

# 箱の上の札（label コンポーネント）の文字を、掴んだとき・離したときに変える。
# 受け取るイベントはクラスに on で書く（付けたときにつながり、外すと外れる）
class GrabHint < AFrame::Component
  register                       # "grab-hint"
  schema hint: "", grabbed: "つかんだ！", idle: "持てるよ"

  on(:grab) { show data.grabbed }
  on(:release) { show data.idle }

  private

  def show(text)
    hint = AFrame::Entity.find(data.hint)
    hint&.set_attribute(:label, :value, text)
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
