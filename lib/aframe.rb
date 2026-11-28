# Entry point of the aframe library (module AFrame).
# Each part lives in lib/aframe/ and is loaded with require below.
# importmap-picoruby resolves "aframe/..." relative to this file.
require "js"
require "aframe/version"
require "aframe/easing"
require "aframe/scene"
require "aframe/entity"
require "aframe/timer"
require "aframe/component"
require "aframe/system"
require "aframe/builder"
require "aframe/camera_lock"
require "aframe/grabbable"
require "aframe/label"
require "aframe/anchor"
