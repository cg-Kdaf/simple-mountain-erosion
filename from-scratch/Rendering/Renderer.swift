//
//  Renderer.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import MetalKit
import MetalPerformanceShaders
import QuartzCore

class Renderer: MTKViewDelegate {
  struct Stats {
    var fps: Double
    var frameTimeMs: Double
    var meshResolution: UInt
    var textureResolution: UInt
    var drawableSize: CGSize
    var deviceName: String
    var shaderReloads: Int
  }

  struct Camera {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>
    var fovYRadians: Float
    var aspect: Float
  }

  let device: MTLDevice
  let dateStart = NSDate()
  let maxFramesInFlight = 1
  var semaphore: DispatchSemaphore!
  var description: String
  var hash: Int
  var superclass: AnyClass?
  var vertexBufferOriginal: MTLBuffer
  var heightField: HeightField
  var scene_displaced: SceneContainer
  var pipeline: RenderingPipeline
  
  var meshResolution: UInt
  var textureResolution: UInt
  var shaderReloads: Int = 0

  var camera: Camera
  var cameraBuffer: MTLBuffer
  var onStats: ((Stats) -> Void)?

  private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()

  // Orbit parameters controlled from SwiftUI gestures
  private var orbitYaw: Double = 0.0
  private var orbitPitch: Double = -0.5
  private var orbitDistance: Double = 3.0

  init?(metalKitView: MTKView) {
    metalKitView.colorPixelFormat = .rgba16Float
    metalKitView.sampleCount = 1
    metalKitView.drawableSize = metalKitView.frame.size
    metalKitView.layoutSubtreeIfNeeded()
    metalKitView.framebufferOnly = false
    
    // Ensure the MTKView has a device
    if metalKitView.device == nil {
      metalKitView.device = MTLCreateSystemDefaultDevice()
    }
    guard let device_ = metalKitView.device else {
      return nil
    }
    device = device_

    let size = metalKitView.drawableSize
    let aspect = Float(size.width / max(size.height, 1))
    let eye = SIMD3<Float>(1.0, 1.0, 1.5)
    let lookAt = SIMD3<Float>(0, 0, 0)
    let worldUp = SIMD3<Float>(0, 1, 0)
    let forward = simd_normalize(lookAt - eye)
    let right = simd_normalize(simd_cross(forward, worldUp))
    let up = simd_normalize(simd_cross(right, forward))
    let fovYRadians: Float = 60.0 * .pi / 180.0
    let cam = Camera(position: eye, forward: forward, right: right, up: up, fovYRadians: fovYRadians, aspect: aspect)
    camera = cam
    guard let camBuf = device.makeBuffer(length: MemoryLayout<Camera>.stride, options: .storageModeShared) else { return nil }
    cameraBuffer = camBuf
    memcpy(cameraBuffer.contents(), &camera, MemoryLayout<Camera>.stride)

    semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
    hash = 100
    description = "Renderer"
    
    meshResolution = 1200
    textureResolution = 1200
    let mesh = MeshFactory.makeExplicitPlane(allocator: MTKMeshBufferAllocator(device: device),
                                             device: device,
                                             segmentsX: Int(meshResolution),
                                             segmentsY: Int(meshResolution))
    scene_displaced = BasicScene(mesh: mesh)
    heightField = HeightField(device: device, textureResolution: Int(textureResolution), library: device.makeDefaultLibrary())

    pipeline = RenderingPipeline(device: self.device, view: metalKitView, scene: scene_displaced)
    pipeline.buildVertexPipeline(initial_buffer: (scene_displaced.mesh.vertexBuffers.first!.buffer), heightField: heightField)
    vertexBufferOriginal = device.makeBuffer(length: scene_displaced.mesh.vertexBuffers[0].length,
                                             options: .storageModePrivate)!
    do { // Copy the buffer to always have the original
      guard let commandBuffer = pipeline.queue.makeCommandBuffer(),
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
      else { return }
      
      blitEncoder.label = "One-off Buffer Copy"
      blitEncoder.copy(from: scene_displaced.mesh.vertexBuffers[0].buffer, sourceOffset: 0,
                       to: vertexBufferOriginal, destinationOffset: 0,
                       size: scene_displaced.mesh.vertexBuffers[0].length)
      blitEncoder.endEncoding()
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
    }
  }

  private func emitStats(for view: MTKView, delta: CFTimeInterval) {
    let fps = delta > 0 ? 1.0 / delta : 0.0
    let stats = Stats(
      fps: fps,
      frameTimeMs: delta * 1000.0,
      meshResolution: meshResolution,
      textureResolution: textureResolution,
      drawableSize: view.drawableSize,
      deviceName: device.name,
      shaderReloads: shaderReloads
    )
    DispatchQueue.main.async {
      self.onStats?(stats)
    }
  }
  
