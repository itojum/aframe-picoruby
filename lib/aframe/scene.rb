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

      private

      def wait(ms)
        JS.eval("new Promise(r => setTimeout(r, #{ms}))").await
      end
    end
  end
end