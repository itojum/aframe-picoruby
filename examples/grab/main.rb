require "aframe"

puts AFrame::VERSION
JS.document.querySelector("a-text").setAttribute("value", "AFrame #{AFrame::VERSION}")
