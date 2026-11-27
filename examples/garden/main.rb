require "aframe"

# 花1本ずつに付く部品：少しずつ伸びる
class Flower < AFrame::Component
  register "flower"
  schema speed: 0.3 # 1秒に伸びる高さ

  def tick(time, delta)
    el.scale.y += data.speed * delta / 1000 if el.scale.y < 3
  end
end

# シーンに1つの System：1秒ごとに花を植え、max 本を超えたら古い花から抜く
# （<a-scene garden="max: 8"> で本数を変えられる）
class Garden < AFrame::System
  register "garden"
  schema max: 8, interval: 1000

  def init
    @elapsed = 0
    @count = 0
  end

  def tick(time, delta)
    @elapsed += delta
    return if @elapsed < data.interval

    @elapsed = 0
    # 植えた花の部品が動き出すのは次の番なので、先に1本分あけておく
    Flower.instances.first.el.js.remove while Flower.instances.size >= data.max
    plant
  end

  private

  def plant
    @count += 1
    angle = @count * 2.4 # 黄金角くらいずつずらして並べる
    radius = 0.4 + (@count % 5) * 0.35
    AFrame::Entity.create("a-cylinder",
                          position: [Math.cos(angle) * radius, 0, -3 + Math.sin(angle) * radius],
                          radius: 0.08, height: 0.5, scale: [1, 0.2, 1],
                          color: "hsl(#{(@count * 47) % 360}, 70%, 60%)",
                          flower: { speed: 0.2 + (@count % 3) * 0.15 })
  end
end

AFrame::Scene.ready
