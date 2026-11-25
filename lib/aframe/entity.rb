module AFrame
  # Thin wrapper around an A-Frame element (a-box, a-sphere, ...).
  class Entity
    def self.all(selector)
      JS.document.querySelectorAll(selector).to_a.map { |js| new(js) }
    end

    attr_reader :js

    def initialize(js)
      @js = js
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
