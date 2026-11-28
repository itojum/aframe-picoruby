module AFrame
  # Thin wrapper around an A-Frame element (a-box, a-sphere, ...).
  class Entity
    def self.all(selector)
      JS.document.querySelectorAll(selector).to_a.map { |js| new(js) }
    end

    # The first element matching selector as an Entity, or nil
    # (querySelector).
    def self.find(selector)
      js = JS.document.querySelector(selector)
      js.nil? ? nil : new(js)
    end

    # Creates <tag> with the attributes, appends it to parent (an Entity,
    # a JS element or a selector; a-scene when omitted) and returns it as
    # an Entity. A selector that matches nothing raises.
    #
    #   AFrame::Entity.create("a-box", position: [0, 1, -3], color: "tomato")
    #   AFrame::Entity.create("a-entity", parent: "#school")
    #
    # The element is usable right away; A-Frame finishes loading it (sets
    # hasLoaded) on a later turn of the event loop.
    def self.create(tag, parent: nil, **attributes)
      parent_js = parent_element(parent)
      entity = new(JS.document.createElement(tag))
      attributes.each { |name, value| entity.set_attribute(name, value) }

      parent_js.appendChild(entity.js)
      entity
    end

    # Looked up before the element is created, so a bad selector raises
    # without leaving anything half made.
    def self.parent_element(parent)
      if parent.is_a?(Entity)
        parent.js
      elsif parent.is_a?(String)
        found = JS.document.querySelector(parent)
        raise "#{parent} not found" if found.nil?

        found
      elsif parent.nil?
        found = Scene.element || JS.document.querySelector("a-scene")
        raise "a-scene not found" if found.nil?

        found
      else
        parent
      end
    end

    COORDINATE_KEYS = ["x", "y", "z", "w"]

    # A-Frame attribute string for a Ruby value:
    #   [0, 1, -3]                          => "0 1 -3"
    #   { x: 0, y: 1, z: -3 }               => "0 1 -3"  (vec2/3/4 order)
    #   { property: "rotation", dur: 500 } => "property: rotation; dur: 500"
    # Strings are kept as they are; anything else uses to_s.
    def self.attribute_value(value)
      if value.is_a?(String)
        value
      elsif value.is_a?(Array)
        value.map { |v| v.to_s }.join(" ")
      elsif value.is_a?(Hash) && coordinates?(value)
        present = COORDINATE_KEYS.select { |k| value.key?(k.to_sym) || value.key?(k) }
        present.map { |k| (value.key?(k.to_sym) ? value[k.to_sym] : value[k]).to_s }.join(" ")
      elsif value.is_a?(Hash)
        value.map { |k, v| "#{k}: #{attribute_value(v)}" }.join("; ")
      else
        value.to_s
      end
    end

    COORDINATE_KEY_SETS = [%w[x y], %w[x y z], %w[w x y z]]

    # { x:, y: } / { x:, y:, z: } / { x:, y:, z:, w: } (Symbol or String keys).
    def self.coordinates?(hash)
      COORDINATE_KEY_SETS.include?(hash.keys.map { |k| k.to_s }.sort)
    end

    # The bridge's setAttribute takes two strings only; these pass an
    # object, or a component name, a property and a value.
    # With wait, the write goes in a microtask: a Ruby component waits in
    # one (queued by register, so earlier) until its class body is done,
    # and this one then runs after it is registered.
    SETTERS_SOURCE = <<~JS
      window.__aframe_setProperties = (el, name, properties, wait) => {
        const set = () => el.setAttribute(name, properties);
        wait ? queueMicrotask(set) : set();
      };
      window.__aframe_setProperty = (el, name, property, value, wait) => {
        const set = () => el.setAttribute(name, property, value);
        wait ? queueMicrotask(set) : set();
      };
    JS

    def self.install_setters
      JS.eval(SETTERS_SOURCE) if JS.global[:__aframe_setProperty].nil?
    end

    # A Hash of properties (not coordinates) with ";" in a value.
    def self.semicolon_properties?(value)
      return false unless value.is_a?(Hash) && !coordinates?(value)

      value.values.any? { |v| attribute_value(v).include?(";") }
    end

    # Whether A-Frame knows the component (name__id uses name).
    def self.component?(name)
      base = name.split("__").first
      JS.eval("AFRAME.components[#{base.inspect}] ? true : false")
    end

    # A Ruby component registered in Ruby but still waiting for its
    # microtask (it is never registered early, so its class body is done
    # first).
    def self.waiting_component?(name)
      Component.classes.key?(name.split("__").first) && !component?(name)
    end

    # Short forms of a value, by attribute name:
    #   scale: 0.5   => [0.5, 0.5, 0.5] (A-Frame would read "0.5" as x only)
    #   swim: true   => "" (the component with its defaults), only for a
    #                   component with several properties, so a single
    #                   boolean property (visible: true) keeps its value
    def self.shorthand(name, value)
      if name == "scale" && (value.is_a?(Integer) || value.is_a?(Float))
        [value, value, value]
      elsif value == true && multi_property_component?(name)
        ""
      else
        value
      end
    end

    # A component (Ruby or A-Frame) whose schema has several properties.
    # Unknown names are not.
    def self.multi_property_component?(name)
      base = name.split("__").first
      klass = Component.classes[base]
      unless klass.nil?
        keys = klass.schema.keys.map { |k| k.to_s }
        return !keys.include?("type") && !keys.include?("default")
      end

      JS.eval("(c => !!c && !c.isSingleProperty)(AFRAME.components[#{base.inspect}])") ? true : false
    end

    def self.attribute_name(symbol)
      symbol.to_s.split("__").map { |part| part.tr("_", "-") }.join("__")
    end

    attr_reader :js

    def initialize(js)
      @js = js
    end

    # Symbol names use - for a single _ (look_controls: => "look-controls");
    # __ is kept, as A-Frame uses it for multiple instances of a component
    # (animation__spin: => "animation__spin").
    # setAttribute only takes two strings, so values go through
    # Entity.attribute_value.
    #
    # A property value with ";" (label: { value: "a; b" }) cannot go in the
    # one-string form, where ";" separates properties, so such a Hash is
    # passed as a JS object, property by property. That needs a registered
    # component (an unknown one would get "[object Object]"), so for a Ruby
    # component still waiting to register, the write waits until it is.
    #
    # scale: 0.5 sets all three axes, and component: true attaches a
    # component with several properties with its defaults (see shorthand).
    #
    # With three arguments, sets one property of a component and leaves the
    # others as they are (any text, ";" included):
    #   hint.set_attribute(:label, :value, "つかんだ！")
    def set_attribute(name, value, *property_value)
      name = name.is_a?(Symbol) ? Entity.attribute_name(name) : name.to_s
      unless property_value.empty?
        Entity.install_setters
        JS.global.__aframe_setProperty(@js, name, value.to_s, Entity.attribute_value(property_value.first),
                                       Entity.waiting_component?(name))
        return self
      end
      value = Entity.shorthand(name, value)
      waiting = Entity.waiting_component?(name)
      if Entity.semicolon_properties?(value) && (waiting || Entity.component?(name))
        properties = {}
        value.each { |k, v| properties[k.to_s] = Entity.attribute_value(v) }
        # The bridge's setAttribute takes two strings only, so go through JS.
        Entity.install_setters
        JS.global.__aframe_setProperties(@js, name, JS::Bridge.to_js(properties), waiting)
      else
        @js.setAttribute(name, Entity.attribute_value(value))
      end
      self
    end

    # Moves child (an Entity or a JS element) under this entity.
    def append(child)
      @js.appendChild(child.is_a?(Entity) ? child.js : child)
      child
    end

    def color
      @js.getAttribute("color")
    end

    def color=(value)
      @js.setAttribute("color", value)
    end

    # object3D.position (THREE.Vector3, relative to the parent). Writing to
    # it moves the element:
    #   el.position.x = 1
    def position
      @js[:object3D][:position]
    end

    # object3D.rotation (THREE.Euler, in radians):
    #   el.rotation.y = -angle
    def rotation
      @js[:object3D][:rotation]
    end

    # object3D.scale (THREE.Vector3).
    def scale
      @js[:object3D][:scale]
    end

    # object3D.visible: whether the element (and its children) is drawn.
    #   el.visible = false
    # It writes object3D directly, which is light enough for every frame;
    # the visible attribute (set_attribute(:visible, false)) is not changed,
    # so the HTML still shows the value it was given.
    def visible
      @js[:object3D][:visible] ? true : false
    end

    def visible=(value)
      @js[:object3D][:visible] = value ? true : false
    end

    # Same as position.set(x, y, z).
    def set_position(x, y, z)
      @js[:object3D][:position].set(x, y, z)
    end

    def pause_animation
      animation&.pause
    end

    def play_animation
      animation&.play
    end

    # Any other method goes to the JS element (JS::Object reads, writes
    # or calls the JS property of that name), so A-Frame properties read
    # as they do in JS:
    #   box.object3D.rotation.y += 0.1
    # Methods of Entity and Object (class, hash, send, ...) are not
    # forwarded; use js for those.
    def method_missing(name, *args, &block)
      @js.__send__(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      !name.to_s.end_with?("?", "!")
    end

    private

    def animation
      @js[:components][:animation]
    end
  end
end
