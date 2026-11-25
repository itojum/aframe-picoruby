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

      # Registers a block called once per frame by run.
      def on_tick(&block)
        tick_handlers << block
        block
      end

      # Frame loop (the tick of A-Frame components). Never returns.
      # Frames come from A-Frame's own render loop (a system's tick), not
      # window.requestAnimationFrame, which may not run during an immersive
      # WebXR session.
      def run
        raise "call AFrame::Scene.ready first" if @element.nil?

        install_frame_source
        while true
          JS.global.__aframe_nextFrame.await
          tick_handlers.each { |handler| handler.call }
        end
      end

      private

      FRAME_SOURCE = <<~JS
        if (!AFRAME.systems["picoruby-frame"]) {
          AFRAME.registerSystem("picoruby-frame", {
            init() { this.waiters = []; },
            tick() {
              const waiters = this.waiters;
              this.waiters = [];
              waiters.forEach((resolve) => resolve());
            }
          });
        }
        window.__aframe_nextFrame = () => new Promise((resolve) =>
          window.__aframe_scene.systems["picoruby-frame"].waiters.push(resolve));
      JS

      # A system registered after the scene has loaded is created for it
      # right away (A-Frame's registerSystem initializes existing scenes).
      def install_frame_source
        JS.global[:__aframe_scene] = @element
        JS.eval(FRAME_SOURCE)
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