  private func updateCameraBasis(lookAt target: SIMD3<Float>) {
    let worldUp = SIMD3<Float>(0, 1, 0)
    var forward = simd_normalize(target - camera.position)
    // If forward is almost parallel to worldUp, choose a different up to avoid degeneracy
    let parallelThreshold: Float = 0.99
    var upCandidate = worldUp
    if abs(simd_dot(forward, worldUp)) > parallelThreshold {
      upCandidate = SIMD3<Float>(0, 0, 1)
    }
    let right = simd_normalize(simd_cross(forward, upCandidate))
    let up = simd_normalize(simd_cross(right, forward))
    forward = simd_normalize(forward)
    camera.forward = forward
    camera.right = right
    camera.up = up
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let aspect = Float(size.width / max(size.height, 1))
    camera.aspect = aspect
    memcpy(cameraBuffer.contents(), &camera, MemoryLayout<Camera>.stride)
  }
  
  func updateResolutions(mesh newMeshResolution: UInt, texture newTextureResolution: UInt) {
    let clampedMesh = max(UInt(8), min(UInt(4096), newMeshResolution))
    let clampedTexture = max(UInt(8), min(UInt(4096), newTextureResolution))
    let meshChanged = clampedMesh != meshResolution
    let textureChanged = clampedTexture != textureResolution
    guard meshChanged || textureChanged else { return }

    semaphore.wait()

    if meshChanged {
      meshResolution = clampedMesh
      let mesh = MeshFactory.makeExplicitPlane(
        allocator: MTKMeshBufferAllocator(device: device),
        device: device,
        segmentsX: Int(clampedMesh),
        segmentsY: Int(clampedMesh))
      scene_displaced = BasicScene(mesh: mesh)
      pipeline.reloadShaders(scene: scene_displaced, heightField: heightField)

      vertexBufferOriginal = device.makeBuffer(length: scene_displaced.mesh.vertexBuffers[0].length,
                                               options: .storageModePrivate)!
      if let commandBuffer = pipeline.queue.makeCommandBuffer(),
         let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
        blitEncoder.copy(from: scene_displaced.mesh.vertexBuffers[0].buffer, sourceOffset: 0,
                         to: vertexBufferOriginal, destinationOffset: 0,
                         size: scene_displaced.mesh.vertexBuffers[0].length)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
      }
    }

    if textureChanged {
      textureResolution = clampedTexture
      heightField.resize(to: Int(clampedTexture))
    }

