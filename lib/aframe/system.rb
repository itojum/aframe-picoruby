module AFrame
  # An A-Frame system written in Ruby (AFRAME.registerSystem): one per
  # scene, for work that looks at the whole scene.
  #
  #   class Garden < AFrame::System
  #     register "garden"
  #     schema max: 20                 # <a-scene garden="max: 50">
  #
  #     def tick(time, delta)
  #       flowers = Flower.instances   # every live Flower component
  #       flowers.first.el.remove if flowers.size > data.max
  #     end
  #   end
  #
  # Written like AFrame::Component: register, schema and the hooks init,
  # update(old_data), tick(time, delta), pause and play (when the scene
  # pauses and plays). A-Frame systems are never removed, so there is no
  # remove. tick runs every frame after
  # all the components' ticks, from the same frame loop (only the scene
  # Scene.ready picked ticks it). Hooks run inside A-Frame, so they must
  # not await.
  class System
    class << self
      # Registers the system under name. The JS side is registered in a
      # microtask, so schema can come before or after register; A-Frame
      # creates it for scenes that already exist.
      def register(name)
        raise "#{self} is already registered as #{@system_name}" if @system_name
        raise "#{name} is already registered" if System.classes.key?(name)
        # picoruby-frame is the frame loop's own system (Scene.start).
        raise "#{name} is reserved" if name == "picoruby-frame"
        if JS.eval("AFRAME.systems[#{name.inspect}] ? true : false")
          raise "#{name} is already registered in A-Frame"
        end

        @system_name = name
        System.classes[name] = self
        System.install
        JS.global.__aframe_defineSystem(name) do |event, id, arg|
          System.dispatch(self, event, id, arg)
        end
        self
      end

      def system_name
        @system_name
      end

      # Same as Component.schema (a value that is not a Hash is the
      # default). The attribute is on a-scene.
      def schema(definition = nil)
        @schema = Component.normalize_schema(definition) unless definition.nil?
        @schema || {}
      end

      # Called from JS (synchronously) for each lifecycle event.
      def dispatch(klass, event, id, arg)
        return JS::Bridge.to_js(Component.js_value(klass.schema)) if event == "schema"

        if event == "init"
          instance = klass.new(arg)
          registry[id] = instance
          instance.playing = arg[:el][:isPlaying] ? true : false
          safely(instance, :init)
          return nil
        end

        instance = registry[id]
        return nil if instance.nil?

        if event == "update"
          safely(instance, :update, arg)
        elsif event == "play"
          instance.playing = true
          safely(instance, :play)
        elsif event == "pause"
          instance.playing = false
          safely(instance, :pause)
        end
        nil
      end

      def classes
        return System.classes unless equal?(System)

        @classes ||= {}
      end

      def registry
        return System.registry unless equal?(System)

        @registry ||= {}
      end

      # The instances of this system (one per scene; all systems when
      # called on AFrame::System).
      def instances
        System.registry.values.select { |instance| instance.is_a?(self) }
      end

      def install
        return if System.installed?

        System.instance_variable_set(:@installed, true)
        JS.eval(DEFINE_SOURCE)
        Scene.start
      end

      def installed?
        System.instance_variable_get(:@installed) ? true : false
      end

      # Calls tick on the playing systems of the scene the frame loop
      # follows (from Scene, once a frame, after the components).
      def tick_all(time, delta)
        scene = JS.global[:__aframe_frameScene]
        registry.values.each do |instance|
          next unless instance.playing && instance.respond_to?(:tick)
          next unless JS.global[:Object].is(instance.el.js, scene)

          safely(instance, :tick, time, delta)
        end
      end

      private

      # A hook that raises is reported and does not stop the others.
      def safely(instance, hook, *args)
        instance.__send__(hook, *args)
      rescue => e
        puts "AFrame::System #{instance.class.system_name} #{hook} error: #{e.message}"
      end
    end

    DEFINE_SOURCE = <<~JS
      window.__aframe_systemId = 0;
      window.__aframe_defineSystem = (name, call) => {
        queueMicrotask(() => {
          AFRAME.registerSystem(name, {
            schema: call("schema", 0, null),
            init() {
              this.__rubyId = ++window.__aframe_systemId;
              call("init", this.__rubyId, this);
              // A-Frame does not call play / pause on systems; follow the
              // scene's own events (children's bubble up, so check target).
              this.el.addEventListener("play", (e) => { if (e.target === this.el) call("play", this.__rubyId, null); });
              this.el.addEventListener("pause", (e) => { if (e.target === this.el) call("pause", this.__rubyId, null); });
            },
            update(oldData) { call("update", this.__rubyId, oldData); }
          });
        });
      };
    JS

    attr_reader :system
    attr_accessor :playing

    # system is the JS system (this in AFRAME.registerSystem).
    # Override init, not initialize.
    def initialize(system)
      @system = system
      @el = Entity.new(system[:el])
      @playing = false
    end

    # The a-scene element as an Entity.
    def el
      @el
    end

    # The parsed a-scene attribute (data.max), or the value itself for a
    # single-property schema.
    def data
      @system[:data]
    end

    # Hooks to override (tick(time, delta) is called only when defined).
    def init; end

    def update(old_data); end

    def play; end

    def pause; end

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

    def deg_to_rad(degrees)
      degrees * Math::PI / 180
    end

    def rad_to_deg(radians)
      radians * 180 / Math::PI
    end
  end
end
