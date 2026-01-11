//
//  Renderer.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import MetalKit
import MetalPerformanceShaders

class Renderer: MTKViewDelegate {
  struct Camera {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>
    var fovYRadians: Float
    var aspect: Float
  }

  let device: MTLDevice
  let maxFramesInFlight = 1
  var semaphore: DispatchSemaphore!
  var description: String
  var hash: Int
  var superclass: AnyClass?
  var vertexBufferOriginal: MTLBuffer
  var scene_displaced: SceneContainer
  var pipeline: RenderingPipeline
  
  var resolution: UInt

  var camera: Camera
  var cameraBuffer: MTLBuffer

  init?(metalKitView: MTKView) {
    metalKitView.colorPixelFormat = .rgba16Float
    metalKitView.sampleCount = 1
    metalKitView.drawableSize = metalKitView.frame.size
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
    
    resolution = 1200
    let mesh = MeshFactory.makeExplicitPlane(allocator: MTKMeshBufferAllocator(device: device),
                                             device: device,
                                             segmentsX: Int(resolution),
                                             segmentsY: Int(resolution))
    scene_displaced = BasicScene(mesh: mesh)

    pipeline = RenderingPipeline(device: self.device, view: metalKitView, scene: scene_displaced)
    pipeline.buildVertexPipeline(initial_buffer: (scene_displaced.mesh.vertexBuffers.first!.buffer))
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
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let aspect = Float(size.width / max(size.height, 1))
    camera.aspect = aspect
    memcpy(cameraBuffer.contents(), &camera, MemoryLayout<Camera>.stride)
  }
  
  func draw(in view: MTKView) {
    semaphore.wait()
    guard let commandBuffer = pipeline.queue.makeCommandBuffer()
    else { fatalError() }
    
    
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

    // Calculate Dispatch Size (1D Grid for vertices)
    // Unlike your ray tracer which uses W x H, this uses a linear array of vertices.
    let threadGroupSize = MTLSize(width: 64, height: 1, depth: 1)
    let threadGroups = MTLSize(width: (scene_displaced.mesh.vertexCount + 63) / 64, height: 1, depth: 1)

    displaceEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    displaceEncoder.endEncoding()
    
    
    guard let normalEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    normalEncoder.label = "Vertex Normal refine Pass"
    normalEncoder.setComputePipelineState(pipeline.normalPipelineState!)

    // Bind Buffers according to your shader signature:
    normalEncoder.setBuffer((scene_displaced.mesh.vertexBuffers.first!.buffer), offset: 0, index: 0)
    normalEncoder.setBytes(&vCount,
                             length: MemoryLayout<UInt32>.size,
                             index: 1)
    var resolution_ = UInt32(resolution)
    normalEncoder.setBytes(&resolution_,
                             length: MemoryLayout<UInt32>.size,
                             index: 2)
    normalEncoder.setBytes(&resolution_,
                             length: MemoryLayout<UInt32>.size,
                             index: 3)

    normalEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    normalEncoder.endEncoding()
    
    // ... [Step 2: Refit Acceleration Structure] ...
    pipeline.accelerationStructureBuilder.refit(commandBuffer: commandBuffer)
    
    
    // ... [Step 3: Ray Tracing Encoder] ...
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    computeEncoder.label = "RT Pass"
    
    computeEncoder.setComputePipelineState(pipeline.rayGenPipelineState)
    computeEncoder.setTexture(view.currentDrawable?.texture, index: 0)
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

