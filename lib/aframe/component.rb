module AFrame
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
      def register(name, multiple: false)
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
        elsif event == "pause"
          instance.playing = false
        elsif event == "remove"
          instance.playing = false
          registry.delete(id)
          safely(instance, :remove)
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

      def installed?
        Component.instance_variable_get(:@installed) ? true : false
      end

      # Calls tick on every playing instance (from Scene, once a frame).
      def tick_all(time, delta)
        # A copy, as a tick may remove an element (and its instance).
        registry.values.each do |instance|
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
      // A registration waits in a microtask (after the class body), unless
      // __aframe_flushComponent runs it first (Entity#set_attribute needs a
      // registered component to pass properties as an object).
      window.__aframe_pendingComponents = {};
      window.__aframe_flushComponent = (name) => {
        const run = window.__aframe_pendingComponents[name];
        if (run) run();
      };
      window.__aframe_defineComponent = (name, multiple, call) => {
        const run = () => {
          if (window.__aframe_pendingComponents[name] !== run) return;
          delete window.__aframe_pendingComponents[name];
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
        };
        window.__aframe_pendingComponents[name] = run;
        queueMicrotask(run);
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

    def deg_to_rad(degrees)
      degrees * Math::PI / 180
    end

    def rad_to_deg(radians)
      radians * 180 / Math::PI
    end
  end
end
