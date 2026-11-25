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
      def run
        JS.eval("window.__aframe_nextFrame = () => new Promise(r => requestAnimationFrame(r))")
        while true
          JS.global.__aframe_nextFrame.await
          tick_handlers.each { |handler| handler.call }
        end
      end

      private

      def tick_handlers
        @tick_handlers ||= []
      end

      def wait(ms)
        JS.eval("new Promise(r => setTimeout(r, #{ms}))").await
      end
    end
  end
end
