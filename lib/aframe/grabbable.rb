module AFrame
  # Shapes that can be grabbed (my-grabbable in 1.html).
  # - Mouse (cursor with rayOrigin: mouse): the shape follows the mouse ray
  #   at the distance it was grabbed, updated every frame.
  # - VR controller (laser-controls etc.): the shape is re-parented to the
  #   controller with Object3D#attach, so it moves with the hand by itself.
  class Grabbable
    GRAB_COLOR = "#ffffff"

    class << self
      # All shapes share one raycaster: a different selector on a later
      # call raises, and shared state is replaced only after the lookup.
      # grab_color: color while grabbed (nil keeps the color).
      # pause_animation: pause the animation component while grabbed.
      def attach_all(selector, raycaster: "[raycaster]", grab_color: GRAB_COLOR, pause_animation: true)
        if @raycaster_selector && @raycaster_selector != raycaster
          raise "Grabbable is already attached with #{@raycaster_selector}"
        end

        element = JS.document.querySelector(raycaster)
        raise "#{raycaster} not found" if element.nil?

        @raycaster_selector = raycaster
        @raycaster = element

        @items ||= []
        added = Entity.all(selector).map do |entity|
          new(entity, grab_color: grab_color, pause_animation: pause_animation)
        end
        @items.concat(added)
        install_handlers
        added
      end

      def items
        @items || []
      end

      # Called by Grabbable#detach.
      def remove(item)
        @items&.delete(item)
      end

      # THREE.Ray of the raycaster (origin is the camera position
      # with rayOrigin: mouse), or nil before it is ready.
      def ray
        component = @raycaster[:components][:raycaster]
        return nil if component.nil?

        three = component[:raycaster]
        three.nil? ? nil : three[:ray]
      end

      private

      # One window mouseup and one tick handler for all instances.
      def install_handlers
        return if @handlers_installed

        @handlers_installed = true
        # Release every shape first, then run the hooks, so a hook that
        # awaits or raises does not keep the other shapes grabbed.
        JS.global.addEventListener("mouseup") do |event|
          released = items.select { |item| item.release(event) }
          released.each { |item| item.run_release_hooks }
        end
        Scene.on_tick { update }
      end

      def update
        held = items.select { |item| item.following_ray? }
        return if held.empty?

        r = ray
        return if r.nil?

        origin = r[:origin]
        direction = r[:direction]
        ox = origin[:x]
        oy = origin[:y]
        oz = origin[:z]
        dx = direction[:x]
        dy = direction[:y]
        dz = direction[:z]
        held.each { |item| item.follow(ox, oy, oz, dx, dy, dz) }
      end
    end

    attr_reader :entity, :grab_distance

    def initialize(entity, grab_color: GRAB_COLOR, pause_animation: true)
      @entity = entity
      @grab_color = grab_color
      @pause_animation = pause_animation
      @original_color = nil
      @enabled = true
      @detached = false
      @grabbed = false
      @grab_distance = 0
      @holder = nil
      @grab_hooks = []
      @release_hooks = []
      @listener_id = entity.js.addEventListener("mousedown") { |event| grab(event) }
    end

    def grabbed?
      @grabbed
    end

    def enabled?
      @enabled
    end

    # false stops grabbing, and releases the shape (running the release
    # hooks) when it is held. A detached shape stays disabled.
    def enabled=(value)
      @enabled = value && !@detached ? true : false
      force_release unless @enabled
    end

    # Distance from the ray origin while grabbed with the mouse (e.g. to
    # move the shape closer with the wheel). Negative values become 0.
    def grab_distance=(value)
      @grab_distance = value < 0 ? 0 : value
    end

    # Stops grabbing for good: releases the shape when it is held,
    # removes the mousedown listener and drops it from Grabbable.items.
    # Disabled and removed before the release hooks run, so a hook cannot
    # grab it again.
    def detach
      @detached = true
      @enabled = false
      unless @listener_id.nil?
        JS::Object.removeEventListener(@listener_id)
        @listener_id = nil
      end
      self.class.remove(self)
      force_release
      self
    end

    # Called with the Entity after it is grabbed.
    def on_grab(&block)
      @grab_hooks << block
      self
    end

    # Called with the Entity after it is released. Entity#position is
    # relative to the parent: a controller grab puts the shape back under
    # a-scene, and a mouse grab keeps its parent, so it is in world
    # coordinates when the shape is directly under a-scene (which mouse
    # grabbing already assumes).
    def on_release(&block)
      @release_hooks << block
      self
    end

    def run_release_hooks
      run_hooks(@release_hooks)
    end

    # Grabbed with the mouse (moved by the frame loop).
    def following_ray?
      @grabbed && @holder.nil?
    end

    # With a VR controller, the shape is attached to the controller.
    # With the mouse, it is ignored until the ray is ready, so the
    # distance is always measured.
    def grab(event = nil)
      return if @grabbed || !@enabled

      cursor = cursor_of(event)
      if controller?(cursor)
        cursor[:object3D].attach(@entity.js[:object3D])
        @holder = cursor
      else
        distance = distance_from_ray_origin
        return if distance.nil?

        @grab_distance = distance
        @holder = nil
      end
      @grabbed = true
      unless @grab_color.nil?
        @original_color = @entity.color
        @entity.color = @grab_color
      end
      @entity.pause_animation if @pause_animation
      run_hooks(@grab_hooks)
    end

    # A mouse grab ends on any mouseup. A controller grab ends only on
    # the mouseup of that controller, so the other hand keeps its shape.
    # Returns true when this call released the shape. The release hooks
    # are run by the mouseup handler (run_release_hooks), not here.
    def release(event = nil)
      return unless @grabbed

      return if !@holder.nil? && !released_by_holder?(event)

      drop
      true
    end

    # Moves the shape to origin + direction * grab_distance.
    def follow(ox, oy, oz, dx, dy, dz)
      d = @grab_distance
      @entity.set_position(ox + dx * d, oy + dy * d, oz + dz * d)
    end

    private

    # Puts the shape back: under a-scene for a controller grab, and the
    # color and animation as they were before the grab.
    def drop
      unless @holder.nil?
        Scene.element[:object3D].attach(@entity.js[:object3D])
        @holder = nil
      end
      @grabbed = false
      unless @grab_color.nil?
        @entity.color = @original_color
        @original_color = nil
      end
      @entity.play_animation if @pause_animation
    end

    # Releases without a mouseup (enabled = false, detach).
    def force_release
      return unless @grabbed

      drop
      run_release_hooks
    end

    # A hook that raises is reported and does not stop the others.
    def run_hooks(hooks)
      hooks.each do |hook|
        begin
          hook.call(@entity)
        rescue => e
          puts "AFrame::Grabbable hook error: #{e.message}"
        end
      end
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
      r = self.class.ray
      return nil if r.nil?

      origin = r[:origin]
      pos = @entity.position
      ddx = pos[:x] - origin[:x]
      ddy = pos[:y] - origin[:y]
      ddz = pos[:z] - origin[:z]
      Math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
    end
  end
end
