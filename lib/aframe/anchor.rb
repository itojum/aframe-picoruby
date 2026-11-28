module AFrame
  # The anchor component: moves the shape so one of its ends sits at the
  # element's origin, so rotation turns it around that end and children
  # placed at the origin start from it.
  #
  #   <a-cone height="1" anchor="bottom"></a-cone>
  #   AFrame.scene { box width: 0.8, anchor: :left }
  #
  # (A-Frame's own pivot component is different: it takes a point, works
  # once at init and moves the children too.)
  #
  # Values: bottom / top (y), left / right (x), front / back (z) and
  # center (the default: the shape where A-Frame put it).
  #
  # Only the element's own mesh (object3D "mesh": geometry or a glTF
  # model) moves; children and the element's position keep their meaning.
  # The shift comes from the mesh's bounding box, and is worked out again
  # when the geometry changes or a model loads.
  class Anchor < Component
    register
    schema type: :string, default: "center",
           oneOf: ["center", "bottom", "top", "left", "right", "front", "back"]

    # Works out the box of mesh (and its children) in the element's space
    # and moves mesh so that the chosen side is at the origin. With no
    # mesh yet, it waits for one and returns false.
    SOURCE = <<~JS
      window.__aframe_anchor = (el, side) => {
        const mesh = el.getObject3D("mesh");
        if (!mesh) {
          // Before the element plays (when the on handlers connect), so
          // wait here for the mesh, then use the value at that time.
          if (!el.__aframe_anchorWaiting) {
            el.__aframe_anchorWaiting = true;
            const wait = (event) => {
              if (event.detail.type !== "mesh") return;
              el.removeEventListener("object3dset", wait);
              el.__aframe_anchorWaiting = false;
              const anchor = el.components.anchor;
              if (anchor) window.__aframe_anchor(el, anchor.data);
            };
            el.addEventListener("object3dset", wait);
          }
          return false;
        }
        // The mesh's own position (a model may have one) is kept and the
        // shift is added to it; a new mesh gets a new base.
        if (el.__aframe_anchorMesh !== mesh) {
          el.__aframe_anchorMesh = mesh;
          el.__aframe_anchorBase = mesh.position.clone();
        }
        mesh.position.copy(el.__aframe_anchorBase);
        if (side === "center") return true;
        // The box in the element's space (mesh.position's space), so the
        // mesh's own rotation and scale count.
        el.object3D.updateMatrixWorld(true);
        const toEl = new THREE.Matrix4().copy(el.object3D.matrixWorld).invert();
        const box = new THREE.Box3();
        const part = new THREE.Box3();
        const matrix = new THREE.Matrix4();
        mesh.traverse((o) => {
          if (!o.geometry) return;
          if (!o.geometry.boundingBox) o.geometry.computeBoundingBox();
          matrix.multiplyMatrices(toEl, o.matrixWorld);
          box.union(part.copy(o.geometry.boundingBox).applyMatrix4(matrix));
        });
        if (box.isEmpty()) return true;
        const at = { bottom: ["y", box.min.y], top: ["y", box.max.y],
                     left: ["x", box.min.x], right: ["x", box.max.x],
                     back: ["z", box.min.z], front: ["z", box.max.z] }[side];
        if (at) mesh.position[at[0]] -= at[1];
        return true;
      };
    JS

    on(:componentchanged) { |event| apply if event[:detail][:name].to_s == "geometry" }
    on(:object3dset) { |event| apply if event[:detail][:type].to_s == "mesh" }

    def init
      JS.eval(SOURCE) if JS.global[:__aframe_anchor].nil?
    end

    # The mesh may not exist yet (geometry or the model comes later); the
    # JS side then waits for it.
    def update(_old_data)
      apply
    end

    def remove
      JS.global.__aframe_anchor(el.js, "center")
    end

    # The on handlers miss what changed while paused, so work it out again
    # when the element plays.
    def connect_events
      super
      apply
    end

    private

    def apply
      JS.global.__aframe_anchor(el.js, data.to_s)
    end
  end
end
