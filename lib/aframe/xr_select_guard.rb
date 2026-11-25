module AFrame
  # In A-Frame 1.6, every cursor other than rayOrigin: mouse also listens to
  # the XR session's selectstart / selectend on enter-vr, without checking
  # which hand fired them. With two controllers, one trigger would then
  # drive both cursors. For cursors that already get their own controller's
  # events (downEvents, as laser-controls sets), remove those session
  # listeners.
  class XRSelectGuard
    class << self
      def install
        return if @installed

        @installed = true
        # Not sync: runs after the cursors' own enter-vr listeners.
        Scene.element.addEventListener("enter-vr") { |_event| detach }
        # Also for a session that is already running (does nothing outside VR).
        detach
      end

      private

      def detach
        session = Scene.element[:xrSession]
        return if session.nil?

        JS.document.querySelectorAll("[cursor]").to_a.each do |el|
          cursor = el[:components][:cursor]
          detach_cursor(session, cursor) if controller_cursor?(cursor)
        end
      end

      def controller_cursor?(cursor)
        return false if cursor.nil?

        data = cursor[:data]
        data[:rayOrigin] != "mouse" && data[:downEvents][:length] > 0
      end

      def detach_cursor(session, cursor)
        session.removeEventListener("selectstart", cursor[:onCursorDown])
        session.removeEventListener("selectend", cursor[:onCursorUp])
      end
    end
  end
end
