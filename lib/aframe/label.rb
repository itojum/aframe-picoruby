module AFrame
  # The label component: text (Japanese included) on a rounded plate,
  # drawn with the device's own fonts on a canvas.
  #
  #   <a-entity position="0 2 -2" label="value: 持てるよ; height: 0.3"></a-entity>
  #   AFrame::Entity.create("a-entity", label: { value: "持てるよ", height: 0.3 })
  #
  # A-Frame's text component has no Japanese glyphs in its fonts, so this
  # draws the text on a canvas (kept out of the DOM, no id) and shows it
  # as the element's own mesh, like geometry / material do. The plate's
  # width follows the text, so only height is given. Changing value,
  # color, background or font redraws; changing height only rescales.
  class Label < Component
    register "label"
    schema value: "",
           color: "#ffffff",
           background: "rgba(0, 0, 0, 0.55)",
           font: "bold 96px sans-serif",
           height: 0.3                       # plate height in meters

    # THREE objects are made and freed on the JS side.
    SOURCE = <<~JS
      window.__aframe_labelCreate = (canvas) => {
        const texture = new THREE.CanvasTexture(canvas);
        texture.colorSpace = THREE.SRGBColorSpace;
        const material = new THREE.MeshBasicMaterial({ map: texture, transparent: true });
        return new THREE.Mesh(new THREE.PlaneGeometry(1, 1), material);
      };
      window.__aframe_labelDispose = (mesh) => {
        mesh.material.map.dispose();
        mesh.material.dispose();
        mesh.geometry.dispose();
      };
    JS

    REDRAW_KEYS = ["value", "color", "background", "font"]

    def init
      JS.eval(SOURCE) if JS.global[:__aframe_labelCreate].nil?
      @canvas = JS.document.createElement("canvas") # not added to the DOM
      @mesh = JS.global.__aframe_labelCreate(@canvas)
      @aspect = 1
      el.js.setObject3D("mesh", @mesh)
    end

    def update(old_data)
      draw if REDRAW_KEYS.any? { |key| old_data.nil? || old_data[key] != data[key] }
      layout
    end

    def remove
      el.js.removeObject3D("mesh")
      JS.global.__aframe_labelDispose(@mesh)
      @mesh = nil
      @canvas = nil
    end

    private

    # Sizes the canvas to the text, then draws the plate and the text.
    def draw
      text = data.value.to_s
      ctx = @canvas.getContext("2d")
      ctx[:font] = data.font
      # The browser gives the font back in px (40pt => 53.3333px), so the
      # size is read from there, whatever unit was written.
      size = font_size(ctx[:font].to_s)
      pad = size * 0.4
      width = ctx.measureText(text)[:width] + pad * 2
      height = size + pad * 2
      # Setting the size clears the canvas and its state, so draw after.
      @canvas[:width] = width.ceil
      @canvas[:height] = height.ceil
      ctx[:font] = data.font
      ctx[:fillStyle] = data.background
      ctx.beginPath
      ctx.roundRect(0, 0, width, height, height / 2)
      ctx.fill
      ctx[:fillStyle] = data.color
      ctx[:textAlign] = "center"
      ctx[:textBaseline] = "middle"
      ctx.fillText(text, width / 2, height / 2)
      @mesh[:material][:map][:needsUpdate] = true
      @aspect = width / height
    end

    def layout
      @mesh[:scale].set(@aspect * data.height, data.height, 1)
    end

    # The number before "px" in a CSS font ("bold 96px sans-serif" => 96),
    # or 96 when there is none.
    def font_size(font)
      index = font.index("px")
      return 96 if index.nil?

      start = index
      start -= 1 while start > 0 && "0123456789.".include?(font[start - 1])
      digits = font[start, index - start]
      digits.empty? ? 96 : digits.to_f
    end
  end
end
