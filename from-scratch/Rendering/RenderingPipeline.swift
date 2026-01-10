//
//  RenderingPipeline.swift
//  from-scratch
//
//  Created by Colin Marmond on 31/12/2025.
//

import MetalKit
import MetalPerformanceShaders


func buildBLAS(device: MTLDevice, scene: SceneContainer) -> MTLAccelerationStructureGeometryDescriptor {
  let mesh = scene.mesh
  
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
    // NOTE: This assumes a normal attribute exists at attributes[1] and is float3.
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
  return tri
}

// MARK: - RenderingPipeline

struct Vertex {
  let position: SIMD3<Float>
  let normal: SIMD3<Float>
  let uv: SIMD2<Float>
}

/// Creates the compute pipeline and owns the BLAS builder for the current scene.
final class RenderingPipeline {
  let queue: MTLCommandQueue
  let device: MTLDevice
  let rayGenPipelineState: MTLComputePipelineState
  var displacePipelineState: MTLComputePipelineState?
  let accelerationStructureBuilder: AccelerationStructureBuilder
  private let library: MTLLibrary
  
  
  init(device: MTLDevice, view: MTKView, scene: SceneContainer) {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
        fatalError("Failed to create command queue")
    }
    self.queue = queue
    guard let library = device.makeDefaultLibrary() else {
      preconditionFailure("Failed to load default Metal library")
    }
    self.library = library
    
    let pipelineDescriptor = MTLComputePipelineDescriptor()
    pipelineDescriptor.computeFunction = library.makeFunction(name: "compute_main")
    let options: MTLPipelineOption = [.bindingInfo, .bufferTypeInfo]
    let result = try! device.makeComputePipelineState(descriptor: pipelineDescriptor, options: options)
    rayGenPipelineState = result.0
    accelerationStructureBuilder = AccelerationStructureBuilder(device: device, queue: queue)
    accelerationStructureBuilder.buildAccelerationStructure(for: [buildBLAS(device: device, scene: scene)])
  }
  
  func buildVertexPipeline(initial_buffer: MTLBuffer) {
    // Create the vertex displacement pipeline
    guard let displaceFunction = library.makeFunction(name: "compute_vertices") else { fatalError() }
    displacePipelineState = try! device.makeComputePipelineState(function: displaceFunction)
  }
}
