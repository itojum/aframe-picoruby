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

          define_method(name.to_sym) do |**attributes, &block|
            tag(tag_name, **attributes, &block)
          end
        end
      end

      def method_name(tag)
        name = tag.start_with?("a-") ? tag[2, tag.size - 2] : tag
        name.tr("-", "_")
      end
    end

    # parent is anything Entity.create takes (an Entity, a JS element, a
    # selector or nil for a-scene).
    def initialize(parent = nil)
      @parent = parent
      @created = []
    end

    # The elements made directly in this Builder's block.
    attr_reader :created

    # Creates any tag, for those not in the list:
    #   tag "a-ocean", depth: 50
    def tag(name, **attributes, &block)
      entity = Entity.create(name, parent: @parent, **attributes)
      @created << entity
      Builder.new(entity).instance_eval(&block) if block
      entity
    end
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
