require "aframe"

AFrame::Scene.ready
puts JS.document.querySelectorAll(".my-grabbable").to_a.size
