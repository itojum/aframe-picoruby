module AFrame
  # Thin wrapper around an A-Frame element (a-box, a-sphere, ...).
  class Entity
    def self.all(selector)
      JS.document.querySelectorAll(selector).to_a.map { |js| new(js) }
    end

    # Creates <tag> with the attributes, appends it to parent (an Entity or
    # a JS element; a-scene when omitted) and returns it as an Entity.
    #
    #   AFrame::Entity.create("a-box", position: [0, 1, -3], color: "tomato")
    #
    # The element is usable right away; A-Frame finishes loading it (sets
    # hasLoaded) on a later turn of the event loop.
    def self.create(tag, parent: nil, **attributes)
      entity = new(JS.document.createElement(tag))
      attributes.each { |name, value| entity.set_attribute(name, value) }
      parent_js = parent.is_a?(Entity) ? parent.js : parent
      parent_js ||= Scene.element || JS.document.querySelector("a-scene")
      raise "a-scene not found" if parent_js.nil?

      parent_js.appendChild(entity.js)
      entity
    end

    # A-Frame attribute string for a Ruby value:
    #   [0, 1, -3]                          => "0 1 -3"
    #   { property: "rotation", dur: 500 } => "property: rotation; dur: 500"
    # Strings are kept as they are; anything else uses to_s.
    def self.attribute_value(value)
      if value.is_a?(String)
        value
      elsif value.is_a?(Array)
        value.map { |v| v.to_s }.join(" ")
      elsif value.is_a?(Hash)
        value.map { |k, v| "#{k}: #{attribute_value(v)}" }.join("; ")
      else
        value.to_s
      end
    end

    attr_reader :js

    def initialize(js)
      @js = js
    end

    # Symbol names use - for _ (look_controls: => "look-controls").
    # setAttribute only takes two strings, so values go through
    # Entity.attribute_value.
    def set_attribute(name, value)
      name = name.is_a?(Symbol) ? name.to_s.tr("_", "-") : name.to_s
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

    # object3D.position as [x, y, z] (relative to the parent).
    def position
      pos = @js[:object3D][:position]
      [pos[:x], pos[:y], pos[:z]]
    end

    # Called every frame, so no Array is created here.
    def set_position(x, y, z)
      @js[:object3D][:position].set(x, y, z)
    end

    def pause_animation
      animation&.pause
    end

    def play_animation
      animation&.play
    end

    private

    def animation
      @js[:components][:animation]
    end
  end
end
