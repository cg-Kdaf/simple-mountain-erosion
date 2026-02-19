//
//  MeshFactory.swift
//  from-scratch
//
//  Created by Colin Marmond on 31/12/2025.
//

import MetalKit

public enum MeshFactory {
  struct Vertex {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
  }
  
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
        // Tri 1: i1, i0, i2; Tri 2: i1, i2, i3
        indices.append(contentsOf: [i1, i0, i2, i1, i2, i3])
      }
    }
    
    let vertexDataSize = vertices.count * MemoryLayout<Vertex>.stride
    let vertexData = Data(bytes: vertices, count: vertexDataSize)
    let mdlVertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
    
    let indexDataSize = indices.count * MemoryLayout<UInt32>.stride
    let indexData = Data(bytes: indices, count: indexDataSize)
    let mdlIndexBuffer = allocator.newBuffer(with: indexData, type: .index)
    
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
    
    let indexCount = indices.count
    let submesh = MDLSubmesh(indexBuffer: mdlIndexBuffer,
                             indexCount: indexCount,
                             indexType: .uInt32,
                             geometryType: .triangles,
                             material: nil)
    
    let mdlMesh = MDLMesh(vertexBuffer: mdlVertexBuffer,
                          vertexCount: vertices.count,
                          descriptor: vertexDescriptor,
                          submeshes: [submesh])
    
    return try! MTKMesh(mesh: mdlMesh, device: device)
  }
}

