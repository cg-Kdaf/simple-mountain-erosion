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
  let queue: MTLCommandQueue!
  var description: String
  var hash: Int
  var superclass: AnyClass?
  var accelerationStructure: MPSAccelerationStructure!
  var pipelineState: MTLRenderPipelineState!
  var mesh: MTKMesh!
  
  init?(metalKitView: MTKView) {
    metalKitView.colorPixelFormat = .rgba16Float
    metalKitView.sampleCount = 1
    metalKitView.drawableSize = metalKitView.frame.size
    
    guard let device_ = metalKitView.device else {
      return nil
    }
    device = device_
    queue = self.device.makeCommandQueue()
    semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
    hash = 100
    description = "Renderer"
    
    createPipelines(device: self.device, view: metalKitView)
  }

  
  func createPipelines(device: MTLDevice, view: MTKView) {
    guard let library = device.makeDefaultLibrary() else {
      return
    }
    
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
    pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
    pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
    mesh = createScene(allocator: MTKMeshBufferAllocator(device: device), device: device)
    pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
    pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    return
  }
  
  func draw(in view: MTKView) {
    semaphore.wait()
    guard let commandBuffer = queue.makeCommandBuffer(),
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor:  renderPassDescriptor)
    else { fatalError() }
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: 0)
    guard let submesh = mesh.submeshes.first else {
      fatalError()
    }
    renderEncoder.drawIndexedPrimitives(
      type: .triangle,
      indexCount: submesh.indexCount,
      indexType: submesh.indexType,
      indexBuffer: submesh.indexBuffer.buffer,
      indexBufferOffset: 0)
    
    renderEncoder.endEncoding()
    guard let drawable = view.currentDrawable else {
      fatalError()
    }
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
