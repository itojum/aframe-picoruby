require "aframe"

AFrame::Scene.ready
AFrame::CameraLock.install
AFrame::Grabbable.attach_all(".my-grabbable")
AFrame::Scene.run
