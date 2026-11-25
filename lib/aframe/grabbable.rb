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
      def attach_all(selector, raycaster: "[raycaster]")
        if @raycaster_selector && @raycaster_selector != raycaster
          raise "Grabbable is already attached with #{@raycaster_selector}"
        end

        element = JS.document.querySelector(raycaster)
        raise "#{raycaster} not found" if element.nil?

        @raycaster_selector = raycaster
        @raycaster = element

        @items ||= []
        added = Entity.all(selector).map { |entity| new(entity) }
        @items.concat(added)
        install_handlers
        added
      end

      def items
        @items || []
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
        JS.global.addEventListener("mouseup") do |event|
          items.each { |item| item.release(event) }
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

    def initialize(entity)
      @entity = entity
      @original_color = entity.color
      @grabbed = false
      @grab_distance = 0
      @holder = nil
      entity.js.addEventListener("mousedown") { |event| grab(event) }
    end

    def grabbed?
      @grabbed
    end

    # Grabbed with the mouse (moved by the frame loop).
    def following_ray?
      @grabbed && @holder.nil?
    end

    # With a VR controller, the shape is attached to the controller.
    # With the mouse, it is ignored until the ray is ready, so the
    # distance is always measured.
    def grab(event = nil)
      return if @grabbed

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
      @entity.color = GRAB_COLOR
      @entity.pause_animation
    end

    # A mouse grab ends on any mouseup. A controller grab ends only on
    # the mouseup of that controller, so the other hand keeps its shape.
    def release(event = nil)
      return unless @grabbed

      unless @holder.nil?
        return unless released_by_holder?(event)

        Scene.element[:object3D].attach(@entity.js[:object3D])
        @holder = nil
      end
      @grabbed = false
      @entity.color = @original_color
      @entity.play_animation
    end

    # Moves the shape to origin + direction * grab_distance.
    def follow(ox, oy, oz, dx, dy, dz)
      d = @grab_distance
      @entity.set_position(ox + dx * d, oy + dy * d, oz + dz * d)
    end

    private

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
      x, y, z = @entity.position
      ddx = x - origin[:x]
      ddy = y - origin[:y]
      ddz = z - origin[:z]
      Math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
    end
  end
end
