module AFrame
  # Builds elements in a block (AFrame.scene). Inside the block self is a
  # Builder, which only has methods that create elements, so a tag name
  # never means a JS property (Entity forwards unknown methods to JS).
  #
  #   AFrame.scene do
  #     entity position: [0, 0, -3] do
  #       box position: [0, 1, 0], color: "tomato"
  #       tag "a-gltf-model", src: "#fish"
  #     end
  #   end
  #
  # Each tag method creates the element with Entity.create and returns the
  # Entity; with a block, the block runs in a Builder for that element.
  class Builder
    class << self
      # Defines a method for every primitive A-Frame knows (a-box => box,
      # a-gltf-model => gltf_model) plus entity. Primitives registered later
      # are added on the next AFrame.scene. A name a Builder already
      # answers to, private ones included (tag, created, initialize, puts,
      # ...), is left alone; such a tag is made with tag "a-...".
      def define_tags
        tags = JS.eval("Object.keys(AFRAME.primitives.primitives).join(' ')").to_s.split(" ")
        tags << "a-entity"
        probe = Builder.new
        tags.each do |tag_name|
          name = method_name(tag_name)
          next if name.empty? || probe.respond_to?(name.to_sym, true)

          define_method(name.to_sym) do |*components, **attributes, &block|
            tag(tag_name, *components, **attributes, &block)
          end
        end
      end

      def method_name(tag)
        name = tag.start_with?("a-") ? tag[2, tag.size - 2] : tag
        name.tr("-", "_")
      end

      # Names defined with AFrame.part.
      def parts
        @parts ||= {}
      end

      # Defines a part (AFrame.part). A name a Builder already answers to
      # (a tag, tag, children, puts, ...) raises; a part can be defined
      # again.
      def define_part(name, definition)
        name = name.to_sym
        define_tags
        if !parts.key?(name) && Builder.new.respond_to?(name, true)
          raise ArgumentError, "#{name} is already a Builder method (a tag or a method of Builder)"
        end

        parts[name] = definition
        define_method(name) do |*components, **attributes, &block|
          make_part(definition, components, attributes, block)
        end
        name
      end

      # Splits a part's keywords: component names (A-Frame's or Ruby's,
      # position / rotation / animation__x ...) and id / class / mixin go
      # on the part's a-entity, the rest to the part's block.
      def split_part_attributes(attributes)
        outer = {}
        options = {}
        attributes.each do |key, value|
          name = key.is_a?(Symbol) ? Entity.attribute_name(key) : key.to_s
          if OUTER_ATTRIBUTES.include?(name) || Entity.component?(name) || Entity.waiting_component?(name)
            outer[key] = value
          else
            options[key] = value
          end
        end
        [outer, options]
      end
    end

    OUTER_ATTRIBUTES = ["id", "class", "mixin"]

    # parent is anything Entity.create takes (an Entity, a JS element, a
    # selector or nil for a-scene). children is what children places here:
    # the block given to the part being built, and the children of the
    # Builder that called it.
    def initialize(parent = nil, children = nil)
      @parent = parent
      @created = []
      @children = children
    end

    # The elements made directly in this Builder's block.
    attr_reader :created

    # Creates any tag, for those not in the list:
    #   tag "a-ocean", depth: 50
    # Symbols before the attributes attach components with their defaults,
    # as in Entity.create (entity :swim, gltf_model: "#shark").
    def tag(name, *components, **attributes, &block)
      entity = Entity.create(name, *components, parent: @parent, **attributes)
      @created << entity
      Builder.new(entity, @children).instance_eval(&block) if block
      entity
    end

    # Inside a part's definition: makes, here, what the block given to the
    # part makes (nothing when it had none). Returns those elements.
    def children
      return [] if @children.nil?

      block, outer = @children
      return [] if block.nil?

      builder = Builder.new(@parent, outer)
      builder.instance_eval(&block)
      @created.concat(builder.created)
      builder.created
    end

    private

    def make_part(definition, components, attributes, block)
      outer, options = Builder.split_part_attributes(attributes)
      entity = Entity.create("a-entity", *components, parent: @parent, **outer)
      begin
        Builder.new(entity, [block, @children]).instance_exec(**options, &definition)
      rescue => e
        # An unknown keyword (or any error) leaves no half-made part.
        entity.js.remove
        raise e
      end
      @created << entity
      entity
    end
  end

  # Defines a part: a method for AFrame.scene blocks that makes an
  # a-entity and runs the block in it, as a Builder. Keywords that are
  # component names (position:, rotation:, ...) and id / class / mixin go
  # on that a-entity; the others go to the block. children places the
  # block given where the part is used.
  #
  #   AFrame.part :lamp do |height: 1, color: "#fff"|
  #     cylinder height: height, radius: 0.05, anchor: :bottom
  #     entity position: [0, height, 0] do
  #       sphere radius: 0.15, color: color
  #       children
  #     end
  #   end
  #
  #   AFrame.scene do
  #     lamp position: [1, 0, -3], height: 1.5
  #     lamp(position: [-1, 0, -3]) { box scale: 0.2, position: [0, 0.3, 0] }
  #   end
  #
  # A part can use itself (a trunk made of segments) and other parts.
  def self.part(name, &definition)
    raise ArgumentError, "part needs a block" if definition.nil?

    Builder.define_part(name, definition)
  end

  # Runs the block in a Builder and returns the elements it made at the
  # top level. parent: is where they go (a-scene when omitted).
  # The block is run with instance_eval, so local variables from outside
  # are visible but methods of the outer self are not.
  def self.scene(parent: nil, &block)
    Builder.define_tags
    builder = Builder.new(parent)
    builder.instance_eval(&block) if block
    builder.created
  end
end
