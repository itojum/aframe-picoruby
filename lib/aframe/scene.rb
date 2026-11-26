module AFrame
  class Scene
    class << self
      def ready(selector = "a-scene")
        @element = JS.document.querySelector(selector)
        raise "#{selector} not found" if @element.nil?

        wait(50) until @element[:hasLoaded]
        @element
      end

      def element
        @element
      end

      # Registers a block called once per frame with (time, delta) in ms.
      # The block runs inside A-Frame's tick, before the frame is drawn,
      # so it must not await.
      def on_tick(&block)
        tick_handlers << block
        block
      end

      # Starts calling the on_tick handlers and returns. Safe to call more
      # than once.
      def start
        return if @started

        @started = true
        JS.eval(FRAME_SOURCE)
        # A block passed to a JS function becomes a JS function that runs
        # Ruby synchronously, so the handlers run inside the system's tick
        # (after the components' ticks, before the render). Resuming a
        # task with a Promise would run them after the render instead,
        # and the changes would show one frame late.
        JS.global.__aframe_setFrameCallback { |time, delta| tick(time, delta) }
      end

      # Frame loop (the tick of A-Frame components). Never returns.
      # Frames come from A-Frame's own render loop (a system's tick), not
      # window.requestAnimationFrame, which may not run during an immersive
      # WebXR session.
      def run
        raise "call AFrame::Scene.ready first" if @element.nil?

        start
        JS.eval("new Promise(() => {})").await
      end

      private

      FRAME_SOURCE = <<~JS
        if (!AFRAME.systems["picoruby-frame"]) {
          AFRAME.registerSystem("picoruby-frame", {
            tick(time, delta) {
              if (window.__aframe_frameCallback) window.__aframe_frameCallback(time, delta);
            }
          });
        }
        window.__aframe_setFrameCallback = (fn) => { window.__aframe_frameCallback = fn; };
      JS

      # A handler that raises is reported and does not stop the others.
      def tick(time, delta)
        tick_handlers.each do |handler|
          begin
            handler.call(time, delta)
          rescue => e
            puts "AFrame::Scene on_tick error: #{e.message}"
          end
        end
        nil
      end

      def tick_handlers
        @tick_handlers ||= []
      end

      def wait(ms)
        JS.eval("new Promise(r => setTimeout(r, #{ms}))").await
      end
    end
  end
end
