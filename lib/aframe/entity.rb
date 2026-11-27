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
    def set_attribute(name, value)
      name = name.is_a?(Symbol) ? Entity.attribute_name(name) : name.to_s
      @js.setAttribute(name, Entity.attribute_value(value))
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
