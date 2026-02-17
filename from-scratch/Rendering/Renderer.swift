//
//  Renderer.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import MetalKit
import MetalPerformanceShaders
import QuartzCore
import SwiftUI

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
  @Binding var meshSize: Float
  var shaderReloads: Int = 0
  
  var raytracingUniforms: RayTracingUniforms
  var raytracingUniformsBuffer: MTLBuffer
  
  var heightMapUniforms: HeightMapUniforms
  
  var onStats: ((Stats) -> Void)?
  
  private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()
  
  // Orbit parameters controlled from SwiftUI gestures
  private var orbitYaw: Double = 0.0
  private var orbitPitch: Double = -0.5
  private var orbitDistance: Double = 3.0
  
  init?(metalKitView: MTKView,
        meshResolution: UInt,
        textureResolution: UInt,
        meshSize: Binding<Float>,
        heightMapUniforms: HeightMapUniforms) {
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
    let eye = SIMD3<Float>(0, 0, 0)
    let lookAt = SIMD3<Float>(0, 0, 0)
    let worldUp = SIMD3<Float>(0, 1, 0)
    let forward = simd_normalize(lookAt - eye)
    let right = simd_normalize(simd_cross(forward, worldUp))
    let up = simd_normalize(simd_cross(right, forward))
    let fovYRadians: Float = 60.0 * .pi / 180.0
    let cam = CameraProperties(position: eye, forward: forward, right: right, up: up, fovYRadians: fovYRadians, aspect: aspect)
    raytracingUniforms = .init(camera: cam, meshSize: 0.0, overlayDebug: Shading)
    raytracingUniformsBuffer = device.makeBuffer(length: MemoryLayout<RayTracingUniforms>.stride, options: .storageModeShared)!
    memcpy(raytracingUniformsBuffer.contents(), &raytracingUniforms, MemoryLayout<RayTracingUniforms>.stride)
    
    semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
    hash = 100
    description = "Renderer"
    
    self.meshResolution = meshResolution
    self.textureResolution = textureResolution
    self._meshSize = meshSize
    let mesh = MeshFactory.makeExplicitPlane(allocator: MTKMeshBufferAllocator(device: device),
                                             device: device,
                                             width: 1.0,
                                             height: 1.0,
                                             segmentsX: Int(meshResolution),
                                             segmentsY: Int(meshResolution))
    scene_displaced = BasicScene(mesh: mesh)
    self.heightMapUniforms = .init(deltaX: meshSize.wrappedValue/Float(meshResolution),
                                   deltaY: meshSize.wrappedValue/Float(meshResolution),
                                   dt: 0.012,
                                   l_pipe: 0.2,
                                   gravity: 9.81,
                                   A_pipe: 1.0,
                                   Kc: 0.5,
                                   Ks: 0.1,
                                   Kd: 0.1,
                                   Ke: 0.015,
                                   talusScale: 2.0,
                                   thermalStrength: 0.5,
                                   advectMultiplier: 1.0,
                                   velAdvMag: 0.1,
                                   velMult: 0.5)
    heightField = HeightField(device: device,
                              textureResolution: Int(textureResolution),
                              library: device.makeDefaultLibrary(),
                              simulationUniforms: self.heightMapUniforms)
    
    let vD: MTLVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)!
    pipeline = RenderingPipeline(device: self.device, view: metalKitView, scene: scene_displaced, vD: vD)
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
  
  func updateErosionUniform(_ data: HeightMapUniforms) {
    heightField.updateErosionUniformBuffer(data)
  }
  
  func setSimulationPaused(_ paused: Bool) {
    heightField.setPaused(paused)
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
    var forward = simd_normalize(target - raytracingUniforms.camera.position)
    // If forward is almost parallel to worldUp, choose a different up to avoid degeneracy
    let parallelThreshold: Float = 0.99
    var upCandidate = worldUp
    if abs(simd_dot(forward, worldUp)) > parallelThreshold {
      upCandidate = SIMD3<Float>(0, 0, 1)
    }
    let right = simd_normalize(simd_cross(forward, upCandidate))
    let up = simd_normalize(simd_cross(right, forward))
    forward = simd_normalize(forward)
    raytracingUniforms.camera.forward = forward
    raytracingUniforms.camera.right = right
    raytracingUniforms.camera.up = up
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let aspect = Float(size.width / max(size.height, 1))
    raytracingUniforms.camera.aspect = aspect
    memcpy(raytracingUniformsBuffer.contents(), &raytracingUniforms, MemoryLayout<RayTracingUniforms>.stride)
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
  
  func raytracing(in view: MTKView) {
    let now = CACurrentMediaTime()
    let delta = now - lastFrameTimestamp
    lastFrameTimestamp = now
    
    semaphore.wait()
    guard let commandBuffer = pipeline.queue.makeCommandBuffer()
    else { fatalError() }
    
    let currentTime: Float = Float(dateStart.timeIntervalSinceNow)
    
    // --- STEP 0: Displacement texture update ---
    heightField.executeStep(commandBuffer: commandBuffer, currentTime: currentTime)
    
    // --- STEP 1: Displacement Encoder ---
    guard let displaceEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    displaceEncoder.label = "Vertex Displacement Pass"
    displaceEncoder.setComputePipelineState(pipeline.displacePipelineState!)
    
    // Bind Buffers according to your shader signature:
    displaceEncoder.setBuffer(vertexBufferOriginal, offset: 0, index: 0)
    displaceEncoder.setBuffer((scene_displaced.mesh.vertexBuffers.first!.buffer), offset: 0, index: 1)
    var vCount = UInt32(scene_displaced.mesh.vertexCount)
    displaceEncoder.setBytes(&vCount,
                             length: MemoryLayout<UInt32>.size,
                             index: 2)
    displaceEncoder.setBytes(&meshSize,
                             length: MemoryLayout<Float>.size,
                             index: 3)
    displaceEncoder.setTexture(heightField.textures.terrain, index: 0)
    
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
    computeEncoder.setTexture(heightField.textures.normal, index: 1)
    computeEncoder.setTexture(heightField.textures.terrain, index: 2)
    computeEncoder.setBuffer(scene_displaced.mesh.vertexBuffers.first!.buffer, offset: 0, index: 1)
    computeEncoder.setBuffer(scene_displaced.mesh.submeshes.first!.indexBuffer.buffer, offset: 0, index: 2)
    computeEncoder.setBuffer(raytracingUniformsBuffer, offset: 0, index: 3)
    
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
  
  func raster(in view: MTKView) {
    let now = CACurrentMediaTime()
    let delta = now - lastFrameTimestamp
    lastFrameTimestamp = now
    
    semaphore.wait()
    guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
    
    guard let commandBuffer = pipeline.queue.makeCommandBuffer() else { return }
    
    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
    
    renderEncoder.setRenderPipelineState(pipeline.rasterPipelineState)
    renderEncoder.setVertexBuffer(vertexBufferOriginal, offset: 0, index: 0)
    renderEncoder.setVertexBytes(&meshSize,
                                 length: MemoryLayout<Float>.size,
                                 index: 1)
    renderEncoder.setVertexTexture(heightField.textures.terrain, index: 0)
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Int(meshResolution * meshResolution))
    
    renderEncoder.endEncoding()
    
    guard let drawable = view.currentDrawable else { fatalError() }
    commandBuffer.present(drawable)
    commandBuffer.commit()
    
    emitStats(for: view, delta: delta)
    
    commandBuffer.addCompletedHandler { cb in
      self.semaphore.signal()
    }
  }
  
  func draw(in view: MTKView) {
    raster(in: view)
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
    orbitDistance = max(0.1, min(300.0, distance))
    
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
    raytracingUniforms.camera.position = target + offset
    
    updateCameraBasis(lookAt: target)
    memcpy(raytracingUniformsBuffer.contents(), &raytracingUniforms, MemoryLayout<RayTracingUniforms>.stride)
  }
}
