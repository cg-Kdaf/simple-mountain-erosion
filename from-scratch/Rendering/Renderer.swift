//
//  Renderer.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import MetalKit
import MetalPerformanceShaders

class Renderer: MTKViewDelegate {
  let device: MTLDevice
  let maxFramesInFlight = 1
  var semaphore: DispatchSemaphore!
  var description: String
  var hash: Int
  var superclass: AnyClass?
  var scene: SceneContainer
  var pipeline: RenderingPipeline
  
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
    semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
    hash = 100
    description = "Renderer"
    
    scene = BasicScene(mesh: MeshFactory.makeBasicSphere(allocator: MTKMeshBufferAllocator(device: device), device: device))

    pipeline = RenderingPipeline(device: self.device, view: metalKitView, scene: scene)
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    return
  }
  
  func draw(in view: MTKView) {
    semaphore.wait()
    guard let commandBuffer = pipeline.queue.makeCommandBuffer(),
          let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    computeEncoder.setComputePipelineState(pipeline.rayGenPipelineState)
    computeEncoder.setTexture(view.currentDrawable?.texture, index: 0)

    computeEncoder.useResource(pipeline.accelerationStructure, usage: .read)
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

