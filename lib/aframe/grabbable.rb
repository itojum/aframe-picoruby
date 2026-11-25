module AFrame
  # Shapes that can be grabbed with the mouse (my-grabbable in 1.html).
  class Grabbable
    GRAB_COLOR = "#ffffff"

    class << self
      def attach_all(selector)
        @items ||= []
        added = Entity.all(selector).map { |entity| new(entity) }
        @items.concat(added)
        install_release
        added
      end

      def items
        @items || []
      end

      private

      # One window mouseup for all instances.
      def install_release
        return if @release_installed

        @release_installed = true
        JS.global.addEventListener("mouseup") do |_event|
          items.each { |item| item.release }
        end
      end
    end

    attr_reader :entity

    def initialize(entity)
      @entity = entity
      @original_color = entity.color
      @grabbed = false
      entity.js.addEventListener("mousedown") { |_event| grab }
    end

    def grabbed?
      @grabbed
    end

    def grab
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
  end
end
