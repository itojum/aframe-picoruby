module AFrame
  class Scene
    class << self
      def ready(selector = "a-scene")
        @element = JS.document.querySelector(selector)
        raise "#{selector} not found" if @element.nil?

        wait(50) until @element[:hasLoaded]
        JS.global[:__aframe_frameScene] = @element if @started
        @element
      end

      def element
        @element
      end

      # Registers a block called once per frame with (time, delta) in ms.
      # For small experiments: frame work normally belongs in a component
      # or system tick (README: 毎フレームの処理をどこに書くか).
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
        # Only this scene's tick calls the handlers, so a second scene
        # does not run them twice and pausing this one stops them. Before
        # ready, it is the first a-scene (or the first one that ticks).
        JS.global[:__aframe_frameScene] = @element || JS.document.querySelector("a-scene")
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
              if (!window.__aframe_frameScene) window.__aframe_frameScene = this.el;
              if (this.el !== window.__aframe_frameScene) return;
              if (window.__aframe_frameCallback) window.__aframe_frameCallback(time, delta);
            }
          });
        }
        window.__aframe_setFrameCallback = (fn) => { window.__aframe_frameCallback = fn; };
      JS

      # Each frame: the Ruby components' ticks, then the Ruby systems'
      # ticks (the order A-Frame uses), then the on_tick handlers.
      # A handler that raises is reported and does not stop the others.
      def tick(time, delta)
        Component.tick_all(time, delta) if Component.installed?
        System.tick_all(time, delta) if System.installed?
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
