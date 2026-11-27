require "aframe"

# Issue #40: checks that an instance_eval DSL works on PicoRuby.wasm.
# Each check prints "ok" or "NG" with what happened. The builder below is
# only for this check; the real AFrame.scene comes with #44.

def check(label)
  result = yield
  puts "#{result ? "ok" : "NG"}: #{label}"
rescue => e
  puts "NG: #{label} (#{e.class}: #{e.message})"
end

# A minimal builder: tag-name methods via method_missing, nesting through
# @parent, attributes as keyword arguments.
class CheckBuilder
  attr_reader :created

  def initialize(parent = nil)
    @parent = parent
    @created = []
  end

  def method_missing(name, **attributes, &block)
    entity = AFrame::Entity.create("a-#{name}", parent: @parent, **attributes)
    @created << entity
    if block
      child = CheckBuilder.new(entity)
      child.instance_eval(&block)
      @created.concat(child.created)
    end
    entity
  end

  def respond_to_missing?(name, include_private = false)
    true
  end
end

class SpinBox < AFrame::Component
  register "spin-box"
  schema speed: 30

  def tick(time, delta)
    el.rotation.y += deg_to_rad(data.speed * delta / 1000)
  end
end

AFrame::Scene.ready

# 1. instance_eval switches self
check("instance_eval switches self") do
  target = CheckBuilder.new
  target.instance_eval { self } .equal?(target)
end

# 2. outer local variables are visible inside the block
outer = "tomato"
check("outer local variables are visible") do
  seen = nil
  CheckBuilder.new.instance_eval { seen = outer }
  seen == "tomato"
end

# 3. method_missing receives tag-name methods (box / sphere)
check("method_missing receives box / sphere") do
  b = CheckBuilder.new
  b.instance_eval do
    box id: "dsl-box", position: [-1.5, 1, -3], color: "tomato"
    sphere id: "dsl-sphere", position: [1.5, 1, -3], radius: 0.4, color: "gold"
  end
  !JS.document.getElementById("dsl-box").nil? && JS.document.getElementById("dsl-sphere")[:tagName] == "A-SPHERE"
end

# 4 + 5. nesting passes parent:, and keyword arguments come with a block
check("nesting passes parent: and takes kwargs with a block") do
  CheckBuilder.new.instance_eval do
    entity id: "dsl-group", position: [0, 0, -3] do
      box id: "dsl-child", position: [0, 1, 0], color: "#4CC3D9"
    end
  end
  group = JS.document.getElementById("dsl-group")
  child = JS.document.getElementById("dsl-child")
  # position is read back below, after A-Frame has loaded the element
  # (right after create it still has the default 0 0 0).
  JS.global[:Object].is(child[:parentNode], group)
end

# 6. Integer#times / Math in the block, with computed attribute values
check("Integer#times / Math and computed values") do
  CheckBuilder.new.instance_eval do
    6.times do |i|
      angle = Math::PI * 2 * i / 6
      sphere class: "dsl-ring", position: [Math.cos(angle) * 1.2, 2.5, -3 + Math.sin(angle) * 1.2],
             radius: 0.15, color: "hsl(#{i * 60}, 80%, 60%)"
    end
  end
  rings = JS.document.querySelectorAll(".dsl-ring").to_a
  rings.size == 6 && rings[1].getAttribute("color") == "hsl(60, 80%, 60%)"
end

# 7. an existing AFrame::Component attaches to DSL-made elements
check("AFrame::Component attaches (spin_box:)") do
  CheckBuilder.new.instance_eval do
    box id: "dsl-spin", position: [0, 1, -2], scale: [0.4, 0.4, 0.4], color: "#7BC8A4", spin_box: { speed: 90 }
  end
  JS.document.getElementById("dsl-spin").getAttribute("spin-box").nil? == false
end

# Components and attributes are set up once A-Frame loads the elements
# (a later turn), so these are checked from the frame loop.
group = AFrame::Entity.find("#dsl-group")
spin = AFrame::Entity.find("#dsl-spin")
start = nil
frames = 0
AFrame::Scene.on_tick do
  frames += 1
  if frames == 5
    start = spin.rotation.y
    puts "#{group.position.z == -3 ? "ok" : "NG"}: position: from the DSL is applied after load (z = #{group.position.z})"
  end
  if frames == 65
    puts "#{spin.rotation.y > start ? "ok" : "NG"}: spin-box turns the DSL-made box (#{(spin.rotation.y - start).round(3)} rad in 60 frames)"
  end
end
AFrame::Scene.run
