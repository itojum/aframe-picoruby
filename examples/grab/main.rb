require "aframe"

AFrame::Scene.ready

# Step 3 check: AFrame::Entity
box, sphere, cylinder = AFrame::Entity.all(".my-grabbable")
puts sphere.color
p sphere.position

sphere.color = "#00ff00"
sphere.set_position(0, 2.5, -3)
box.pause_animation
cylinder.pause_animation
