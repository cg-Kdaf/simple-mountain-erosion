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
}
