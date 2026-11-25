module AFrame
  # Stops look-controls while a shape is being grabbed
  # (lock-camera-on-grab in 1.html).
  class CameraLock
    class << self
      def install(camera: "a-camera", raycaster: "[raycaster]")
        @camera = find(camera)
        @raycaster = find(raycaster)

        # Must run before look-controls starts dragging, so this is a
        # sync handler in the capture phase. No await inside.
        JS.global.addEventListener("mousedown", sync: true, capture: true) do |_event|
          lock if hovering?
        end
        JS.global.addEventListener("mouseup") { |_event| unlock }
      end

      private

      def find(selector)
        el = JS.document.querySelector(selector)
        raise "#{selector} not found" if el.nil?

        el
      end

      def hovering?
        component = @raycaster[:components][:raycaster]
        return false if component.nil?

        els = component[:intersectedEls]
        !els.nil? && els[:length] > 0
      end

      # Disables look-controls and remembers whether it was enabled,
      # so unlock restores it only when this lock was taken.
      def lock
        return if @locked

        look_controls = @camera[:components]["look-controls"]
        return if look_controls.nil?

        @previous_enabled = look_controls[:data][:enabled]
        look_controls[:mouseDown] = false
        @camera.setAttribute("look-controls", "enabled: false")
        @locked = true
      end

      def unlock
        return unless @locked

        @locked = false
        @camera.setAttribute("look-controls", "enabled: #{@previous_enabled}")
      end
    end
  end
end
