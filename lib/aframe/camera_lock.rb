module AFrame
  # The camera-lock system: stops look-controls while a grab-target is
  # being grabbed with the mouse, so dragging a shape does not turn the
  # view. It works on scenes that have the attribute:
  #
  #   <a-scene camera-lock="camera: a-camera; raycaster: [raycaster]">
  #
  # (A-Frame creates a system for every scene, so the attribute is what
  # turns it on.) camera and raycaster are looked up inside that scene. The lock must be taken before look-controls starts
  # dragging, which happens on the same mousedown, so it checks what the
  # raycaster is over in a sync capture-phase handler rather than waiting
  # for the grab event, which reaches Ruby later.
  class CameraLock < System
    register "camera-lock"
    schema camera: "a-camera", raycaster: "[raycaster]"

    # Kept for older code: puts camera-lock on a-scene with these
    # settings.
    def self.install(camera: "a-camera", raycaster: "[raycaster]")
      scene = Scene.element || JS.document.querySelector("a-scene")
      raise "a-scene not found" if scene.nil?

      scene.setAttribute("camera-lock", "camera: #{camera}; raycaster: #{raycaster}")
    end

    def init
      @locked = false
      @camera = nil
      # No await inside: this runs synchronously in the capture phase.
      @mousedown_id = JS.global.addEventListener("mousedown", sync: true, capture: true) do |_event|
        lock if active? && hovering_grab_target?
      end
      @mouseup_id = JS.global.addEventListener("mouseup") { |_event| unlock }
    end

    private

    def active?
      el.js.hasAttribute("camera-lock") ? true : false
    end

    # True when the target the mouse would grab is a grab-target that can
    # be grabbed (enabled), so pressing on anything else still turns the
    # view. The target is the cursor's intersectedEl (the cursor sends
    # mousedown only to it), or the nearest intersection without a cursor.
    def hovering_grab_target?
      raycaster = el.js.querySelector(data.raycaster)
      return false if raycaster.nil?

      target = nearest_target(raycaster)
      return false if target.nil?

      grab = target[:components]["grab-target"]
      !grab.nil? && grab[:data][:enabled] ? true : false
    end

    def nearest_target(raycaster)
      cursor = raycaster[:components][:cursor]
      return cursor[:intersectedEl] unless cursor.nil?

      component = raycaster[:components][:raycaster]
      return nil if component.nil?

      els = component[:intersectedEls]
      els.nil? || els[:length] == 0 ? nil : els[0]
    end

    # Disables look-controls and remembers whether it was enabled,
    # so unlock restores it only when this lock was taken.
    def lock
      return if @locked

      camera = el.js.querySelector(data.camera)
      return if camera.nil?

      look_controls = camera[:components]["look-controls"]
      return if look_controls.nil?

      @camera = camera
      @previous_enabled = look_controls[:data][:enabled]
      look_controls[:mouseDown] = false
      camera.setAttribute("look-controls", "enabled: false")
      @locked = true
    end

    def unlock
      return unless @locked

      @locked = false
      @camera.setAttribute("look-controls", "enabled: #{@previous_enabled}")
      @camera = nil
    end
  end
end
