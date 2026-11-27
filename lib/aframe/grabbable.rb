module AFrame
  # The grab-target component: an element with it can be grabbed and
  # moved. (A-Frame already has a component named grabbable, for hand
  # tracking, so this one is grab-target.)
  #
  #   <a-box grab-target="grab_color: #ffff00"></a-box>
  #   AFrame::Entity.create("a-box", grab_target: { grab_color: "#ffff00" })
  #
  # - Mouse (cursor with rayOrigin: mouse): the shape follows the mouse ray
  #   at the distance it was grabbed, updated every frame (tick).
  # - VR controller (laser-controls etc.): the shape is re-parented to the
  #   controller with Object3D#attach, so it moves with the hand by itself.
  #
  # The element emits grab and release (detail.cursorEl is the cursor
  # that grabbed it) and has the grabbed state while it is held
  # (el.is("grabbed")). data holds only the settings.
  class Grabbable < Component
    register "grab-target"
    schema grab_color: "#ffffff",       # color while grabbed ("none" keeps it)
           pause_animation: true,       # pause the animation component
           enabled: true,               # false: cannot be grabbed
           raycaster: "[raycaster]"     # the mouse cursor's raycaster

    class << self
      # Every live grab-target component, in the order they were created.
      def instances
        @items ||= []
      end

      # One window mouseup for all instances: release every shape first,
      # then emit release, so a listener cannot keep another one held.
      def install_mouseup
        return if @mouseup_installed

        @mouseup_installed = true
        JS.global.addEventListener("mouseup") do |event|
          released = instances.select { |item| item.release(event) }
          released.each { |item| item.emit_release }
        end
      end
    end

    attr_reader :grab_distance

    def init
      @grabbed = false
      @grab_distance = 0
      @holder = nil       # the controller holding it (nil for the mouse)
      @cursor = nil       # the cursor that grabbed it (mouse or controller)
      @paused = false     # whether the grab paused the animation
      @original_color = nil
      @listener_id = el.js.addEventListener("mousedown") { |event| grab(event) }
      Grabbable.instances << self
      Grabbable.install_mouseup
    end

    # enabled: false releases a shape that is held. grab_color and
    # pause_animation changed while held apply right away.
    def update(old_data)
      return release_now unless data.enabled
      return unless @grabbed

      apply_grab_color
      if data.pause_animation && !@paused
        el.pause_animation
        @paused = true
      elsif !data.pause_animation && @paused
        el.play_animation
        @paused = false
      end
    end

    # removeAttribute("grab-target") or removing the element: releases the
    # shape and stops listening.
    def remove
      Grabbable.instances.delete(self)
      unless @listener_id.nil?
        JS::Object.removeEventListener(@listener_id)
        @listener_id = nil
      end
      release_now
    end

    def grabbed?
      @grabbed
    end

    # Distance from the ray origin while grabbed with the mouse (e.g. to
    # move the shape closer with the wheel). Negative values become 0.
    def grab_distance=(value)
      @grab_distance = value < 0 ? 0 : value
    end

    # Grabbed with the mouse (moved every frame).
    def following_ray?
      @grabbed && @holder.nil?
    end

    # Moves a shape held by the mouse to origin + direction * distance.
    def tick(time, delta)
      return unless following_ray?

      r = ray
      return if r.nil?

      origin = r[:origin]
      direction = r[:direction]
      d = @grab_distance
      el.set_position(origin[:x] + direction[:x] * d,
                      origin[:y] + direction[:y] * d,
                      origin[:z] + direction[:z] * d)
    end

    # With a VR controller, the shape is attached to the controller.
    # With the mouse, it is ignored until the ray is ready, so the
    # distance is always measured.
    def grab(event = nil)
      return if @grabbed || !data.enabled

      cursor = cursor_of(event)
      if controller?(cursor)
        cursor[:object3D].attach(el.js[:object3D])
        @holder = cursor
      else
        distance = distance_from_ray_origin
        return if distance.nil?

        @grab_distance = distance
        @holder = nil
      end
      @grabbed = true
      @cursor = cursor
      apply_grab_color
      if data.pause_animation
        el.pause_animation
        @paused = true
      end
      el.js.addState("grabbed")
      el.js.emit("grab", JS::Bridge.to_js({ "cursorEl" => cursor }))
    end

    # A mouse grab ends on any mouseup. A controller grab ends only on
    # the mouseup of that controller, so the other hand keeps its shape.
    # Returns true when this call released the shape; release is emitted
    # by the caller (emit_release).
    def release(event = nil)
      return false unless @grabbed
      return false if !@holder.nil? && !released_by_holder?(event)

      @released_by = @cursor
      drop
      true
    end

    def emit_release
      el.js.emit("release", JS::Bridge.to_js({ "cursorEl" => @released_by }))
      @released_by = nil
    end

    private

    # Sets the grab color, saving the original the first time; "none"
    # (A-Frame turns an empty value into the default, so "" cannot be
    # used) puts the original back.
    def apply_grab_color
      color = data.grab_color.to_s
      if color.empty? || color == "none"
        unless @original_color.nil?
          el.color = @original_color
          @original_color = nil
        end
      else
        @original_color = el.color if @original_color.nil?
        el.color = color
      end
    end

    # Releases without a mouseup (enabled: false, remove).
    def release_now
      return unless @grabbed

      @released_by = @cursor
      drop
      emit_release
    end

    # Puts the shape back: under a-scene for a controller grab, and the
    # color and animation as they were before the grab.
    def drop
      unless @holder.nil?
        el.js[:sceneEl][:object3D].attach(el.js[:object3D])
        @holder = nil
      end
      @grabbed = false
      @cursor = nil
      unless @original_color.nil?
        el.color = @original_color
        @original_color = nil
      end
      if @paused
        el.play_animation
        @paused = false
      end
      el.js.removeState("grabbed")
    end

    # THREE.Ray of the mouse cursor's raycaster (origin is the camera
    # position with rayOrigin: mouse), or nil before it is ready.
    def ray
      raycaster = raycaster_element
      return nil if raycaster.nil?

      component = raycaster[:components][:raycaster]
      return nil if component.nil?

      three = component[:raycaster]
      three.nil? ? nil : three[:ray]
    end

    # The raycaster element, looked up once per selector and again when
    # the selector changes, it leaves the page, or it was not found yet.
    def raycaster_element
      selector = data.raycaster
      if @raycaster_el.nil? || @raycaster_selector != selector || !@raycaster_el[:isConnected]
        @raycaster_selector = selector
        @raycaster_el = JS.document.querySelector(selector)
      end
      @raycaster_el
    end

    # detail is a JS object for cursor events and an Integer for native
    # mouse events (do not call .class on a JS object).
    def cursor_of(event)
      return nil if event.nil?

      detail = event[:detail]
      detail.is_a?(JS::Object) ? detail[:cursorEl] : nil
    end

    def controller?(cursor)
      return false if cursor.nil?

      component = cursor[:components][:cursor]
      !component.nil? && component[:data][:rayOrigin] != "mouse"
    end

    # The cursor emits mouseup on itself (target) and on the intersected
    # shape (detail.cursorEl).
    def released_by_holder?(event)
      return false if event.nil?

      same = JS.global[:Object]
      same.is(@holder, event[:target]) || same.is(@holder, cursor_of(event))
    end

    def distance_from_ray_origin
      r = ray
      return nil if r.nil?

      origin = r[:origin]
      pos = el.position
      ddx = pos[:x] - origin[:x]
      ddy = pos[:y] - origin[:y]
      ddz = pos[:z] - origin[:z]
      Math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
    end
  end
end
