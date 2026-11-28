module AFrame
  # The value for A-Frame's animation component, written the way the rest
  # of this library is: times in seconds and easings with AFrame::Easing's
  # names.
  #
  #   entity animation: AFrame.animation(:rotation, to: [3, 0, -4], dur: 3,
  #                                      alternate: true, easing: :ease_in_out_sine)
  #   box animation__spin: AFrame.animation(:rotation, to: [0, 360, 0], dur: 4, loop: true)
  #
  # property is the animated property (:rotation, :position, :scale,
  # "material.color", ...; rotation is in degrees, as in the attribute).
  # to: / from: take what attributes take ([x, y, z], a number, a color;
  # a number for scale sets all three axes).
  # dur: and delay: are seconds (fractions too). easing: takes a Symbol
  # like AFrame::Easing's (:ease_in_out_sine => "easeInOutSine") or
  # A-Frame's name as a String. loop: is true or a count. alternate: true
  # goes there and back (dir: alternate) and loops, unless loop: is given.
  # Other keywords go to the component as they are, snake_case turned
  # into A-Frame's camelCase (start_events: "click" => startEvents).
  def self.animation(property, to: nil, from: nil, dur: nil, delay: nil, easing: nil,
                     loop: nil, alternate: false, **others)
    value = { property: property.to_s }
    # The attribute's short forms apply (scale: 2 is [2, 2, 2]).
    value[:from] = Entity.shorthand(property.to_s, from) unless from.nil?
    value[:to] = Entity.shorthand(property.to_s, to) unless to.nil?
    value[:dur] = seconds_to_ms(dur) unless dur.nil?
    value[:delay] = seconds_to_ms(delay) unless delay.nil?
    value[:easing] = easing_name(easing) unless easing.nil?
    if alternate
      value[:dir] = "alternate"
      value[:loop] = loop.nil? ? true : loop
    elsif !loop.nil?
      value[:loop] = loop
    end
    others.each { |key, v| value[camel_case(key.to_s).to_sym] = v }
    value
  end

  def self.seconds_to_ms(seconds)
    raise ArgumentError, "a time in seconds is a number, not #{seconds.inspect}" unless seconds.is_a?(Numeric)

    (seconds * 1000).round
  end

  # :ease_in_out_sine => "easeInOutSine"; a String is kept.
  def self.easing_name(easing)
    easing.is_a?(Symbol) ? camel_case(easing.to_s) : easing.to_s
  end

  def self.camel_case(name)
    parts = name.split("_")
    first = parts.shift.to_s
    first + parts.map { |part| part.empty? ? "" : part[0].upcase + part[1, part.size - 1] }.join
  end
end
