module AFrame
  # Shapes that can be grabbed with the mouse (my-grabbable in 1.html).
  # A grabbed shape follows the mouse ray at the distance it was grabbed.
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
        JS.global.addEventListener("mouseup") do |_event|
          items.each { |item| item.release }
        end
        Scene.on_tick { update }
      end

      def update
        held = items.select { |item| item.grabbed? }
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
      entity.js.addEventListener("mousedown") { |_event| grab }
    end

    def grabbed?
      @grabbed
    end

    # Ignored until the ray is ready, so the distance is always measured.
    def grab
      distance = distance_from_ray_origin
      return if distance.nil?

      @grab_distance = distance
      @grabbed = true
      @entity.color = GRAB_COLOR
      @entity.pause_animation
    end

    def release
      return unless @grabbed

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
