import ARKit
import RealityKit
import simd
import UIKit

/// Owns the AR view, placement, gestures, and the bridge into the video recorder.
final class SceneController: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
    weak var model: AppModel?
    private(set) var isRecording = false

    private var arView: ARView?
    private var coaching: ARCoachingOverlayView?
    private var coachingActive = false
    private var reticleAnchor: AnchorEntity?
    private var instances: [UUID: Entity] = [:]
    private var anchors: [UUID: AnchorEntity] = [:]
    private var playbacks: [UUID: [AnimationPlaybackController]] = [:]
    private var frameCount = 0
    private var pausedForScan = false
    private let recorder = FrameRecorder()

    func attach(_ view: ARView) {
        if arView === view { return }
        arView = view
        PlacedObjectComponent.registerIfNeeded()
        view.automaticallyConfigureSession = false
        view.environment.lighting.intensityExponent = 1
        view.renderOptions.remove(.disableGroundingShadows)
        view.renderOptions.remove(.disablePersonOcclusion)
        view.renderOptions.remove(.disableAREnvironmentLighting)
        applySceneUnderstanding()

        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.delegate = self
        coaching.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: view.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.coaching = coaching

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)

        installReticle(in: view)
        view.session.delegate = self
        view.session.delegateQueue = .main
        recorder.onRuntimeFailure = { [weak self] message in
            Task { @MainActor in
                await self?.model?.handleRecordingFailure(message)
            }
        }
        do {
            try recorder.prepareIfNeeded()
        } catch {
            // The record button reports this if preparation is still failing later.
        }
        restartSession(resettingAnchors: true)
    }

    func pauseForScan() {
        pausedForScan = true
        arView?.session.pause()
    }

    func resumeAfterScan(clearScene: Bool) {
        guard pausedForScan else { return }
        pausedForScan = false
        if clearScene {
            clearPlaced()
            restartSession(resettingAnchors: true)
        } else if let arView {
            let configuration = model?.capabilities.makeConfiguration() ?? DeviceCapabilities.current.makeConfiguration()
            arView.session.run(configuration)
        }
    }

    func clearPlaced() {
        for id in Array(instances.keys) {
            removeInstance(id)
        }
        if let model {
            model.placed.removeAll()
            model.selectedInstanceID = nil
        }
        refreshSelectionRings()
    }

    func resetTracking() {
        clearPlaced()
        restartSession(resettingAnchors: true)
    }

    func deleteSelected() {
        guard let model, let id = model.selectedInstanceID else { return }
        removeInstance(id)
        model.placed.removeAll { $0.id == id }
        model.selectedInstanceID = nil
        refreshSelectionRings()
        Haptics.tick()
    }

    func toggleAnimation() {
        guard let model, let id = model.selectedInstanceID, let controllers = playbacks[id], !controllers.isEmpty else { return }
        guard let index = model.placed.firstIndex(where: { $0.id == id }) else { return }
        if model.placed[index].isPlaying {
            controllers.forEach { $0.pause() }
            model.placed[index].isPlaying = false
        } else {
            controllers.forEach { $0.resume() }
            model.placed[index].isPlaying = true
        }
    }

    func duplicateSelected() {
        guard let model, let id = model.selectedInstanceID, let wrapper = instances[id] else { return }
        guard let info = wrapper.components[PlacedObjectComponent.self] else { return }
        let world = wrapper.position(relativeTo: nil)
        Task { @MainActor in
            await self.place(assetID: info.assetID, worldPosition: world + SIMD3<Float>(0.14, 0, 0.05))
        }
    }

    func startRecording(includeAudio: Bool) throws {
        try recorder.begin(includeAudio: includeAudio)
        isRecording = true
        coaching?.setActive(false, animated: true)
        refreshSelectionRings()
        arView?.renderCallbacks.postProcess = { [weak self] context in
            self?.recorder.consume(context)
        }
    }

    func stopRecording() async throws -> URL {
        isRecording = false
        refreshSelectionRings()
        arView?.renderCallbacks.postProcess = nil
        return try await recorder.finish()
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            model?.trackingReady = true
            model?.trackingMessage = nil
        case .notAvailable:
            model?.trackingReady = false
            model?.trackingMessage = "AR isn't available right now."
        case .limited(let reason):
            model?.trackingReady = true
            model?.trackingMessage = Self.trackingMessage(reason)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        guard frameCount % 3 == 0 else { return }
        let point = arView.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
        applyReticle(show: shouldShowReticle, hit: point.flatMap { raycast(at: $0) })
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.model?.showNotice("AR stopped. \(error.localizedDescription)")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            if self.model?.isRecording == true {
                await self.model?.stopRecording()
            }
            self.model?.showNotice("The camera was interrupted.")
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.restartSession(resettingAnchors: false)
        }
    }

    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        coachingActive = true
        reticleAnchor?.isEnabled = false
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        coachingActive = false
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let arView, model?.isBusy != true else { return }
        let point = gesture.location(in: arView)
        if let hit = arView.entity(at: point), let wrapper = hit.placedWrapper(),
           let info = wrapper.components[PlacedObjectComponent.self] {
            select(info.instanceID)
            return
        }
        guard let assetID = model?.armedAssetID else {
            select(nil)
            return
        }
        Task { @MainActor in
            await self.place(assetID: assetID, screenPoint: point)
        }
    }

    @objc private func entityGesture(_ gesture: UIGestureRecognizer) {
        guard let entityGesture = gesture as? EntityGestureRecognizer,
              let entity = entityGesture.entity?.placedWrapper(),
              let info = entity.components[PlacedObjectComponent.self] else { return }
        if gesture.state == .began {
            select(info.instanceID)
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            let scale = entity.scale
            entity.scale = SIMD3(
                min(max(scale.x, 0.05), 8),
                min(max(scale.y, 0.05), 8),
                min(max(scale.z, 0.05), 8)
            )
        }
    }

    @MainActor
    private func place(assetID: UUID, screenPoint: CGPoint) async {
        guard let hit = raycast(at: screenPoint) else {
            model?.showNotice("Point at a floor or wall, then tap again.")
            return
        }
        let position = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
        let normal = SIMD3<Float>(hit.worldTransform.columns.1.x, hit.worldTransform.columns.1.y, hit.worldTransform.columns.1.z)
        await place(assetID: assetID, worldPosition: position, normal: normal)
    }

    @MainActor
    private func place(assetID: UUID, worldPosition: SIMD3<Float>, normal: SIMD3<Float> = SIMD3(0, 1, 0)) async {
        guard let model, let root = model.library.root, let item = model.library.items.first(where: { $0.id == assetID }) else { return }
        guard model.isBusy == false else { return }
        model.isBusy = true
        model.busyText = "Placing \(item.name)…"
        defer { model.isBusy = false }
        do {
            let visual = try await ModelLoader.loadVisual(for: item, libraryRoot: root)
            let placed = try install(visual: visual, item: item, at: worldPosition, normal: normal)
            model.placed.append(placed)
            select(placed.id)
            Haptics.place()
        } catch {
            model.showNotice((error as? LocalizedError)?.errorDescription ?? "That object couldn't be placed.")
        }
    }

    private func install(visual: Entity, item: AssetItem, at position: SIMD3<Float>, normal: SIMD3<Float>) throws -> PlacedInstance {
        guard let arView else {
            throw UserFacingError(message: "The camera isn't ready yet.")
        }
        let holder = Entity()
        holder.name = "holder"
        holder.addChild(visual)
        let bounds = visual.visualBounds(relativeTo: holder)
        let extents = SIMD3<Float>(
            max(bounds.extents.x, 0.02),
            max(bounds.extents.y, 0.02),
            max(bounds.extents.z, 0.02)
        )
        holder.position = SIMD3(-bounds.center.x, -bounds.min.y, -bounds.center.z)

        let wrapper = ModelEntity()
        wrapper.name = item.name
        wrapper.addChild(holder)
        let collisionCenter = holder.position + bounds.center
        let shape = ShapeResource.generateBox(size: extents).offsetBy(translation: collisionCenter)
        wrapper.components.set(CollisionComponent(shapes: [shape]))

        if let ringMesh = try? ProceduralMesh.torus(
            meanRadius: max(extents.x, extents.z) * 0.55,
            tubeRadius: 0.0025,
            sides: 48,
            tubeSides: 10
        ) {
            let ring = ModelEntity(
                mesh: ringMesh,
                materials: [UnlitMaterial(color: UIColor(red: 0.89, green: 0.60, blue: 0.29, alpha: 1))]
            )
            ring.name = "selectionRing"
            ring.position.y = 0.003
            ring.isEnabled = false
            wrapper.addChild(ring)
        }

        let instanceID = UUID()
        let hasAnimation = startAnimations(on: visual, id: instanceID)
        wrapper.components.set(PlacedObjectComponent(
            instanceID: instanceID,
            assetID: item.id,
            title: item.name,
            hasAnimation: hasAnimation
        ))

        var translation = position
        if abs(normal.y) < 0.75, simd_length(normal) > 0.1 {
            translation += simd_normalize(normal) * (max(extents.x, extents.z) * 0.5 + 0.01)
        }
        let yaw = yawFacingCamera(from: translation)
        let anchor = AnchorEntity(world: translation)
        anchor.orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        anchor.addChild(wrapper)
        arView.scene.addAnchor(anchor)
        for recognizer in arView.installGestures([.translation, .rotation, .scale], for: wrapper) {
            recognizer.addTarget(self, action: #selector(entityGesture(_:)))
        }
        instances[instanceID] = wrapper
        anchors[instanceID] = anchor
        return PlacedInstance(id: instanceID, assetID: item.id, title: item.name, hasAnimation: hasAnimation, isPlaying: hasAnimation)
    }

    private func startAnimations(on entity: Entity, id: UUID) -> Bool {
        var controllers: [AnimationPlaybackController] = []
        func walk(_ node: Entity) {
            for animation in node.availableAnimations {
                let looping = animation.repeat(duration: .infinity)
                controllers.append(node.playAnimation(looping, transitionDuration: 0.25, startsPaused: false))
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(entity)
        playbacks[id] = controllers
        return !controllers.isEmpty
    }

    private func select(_ id: UUID?) {
        guard model?.selectedInstanceID != id else {
            refreshSelectionRings()
            return
        }
        model?.selectedInstanceID = id
        if id != nil { Haptics.tick() }
        refreshSelectionRings()
    }

    func refreshSelectionRings() {
        let selected = model?.selectedInstanceID
        for (id, wrapper) in instances {
            let show = !isRecording && id == selected
            wrapper.findEntity(named: "selectionRing")?.isEnabled = show
        }
    }

    private func removeInstance(_ id: UUID) {
        playbacks[id]?.forEach { $0.stop() }
        playbacks[id] = nil
        if let anchor = anchors[id], let arView {
            arView.scene.removeAnchor(anchor)
        }
        anchors[id] = nil
        instances[id] = nil
    }

    private var shouldShowReticle: Bool {
        model?.armedAssetID != nil && !isRecording && model?.isBusy != true && !coachingActive
    }

    private func applyReticle(show: Bool, hit: ARRaycastResult?) {
        guard let reticleAnchor else { return }
        guard show, let hit else {
            reticleAnchor.isEnabled = false
            return
        }
        reticleAnchor.isEnabled = true
        reticleAnchor.transform = Transform(matrix: hit.worldTransform)
    }

    private func installReticle(in view: ARView) {
        guard let mesh = try? ProceduralMesh.torus(meanRadius: 0.075, tubeRadius: 0.0022, sides: 56, tubeSides: 10) else { return }
        let ring = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        ring.position.y = 0.0025
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(ring)
        anchor.isEnabled = false
        view.scene.addAnchor(anchor)
        reticleAnchor = anchor
    }

    private func raycast(at point: CGPoint) -> ARRaycastResult? {
        guard let arView, arView.bounds.width > 1, arView.bounds.contains(point) else { return nil }
        if let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any).first {
            return hit
        }
        return arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first
    }

    private func yawFacingCamera(from position: SIMD3<Float>) -> Float {
        guard let camera = arView?.cameraTransform.translation else { return 0 }
        var direction = camera - position
        direction.y = 0
        guard simd_length(direction) > 0.001 else { return 0 }
        return atan2(direction.x, direction.z)
    }

    private func restartSession(resettingAnchors: Bool) {
        guard let arView else { return }
        guard let model else {
            arView.session.run(DeviceCapabilities.current.makeConfiguration())
            return
        }
        var options: ARSession.RunOptions = [.resetTracking]
        if resettingAnchors { options.insert(.removeExistingAnchors) }
        applySceneUnderstanding()
        arView.session.run(model.capabilities.makeConfiguration(), options: options)
    }

    private func applySceneUnderstanding() {
        guard let arView, let model else { return }
        var options: ARView.Environment.SceneUnderstanding.Options = []
        if model.capabilities.lidarMesh {
            options.insert(.occlusion)
            options.insert(.receivesLighting)
        }
        arView.environment.sceneUnderstanding.options = options
    }

    private static func trackingMessage(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: return "Starting the camera…"
        case .excessiveMotion: return "Move more slowly."
        case .insufficientFeatures: return "Point at a surface with more detail."
        case .relocalizing: return "Finding the room again…"
        @unknown default: return "Tracking is limited."
        }
    }
}