    semaphore.signal()
  }
  
  func reloadShaders() {
    semaphore.wait()
    pipeline.reloadShaders(scene: scene_displaced, heightField: heightField)
    shaderReloads += 1
    semaphore.signal()
  }
  
  func draw(in view: MTKView) {
    let now = CACurrentMediaTime()
    let delta = now - lastFrameTimestamp
    lastFrameTimestamp = now

    semaphore.wait()
    guard let commandBuffer = pipeline.queue.makeCommandBuffer()
    else { fatalError() }

    var currentTime: Float = Float(dateStart.timeIntervalSinceNow)
    
    // --- STEP 0: Displacement texture update ---
    guard let displaceTextureEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    displaceTextureEncoder.label = "Displace Texture Pass"
    displaceTextureEncoder.setComputePipelineState(heightField.displaceTexturePipelineState!)
    displaceTextureEncoder.setTexture(heightField.displacementTexture, index: 0)
    displaceTextureEncoder.setTexture(heightField.normalTexture, index: 1)
    displaceTextureEncoder.setBytes(&currentTime,
                                    length: MemoryLayout<Float>.size,
                                    index: 0)

    let w_texture = heightField.displaceTexturePipelineState!.threadExecutionWidth
    let h_texture = heightField.displaceTexturePipelineState!.maxTotalThreadsPerThreadgroup / w_texture
    let threadsPerThreadgroup = MTLSizeMake(w_texture, h_texture, 1)
    let threadsPerGrid = MTLSize(width: (heightField.displacementTexture.width + w_texture - 1) / w_texture,
                   height: (heightField.displacementTexture.height + h_texture - 1) / h_texture,
                   depth: 1)

    displaceTextureEncoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    displaceTextureEncoder.endEncoding()
    
    // --- STEP 1: Displacement Encoder ---
    guard let displaceEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    displaceEncoder.label = "Vertex Displacement Pass"
    displaceEncoder.setComputePipelineState(heightField.displacePipelineState!)

    // Bind Buffers according to your shader signature:
    displaceEncoder.setBuffer(vertexBufferOriginal, offset: 0, index: 0)
    displaceEncoder.setBuffer((scene_displaced.mesh.vertexBuffers.first!.buffer), offset: 0, index: 1)
    var vCount = UInt32(scene_displaced.mesh.vertexCount)
    displaceEncoder.setBytes(&vCount,
                             length: MemoryLayout<UInt32>.size,
                             index: 2)
    displaceEncoder.setTexture(heightField.displacementTexture, index: 0)
    
    // Calculate Dispatch Size (1D Grid for vertices)
    // Unlike your ray tracer which uses W x H, this uses a linear array of vertices.
    let threadGroupSize = MTLSize(width: 64, height: 1, depth: 1)
    let threadGroups = MTLSize(width: (scene_displaced.mesh.vertexCount + 63) / 64, height: 1, depth: 1)

    displaceEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    displaceEncoder.endEncoding()

    // ... [Step 2: Refit Acceleration Structure] ...
    pipeline.accelerationStructureBuilder.refit(commandBuffer: commandBuffer)
    
    // ... [Step 3: Ray Tracing Encoder] ...
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    computeEncoder.label = "RT Pass"
    
    computeEncoder.setComputePipelineState(pipeline.rayGenPipelineState)
    computeEncoder.setTexture(view.currentDrawable?.texture, index: 0)
    computeEncoder.setTexture(heightField.normalTexture, index: 1)
    computeEncoder.setBuffer(scene_displaced.mesh.vertexBuffers.first!.buffer, offset: 0, index: 1)
    computeEncoder.setBuffer(scene_displaced.mesh.submeshes.first!.indexBuffer.buffer, offset: 0, index: 2)
    computeEncoder.setBuffer(cameraBuffer, offset: 0, index: 3)

    computeEncoder.useResource(pipeline.accelerationStructureBuilder.accelerationStructure, usage: .read)
    computeEncoder.useResource(cameraBuffer, usage: .read)
    computeEncoder.setAccelerationStructure(pipeline.accelerationStructureBuilder.accelerationStructure, bufferIndex: 0)
    let w = Int(view.drawableSize.width)
    let h = Int(view.drawableSize.height)
    let tg = MTLSize(width: 8, height: 8, depth: 1)
    let grid = MTLSize(width: (w + 7)/8 * 8, height: (h + 7)/8 * 8, depth: 1)
    computeEncoder.dispatchThreads(grid, threadsPerThreadgroup: tg)
    computeEncoder.endEncoding()

    
    guard let drawable = view.currentDrawable else { fatalError() }

    commandBuffer.present(drawable)
    commandBuffer.commit()

    emitStats(for: view, delta: delta)
    
    commandBuffer.addCompletedHandler { cb in
      self.semaphore.signal()
    }
  }
  
  func isEqual(_ object: Any?) -> Bool {
    return true
  }
  
  func `self`() -> Self {
    return self
  }
  
  func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! {
    return nil
  }
  
  func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! {
    return nil
  }
  
  func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! {
    return nil
  }
  
  func isProxy() -> Bool {
    return true
  }
  
  func isKind(of aClass: AnyClass) -> Bool {
    return true
  }
  
  func isMember(of aClass: AnyClass) -> Bool {
    return true
  }
  
  func conforms(to aProtocol: Protocol) -> Bool {
    return true
  }
  
  func responds(to aSelector: Selector!) -> Bool {
    return true
  }
}

extension Renderer: OrbitControllable {
    func setOrbit(yaw: Double, pitch: Double, distance: Double) {
        // Cache values with safety clamps
        orbitYaw = yaw
        orbitPitch = max(-1.5, min(1.5, pitch))
        orbitDistance = max(0.1, min(200.0, distance))

        // Target the origin (0,0,0). Compute spherical coordinates (yaw around Y, pitch around X).
        let target = SIMD3<Float>(0, 0, 0)
        let cosPitch = cos(orbitPitch)
        let sinPitch = sin(orbitPitch)
        let cosYaw = cos(orbitYaw)
        let sinYaw = sin(orbitYaw)
        // Yaw = 0 looks toward -Z for a typical right-handed view
        let offset = SIMD3<Float>(
          Float(cosPitch * sinYaw * orbitDistance),
          Float(sinPitch * orbitDistance),
          Float(-cosPitch * cosYaw * orbitDistance)
        )
        camera.position = target + offset

        updateCameraBasis(lookAt: target)
        memcpy(cameraBuffer.contents(), &camera, MemoryLayout<Camera>.stride)
    }
}
