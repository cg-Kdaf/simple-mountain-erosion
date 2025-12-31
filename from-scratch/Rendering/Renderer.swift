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
  var scene: SceneContainer
  var pipeline: RenderingPipeline

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
    let eye = SIMD3<Float>(1.5, 1.5, 1.5)
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
    
    scene = BasicScene(mesh: MeshFactory.makeBasicPlane(allocator: MTKMeshBufferAllocator(device: device), device: device))

    pipeline = RenderingPipeline(device: self.device, view: metalKitView, scene: scene)
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let aspect = Float(size.width / max(size.height, 1))
    camera.aspect = aspect
    memcpy(cameraBuffer.contents(), &camera, MemoryLayout<Camera>.stride)
  }
  
  func draw(in view: MTKView) {
    semaphore.wait()
    guard let commandBuffer = pipeline.queue.makeCommandBuffer(),
          let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    computeEncoder.setComputePipelineState(pipeline.rayGenPipelineState)
    computeEncoder.setTexture(view.currentDrawable?.texture, index: 0)
    computeEncoder.setBuffer(cameraBuffer, offset: 0, index: 1)

    computeEncoder.useResource(pipeline.accelerationStructure, usage: .read)
    computeEncoder.useResource(cameraBuffer, usage: .read)
    computeEncoder.setAccelerationStructure(pipeline.accelerationStructure, bufferIndex: 0)
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

