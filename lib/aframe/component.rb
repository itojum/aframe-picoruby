module AFrame
  # The A-Frame name for a class: the part after the last :: in
  # kebab-case, a run of capitals kept together (SpinBox => "spin-box",
  # CameraLock => "camera-lock", XRHand => "xr-hand", AFrame::Label =>
  # "label", XR2Hand => "xr2-hand", Spin_Box => "spin-box").
  # PicoRuby has no Class#name, so this reads to_s.
  def self.default_name(klass)
    full = klass.to_s
    raise ArgumentError, "register needs a name for an anonymous class" if full.start_with?("#")

    base = full.split("::").last
    upper = ->(c) { !c.nil? && c >= "A" && c <= "Z" }
    lower = ->(c) { !c.nil? && c >= "a" && c <= "z" }
    lower_or_digit = ->(c) { lower.call(c) || (!c.nil? && c >= "0" && c <= "9") }
    name = ""
    base.length.times do |i|
      c = base[i]
      if upper.call(c) && i > 0 &&
         (lower_or_digit.call(base[i - 1]) || (upper.call(base[i - 1]) && lower.call(base[i + 1])))
        name << "-"
      end
      # _ becomes -, as in attribute names (Spin_Box => "spin-box").
      if c == "_"
        name << "-" unless name.end_with?("-")
      else
        name << c.downcase
      end
    end
    name
  end

  # An A-Frame component written in Ruby (AFRAME.registerComponent).
  #
  #   class SpinBox < AFrame::Component
  #     register "spin-box"
  #     schema speed: 30
  #
  #     def tick(time, delta)
  #       el.rotation.y += deg_to_rad(data.speed * delta / 1000)
  #     end
  #   end
  #
  #   <a-box spin-box="speed: 90"></a-box>
  #
  # A-Frame reads the schema and calls init / update / remove / play /
  # pause on a JS component whose methods call Ruby synchronously. tick is
  # called from the frame loop for every playing instance, so there is one
  # call from JS to Ruby per frame however many instances there are.
  # Hooks run inside A-Frame, so they must not await.
  class Component
    class << self
      # Registers the component under name. The JS side is registered in a
      # microtask (after the class body, so schema can come before or after
      # register) and picks up elements that already have the attribute.
      # multiple: true lets one element have several instances, each under
      # name__id (spin__fast, spin__slow), as A-Frame's multiple does.
      #
      # Without a name, the class name is used in kebab-case (the part after
      # the last ::): SpinBox => "spin-box", XRHand => "xr-hand".
      def register(name = nil, multiple: false)
        name = AFrame.default_name(self) if name.nil?
        raise "#{self} is already registered as #{@component_name}" if @component_name
        raise "#{name} is already registered" if Component.classes.key?(name)
        if JS.eval("AFRAME.components[#{name.inspect}] ? true : false")
          raise "#{name} is already registered in A-Frame"
        end

        @component_name = name
        Component.classes[name] = self
        Component.install
        JS.global.__aframe_defineComponent(name, multiple ? true : false) do |event, id, arg|
          Component.dispatch(self, event, id, arg)
        end
        self
      end

      def component_name
        @component_name
      end

      # Listens for event on the element while the component plays, like
      # A-Frame's events: connected when it plays, disconnected when it
      # pauses or is removed. The block runs in the instance (el, data and
      # private methods work) and may take the event or nothing:
      #   on(:grab) { show data.grabbed }
      #   on(:release) { |event| p event[:detail][:cursorEl] }
      # Each instance (multiple: true included) gets its own listener.
      # Subclasses keep their parent's handlers.
      def on(event, &block)
        raise ArgumentError, "on needs a block" if block.nil?

        (@event_handlers ||= []) << [event.to_s, block]
        nil
      end

      # [[event, block], ...]: the parent's first, then this class's.
      def event_handlers
        inherited = superclass.respond_to?(:event_handlers) ? superclass.event_handlers : []
        inherited + (@event_handlers || [])
      end

      # Sets the schema (A-Frame's schema with Symbol or String keys and
      # values) or returns it.
      #   schema speed: { type: :number, default: 30 }  # multiple properties
      #   schema speed: 30, label: "x"                  # defaults only
      #   schema type: :number, default: 30             # single property
      # A value that is not a Hash is the property's default; A-Frame then
      # picks the type from it (number, boolean, array or string).
      def schema(definition = nil)
        @schema = Component.normalize_schema(definition) unless definition.nil?
        @schema || {}
      end

      # A schema with type or default at the top is a single property and
      # is kept as it is.
      def normalize_schema(definition)
        return definition unless definition.is_a?(Hash)

        keys = definition.keys.map { |k| k.to_s }
        return definition if keys.include?("type") || keys.include?("default")

        result = {}
        definition.each do |name, property|
          result[name] = property.is_a?(Hash) ? property : { default: property }
        end
        result
      end

      # Called from JS (synchronously) for each lifecycle event.
      def dispatch(klass, event, id, arg)
        if event == "schema"
          return JS::Bridge.to_js(js_value(klass.schema))
        end

        if event == "init"
          instance = klass.new(arg)
          registry[id] = instance
          safely(instance, :init)
          return nil
        end

        instance = registry[id]
        return nil if instance.nil?

        if event == "update"
          safely(instance, :update, arg)
        elsif event == "play"
          instance.playing = true
          instance.connect_events
        elsif event == "pause"
          instance.playing = false
          instance.disconnect_events
        elsif event == "remove"
          instance.playing = false
          instance.disconnect_events
          registry.delete(id)
          safely(instance, :remove)
          instance.cancel_timers
        end
        nil
      end

      def classes
        @classes ||= {}
      end

      # Every live instance of every Ruby component, by id. Shared by all
      # subclasses, so it always lives on Component.
      def registry
        return Component.registry unless equal?(Component)

        @registry ||= {}
      end

      # The live instances of this component (all components when called
      # on AFrame::Component), in the order they were created:
      #   Flower.instances.each { |flower| ... }
      def instances
        Component.registry.values.select { |instance| instance.is_a?(self) }
      end

      # Defines the JS helper and starts the frame loop, once. Scene calls
      # tick_all every frame before the systems and the on_tick handlers.
      def install
        return if Component.installed?

        Component.instance_variable_set(:@installed, true)
        JS.eval(DEFINE_SOURCE)
        Scene.start
      end

      # The number of frames tick_all has run (timers use it to skip the
      # frame they were made in).
      def frame
        Component.instance_variable_get(:@frame) || 0
      end

      def installed?
        Component.instance_variable_get(:@installed) ? true : false
      end

      # Moves the timers on and calls tick on every playing instance (from
      # Scene, once a frame). Timers go first, so what they change shows in
      # the same frame's tick.
      def tick_all(time, delta)
        Component.instance_variable_set(:@frame, frame + 1)
        seconds = delta / 1000.0
        # A copy, as a tick may remove an element (and its instance).
        registry.values.each do |instance|
          next unless instance.playing

          instance.advance_timers(seconds)
          # A timer may have removed the element.
          next unless instance.playing && instance.respond_to?(:tick)

          safely(instance, :tick, time, delta)
        end
      end

      # Symbols become strings, so the bridge passes them to JS.
      def js_value(value)
        if value.is_a?(Hash)
          result = {}
          value.each { |k, v| result[k.to_s] = js_value(v) }
          result
        elsif value.is_a?(Array)
          value.map { |v| js_value(v) }
        elsif value.is_a?(Symbol)
          value.to_s
        else
          value
        end
      end

      private

      # A hook that raises is reported and does not stop the others.
      def safely(instance, hook, *args)
        instance.__send__(hook, *args)
      rescue => e
        puts "AFrame::Component #{instance.class.component_name} #{hook} error: #{e.message}"
      end
    end

    DEFINE_SOURCE = <<~JS
      // Ids are shared by every Ruby component, as Component.registry is
      // keyed by id alone.
      window.__aframe_componentId = 0;
      window.__aframe_defineComponent = (name, multiple, call) => {
        queueMicrotask(() => {
          AFRAME.registerComponent(name, {
            schema: call("schema", 0, null),
            multiple: multiple,
            init() { this.__rubyId = ++window.__aframe_componentId; call("init", this.__rubyId, this); },
            update(oldData) { call("update", this.__rubyId, oldData); },
            play() { call("play", this.__rubyId, null); },
            pause() { call("pause", this.__rubyId, null); },
            remove() { call("remove", this.__rubyId, null); }
          });
          // Elements that loaded before the component existed, under name
          // (or name__id when multiple). Only a multiple component needs
          // to look at every element, as CSS cannot match name__*.
          const matches = (attr) => attr === name || (multiple && attr.startsWith(name + "__"));
          document.querySelectorAll(multiple ? "*" : "[" + name + "]").forEach((el) => {
            if (!el.hasLoaded || !el.components) return;
            Array.from(el.attributes).map((a) => a.name).filter(matches).forEach((attr) => {
              if (!el.components[attr]) el.setAttribute(attr, el.getAttribute(attr) || "");
            });
          });
        });
      };
    JS

    attr_reader :component
    attr_accessor :playing

    # component is the JS component (this in AFRAME.registerComponent).
    # Override init, not initialize.
    def initialize(component)
      @component = component
      @el = Entity.new(component[:el])
      @playing = false
    end

    # The element as an Entity (el.object3D etc. go to JS).
    def el
      @el
    end

    # The part after __ for a multiple component (spin__fast => "fast"),
    # or nil.
    def id
      @component[:id]
    end

    # The parsed attribute: a JS object for a multi-property schema
    # (data.speed), or the value itself for a single-property one.
    def data
      @component[:data]
    end

    # Hooks to override (tick(time, delta) is called only when defined).
    def init; end

    def update(old_data); end

    def remove; end

    # This frame's delta in seconds (delta / 1000.0), for speeds per second
    # in tick:
    #   el.position.x += data.speed * delta_seconds
    def delta_seconds
      Scene.delta_seconds
    end

    # A Float from min up to max (AFrame.random).
    def random(min, max)
      AFrame.random(min, max)
    end

    # Calls the block once, seconds from now (in the component's time: it
    # stops while paused). Returns an AFrame::Timer; timer.cancel stops it.
    #   @timer = after(random(3, 11)) { start_crossing }
    def after(seconds, &block)
      add_timer(seconds, false, block)
    end

    # Calls the block every seconds (the first time seconds from now), at
    # most once a frame, until cancelled or the component is removed.
    #   every(1) { blink }
    def every(seconds, &block)
      raise ArgumentError, "every needs a time above 0" unless seconds > 0

      add_timer(seconds, true, block)
    end

    # Called by tick_all: moves this component's timers on.
    def advance_timers(seconds)
      return if @timers.nil? || @timers.empty?

      # A copy, as a block may add or cancel timers.
      frame = Component.frame
      @timers.dup.each do |timer|
        # A timer may have paused or removed the element: the rest keep
        # their time until it plays again.
        break unless @playing

        begin
          timer.advance(seconds, frame)
        rescue => e
          puts "AFrame::Component #{self.class.component_name} timer error: #{e.message}"
        end
      end
      @timers = @timers.select { |timer| timer.active? }
    end

    # Cancels every timer (called when the component is removed). Timers
    # made after that come back already cancelled, so nothing is kept for
    # a component that will never tick again.
    def cancel_timers
      @removed = true
      return if @timers.nil?

      @timers.each { |timer| timer.cancel }
      @timers = []
    end

    # Connects the class's on handlers (called on play).
    def connect_events
      return unless @listeners.nil?

      @listeners = self.class.event_handlers.map do |event, block|
        takes_event = !(block.lambda? && block.arity == 0)
        el.on(event) do |e|
          begin
            takes_event ? instance_exec(e, &block) : instance_exec(&block)
          rescue => error
            puts "AFrame::Component #{self.class.component_name} #{event} error: #{error.message}"
          end
        end
      end
    end

    # Disconnects them (called on pause and remove).
    def disconnect_events
      return if @listeners.nil?

      @listeners.each { |listener| el.off(listener) }
      @listeners = nil
    end

    def deg_to_rad(degrees)
      degrees * Math::PI / 180
    end

    def rad_to_deg(radians)
      radians * 180 / Math::PI
    end

    private

    def add_timer(seconds, repeat, block)
      raise ArgumentError, "a timer needs a block" if block.nil?

      timer = Timer.new(seconds, repeat, block, Component.frame)
      if @removed
        timer.cancel
      else
        (@timers ||= []) << timer
      end
      timer
    end
  end
end
