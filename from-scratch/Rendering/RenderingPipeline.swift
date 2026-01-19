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
  return tri
}

// MARK: - RenderingPipeline

struct Vertex {
  let position: SIMD3<Float>
  let uv: SIMD2<Float>
}

/// Creates the compute pipeline and owns the BLAS builder for the current scene.
final class RenderingPipeline {
  let queue: MTLCommandQueue
  let device: MTLDevice
  var rayGenPipelineState: MTLComputePipelineState
  let accelerationStructureBuilder: AccelerationStructureBuilder
  private var library: MTLLibrary
  
  
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
  
  /// Build vertex/texture pipelines and optionally register them on a `HeightField`.
  func buildVertexPipeline(initial_buffer: MTLBuffer, heightField: AnyObject? = nil) {
    // If a HeightField is provided, let it create the displacement/texture pipelines
    // The HeightField will use the pipeline library to build its compute pipelines.
    if let hf = heightField as? HeightField {
      hf.buildPipelines(library: library)
    }
  }

  /// Rebuilds all compute pipelines and acceleration structures using the latest default Metal library.
  func reloadShaders(scene: SceneContainer, heightField: AnyObject? = nil) {
    guard let newLibrary = device.makeDefaultLibrary() else { return }
    library = newLibrary

    let pipelineDescriptor = MTLComputePipelineDescriptor()
    pipelineDescriptor.computeFunction = library.makeFunction(name: "compute_main")
    let options: MTLPipelineOption = [.bindingInfo, .bufferTypeInfo]
    let result = try! device.makeComputePipelineState(descriptor: pipelineDescriptor, options: options)
    rayGenPipelineState = result.0

    buildVertexPipeline(initial_buffer: scene.mesh.vertexBuffers.first!.buffer, heightField: heightField)
    accelerationStructureBuilder.buildAccelerationStructure(for: [buildBLAS(device: device, scene: scene)])
  }
}
