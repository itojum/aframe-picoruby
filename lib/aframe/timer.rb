module AFrame
  # A timer made by Component#after or Component#every. Time goes with
  # the component's ticks (A-Frame's delta), so it stops while the element
  # or the scene is paused, and the timers are dropped when the component
  # is removed.
  #
  #   @timer = after(3) { start_crossing }
  #   @timer.cancel
  class Timer
    # seconds until the first call; every seconds after that when repeat.
    # frame is the frame it was made in (Component.frame), which it does
    # not take part in.
    def initialize(seconds, repeat, block, frame = nil)
      @frame = frame
      @left = seconds.to_f
      @interval = repeat ? seconds.to_f : nil
      @block = block
      @cancelled = false
    end

    # Stops the timer; its block is not called any more.
    def cancel
      @cancelled = true
      nil
    end

    def cancelled?
      @cancelled
    end

    # Whether it will still call its block (not cancelled, and for after,
    # not called yet).
    def active?
      !@cancelled
    end

    # Moves the timer on by seconds and calls the block when it is due:
    # at most once a frame, so a long frame does not call an every timer
    # many times in a row (the missed calls are skipped).
    # A timer made during frame is left out of it, whichever component
    # made it, so it never gets time from before it existed.
    def advance(seconds, frame = nil)
      return if @cancelled
      return if !frame.nil? && frame == @frame

      @left -= seconds
      return if @left > 0

      if @interval.nil?
        @cancelled = true
      else
        @left += @interval
        @left = @interval if @left <= 0
      end
      @block.call
    end
  end
end
