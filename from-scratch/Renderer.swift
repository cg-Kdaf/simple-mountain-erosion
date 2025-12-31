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
  var accelerationStructure: MTLAccelerationStructure!
  var accelerationStructureSize: MTLAccelerationStructureSizes!
  var rayGenPipelineState: MTLComputePipelineState!
  var rayGenPipelineReflection: MTLComputePipelineReflection!
  var mesh: MTKMesh!
  
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
    queue = self.device.makeCommandQueue()
    semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
    hash = 100
    description = "Renderer"

    createPipelines(device: self.device, view: metalKitView)
  }
  
  func buildAccelerationStructure(device: MTLDevice, queue: MTLCommandQueue, mesh: MTKMesh) {
    // Build a Bottom-Level Acceleration Structure (BLAS) from the provided MTKMesh
    // Extract geometry info from the first vertex buffer and first submesh
    guard let vertexVB = mesh.vertexBuffers.first else {
      fatalError("Mesh has no vertex buffers")
    }
    guard let submesh = mesh.submeshes.first else {
      fatalError("Mesh has no submeshes")
    }
    let triangleCount = submesh.indexCount / 3

    // Configure the triangle geometry descriptor
    let tri = MTLAccelerationStructureTriangleGeometryDescriptor()
    tri.vertexBuffer = vertexVB.buffer
    tri.vertexStride = (mesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
    tri.vertexFormat = .float3
    tri.indexBuffer = submesh.indexBuffer.buffer
    tri.indexType = submesh.indexType
    tri.triangleCount = triangleCount
    tri.opaque = true

    do { // Store the vertex normals in the primitive AS
      // Build per-primitive data: store three vertex normals per triangle (float3 * 3 = 36B; align to 48B)
      let primitiveStride = 48 // bytes per triangle payload (aligned)
      let primitiveDataBuffer = device.makeBuffer(length: triangleCount * primitiveStride, options: .storageModeShared)!
      
      // Try to locate the normal attribute in the MTKMesh's vertex descriptor
      // We assume attribute(1) is the normal, which is common for Model I/O layouts.
      // If not found, we will fall back to geometric normals.
      var normalAttributeOffset: Int? = nil
      
      let vertexStrideBytes = (mesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
      if let normalAttr = mesh.vertexDescriptor.attributes[1] as? MDLVertexAttribute,
         normalAttr.name == MDLVertexAttributeNormal,
         normalAttr.format == .float3 {
        normalAttributeOffset = Int(normalAttr.offset)
      }
      
      func loadFloat3(from base: UnsafeRawPointer, offset: Int) -> SIMD3<Float> {
        return base.advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
      }
      
      // Fill the primitive payloads
      let primRaw = primitiveDataBuffer.contents()
      let idxPtr = submesh.indexBuffer.buffer.contents().advanced(by: submesh.indexBuffer.offset).assumingMemoryBound(to: UInt16.self)
      for t in 0..<triangleCount {
        let i0 = Int(idxPtr[t*3 + 0])
        let i1 = Int(idxPtr[t*3 + 1])
        let i2 = Int(idxPtr[t*3 + 2])
        
        // Compute byte offsets per vertex
        let v0Base = vertexVB.buffer.contents().advanced(by: i0 * vertexStrideBytes)
        let v1Base = vertexVB.buffer.contents().advanced(by: i1 * vertexStrideBytes)
        let v2Base = vertexVB.buffer.contents().advanced(by: i2 * vertexStrideBytes)
        
        // Load normals if available
        let nOff = normalAttributeOffset!
        let n0 = loadFloat3(from: v0Base, offset: nOff)
        let n1 = loadFloat3(from: v1Base, offset: nOff)
        let n2 = loadFloat3(from: v2Base, offset: nOff)
        
        // Write three float3 normals into 48B record: [n0(12), n1(12), n2(12), pad(12)]
        let dst = primRaw.advanced(by: t * primitiveStride)
        dst.storeBytes(of: n0, as: SIMD3<Float>.self)
        dst.advanced(by: 12).storeBytes(of: n1, as: SIMD3<Float>.self)
        dst.advanced(by: 24).storeBytes(of: n2, as: SIMD3<Float>.self)
        // leave remaining 12 bytes as padding
      }
      
      // Attach per-primitive data to the geometry descriptor
      tri.primitiveDataBuffer = primitiveDataBuffer
      tri.primitiveDataStride = primitiveStride
      tri.primitiveDataBufferOffset = 0
      tri.primitiveDataElementSize = primitiveStride
    }
  
    let primDesc = MTLPrimitiveAccelerationStructureDescriptor()
    primDesc.geometryDescriptors = [tri]
    
    accelerationStructureSize = device.accelerationStructureSizes(descriptor: primDesc)
    let accelerationBuffer = device.makeBuffer(length: accelerationStructureSize.accelerationStructureSize,
                                               options: .storageModePrivate)!
    accelerationStructure = device.makeAccelerationStructure(size: accelerationBuffer.length)
    
    // Scratch buffer
    let scratchBuffer = device.makeBuffer(length: accelerationStructureSize.buildScratchBufferSize,
                                          options: .storageModePrivate)!

    // Encode build
    let commandBuffer = queue.makeCommandBuffer()!
    let asEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
    asEncoder.build(accelerationStructure: accelerationStructure,
                    descriptor: primDesc,
                    scratchBuffer: scratchBuffer,
                    scratchBufferOffset: 0)
    asEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }

  
  func createPipelines(device: MTLDevice, view: MTKView) {
    guard let library = device.makeDefaultLibrary() else {
      return
    }
    
    let pipelineDescriptor = MTLComputePipelineDescriptor()
    pipelineDescriptor.computeFunction = library.makeFunction(name: "compute_main")
    let options: MTLPipelineOption = [.bindingInfo, .bufferTypeInfo]
    let result = try! device.makeComputePipelineState(descriptor: pipelineDescriptor, options: options)
    rayGenPipelineState = result.0
    rayGenPipelineReflection = result.1
    mesh = createScene(allocator: MTKMeshBufferAllocator(device: device), device: device)
    buildAccelerationStructure(device: device, queue: queue, mesh: mesh)
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    return
  }
  
  func draw(in view: MTKView) {
    semaphore.wait()
    guard let commandBuffer = queue.makeCommandBuffer(),
          let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    computeEncoder.setComputePipelineState(rayGenPipelineState)
    computeEncoder.setTexture(view.currentDrawable?.texture, index: 0)

    computeEncoder.useResource(accelerationStructure, usage: .read)
    computeEncoder.setAccelerationStructure(accelerationStructure, bufferIndex: 0)
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

