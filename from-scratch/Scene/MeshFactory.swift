//
//  MeshFactory.swift
//

import MetalKit

/// MeshFactory centralizes creation of MTKMesh assets used by the scene.
public enum MeshFactory {
  /// Returns the primary mesh for the scene using an external creator (kept for backward compatibility).
  public static func makeBasicSphere(allocator: MTKMeshBufferAllocator, device: MTLDevice) -> MTKMesh {
    let mdlMesh = MDLMesh(
      sphereWithExtent: [0.75, 0.75, 0.75],
      segments: [30, 30],
      inwardNormals: false,
      geometryType: .triangles,
      allocator: allocator)
    return try! MTKMesh(mesh: mdlMesh, device: device)
  }
  
  public static func makeBasicPlane(allocator: MTKMeshBufferAllocator, device: MTLDevice) -> MTKMesh {
    let mdlMesh = MDLMesh.newPlane(
      withDimensions: [2.0, 2.0],
      segments: [4,4],
      geometryType: .triangles,
      allocator: allocator)
    return try! MTKMesh(mesh: mdlMesh, device: device)
  }
  
  /// Simple interleaved vertex layout for explicit meshes
  struct Vertex {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
  }
  
  /// Creates a basic XY plane centered at origin using explicit vertex/index buffers.
  /// - Parameters:
  ///   - allocator: MTKMeshBufferAllocator used for Model I/O buffers
  ///   - device: MTLDevice used to create the MTKMesh
  ///   - width: plane width along X
  ///   - height: plane height along Y
  ///   - segmentsX: number of subdivisions along X axis
  ///   - segmentsY: number of subdivisions along Y axis
  /// - Returns: An MTKMesh representing the plane
  public static func makeExplicitPlane(
    allocator: MTKMeshBufferAllocator,
    device: MTLDevice,
    width: Float = 2.0,
    height: Float = 2.0,
    segmentsX: Int = 1,
    segmentsY: Int = 1
  ) -> MTKMesh {
    // Build a grid of vertices in XZ plane (Y = 0), centered at origin
    let sx = max(1, segmentsX)
    let sy = max(1, segmentsY)
    let hw = width * 0.5
    let hh = height * 0.5
    let vertsPerRow = sx + 1
    let vertsPerCol = sy + 1
    var vertices: [Vertex] = []
    vertices.reserveCapacity(vertsPerRow * vertsPerCol)
    
    for j in 0...sy {
      let v = Float(j) / Float(sy)
      let z = -hh + v * height
      for i in 0...sx {
        let u = Float(i) / Float(sx)
        let x = -hw + u * width
        vertices.append(Vertex(position: SIMD3<Float>(x, 0, z), uv: SIMD2<Float>(u, v)))
      }
    }
    
    // Indices: two triangles per cell
    var indices: [UInt32] = []
    indices.reserveCapacity(sx * sy * 6)
    for j in 0..<sy {
      for i in 0..<sx {
        let row0 = j * vertsPerRow
        let row1 = (j + 1) * vertsPerRow
        let i0 = UInt32(row0 + i)
        let i1 = UInt32(row0 + i + 1)
        let i2 = UInt32(row1 + i)
        let i3 = UInt32(row1 + i + 1)
        // Tri 1: i0, i1, i2; Tri 2: i2, i1, i3
        indices.append(contentsOf: [i1, i0, i2, i1, i2, i3])
      }
    }
    
    // Create Model I/O vertex buffer
    let vertexDataSize = vertices.count * MemoryLayout<Vertex>.stride
    let vertexData = Data(bytes: vertices, count: vertexDataSize)
    let mdlVertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
    
    // Create Model I/O index buffer (use 32-bit to handle large grids safely)
    let indexDataSize = indices.count * MemoryLayout<UInt32>.stride
    let indexData = Data(bytes: indices, count: indexDataSize)
    let mdlIndexBuffer = allocator.newBuffer(with: indexData, type: .index)
    
    // Describe the layout: position (float3), uv (float2)
    let vertexDescriptor = MDLVertexDescriptor()
    vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                        format: .float3,
                                                        offset: 0,
                                                        bufferIndex: 0)
    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                        format: .float2,
                                                        offset: MemoryLayout<SIMD3<Float>>.stride,
                                                        bufferIndex: 0)
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Vertex>.stride)
    
    // Build MDLSubmesh with triangle topology
    let indexCount = indices.count
    let submesh = MDLSubmesh(indexBuffer: mdlIndexBuffer,
                             indexCount: indexCount,
                             indexType: .uInt32,
                             geometryType: .triangles,
                             material: nil)
    
    // Create MDLMesh from our buffers
    let mdlMesh = MDLMesh(vertexBuffer: mdlVertexBuffer,
                          vertexCount: vertices.count,
                          descriptor: vertexDescriptor,
                          submeshes: [submesh])
    
    // Finally, create the MTKMesh
    return try! MTKMesh(mesh: mdlMesh, device: device)
  }
}

