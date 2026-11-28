require "aframe"

# 花1本ずつに付く部品：duration 秒かけて height まで伸びる
# （初めは速く、伸びきる前にゆっくりになる）
class Flower < AFrame::Component
  register "flower"
  schema height: 3, duration: 4 # 伸びきったときの縦の倍率と、かかる秒数

  def init
    @start = el.scale.y
    @t = 0.0 # 0 から 1 まで進む
  end

  def tick(time, delta)
    return if @t >= 1

    @t = [@t + delta_seconds / data.duration, 1.0].min
    el.scale.y = @start + (data.height - @start) * AFrame::Easing.ease_out_cubic(@t)
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
    while !Flower.instances.empty? && Flower.instances.size >= data.max
      Flower.instances.first.el.js.remove
    end
    plant if data.max >= 1
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
                          flower: { height: random(2.0, 3.5), duration: random(3, 6) })
  end
end

AFrame::Scene.ready
