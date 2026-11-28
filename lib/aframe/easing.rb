module AFrame
  # Easing functions: t from 0 to 1 in, 0 to 1 out (0 at 0, 1 at 1).
  # The names follow the easing property of A-Frame's animation component
  # (easeInOutSine => ease_in_out_sine), so a move written in Ruby can
  # match one written in HTML:
  #
  #   @t = [@t + delta_seconds / 2.0, 1.0].min
  #   el.position.y = 1 + AFrame::Easing.ease_in_out_sine(@t)
  #
  # These are the usual (Penner) formulas. A-Frame's animation draws the
  # same names with cubic Bezier approximations of them, so the two can
  # differ by up to about 0.035 midway (never at 0 or 1).
  #
  # To pick one from a schema value: AFrame::Easing.send(data.easing, t).
  module Easing
    HALF_PI = Math::PI / 2

    def self.linear(t)
      t
    end

    def self.ease_in_sine(t)
      1 - Math.cos(t * HALF_PI)
    end

    def self.ease_out_sine(t)
      Math.sin(t * HALF_PI)
    end

    def self.ease_in_out_sine(t)
      (1 - Math.cos(Math::PI * t)) / 2
    end

    def self.ease_in_quad(t)
      t * t
    end

    def self.ease_out_quad(t)
      1 - (1 - t) * (1 - t)
    end

    def self.ease_in_out_quad(t)
      t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2.0
    end

    def self.ease_in_cubic(t)
      t * t * t
    end

    def self.ease_out_cubic(t)
      1 - (1 - t) * (1 - t) * (1 - t)
    end

    def self.ease_in_out_cubic(t)
      t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2.0
    end
  end

  # A Float from min up to max (PicoRuby's rand takes neither a Float nor
  # a Range):
  #   AFrame.random(3, 11)   # => 7.284...
  # Component#random and System#random are the same.
  def self.random(min, max)
    min + (max - min) * rand(RANDOM_STEPS) / RANDOM_STEPS.to_f
  end

  RANDOM_STEPS = 1_000_000
end
