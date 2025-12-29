//
//  Scene.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import MetalKit

func createScene(allocator: MTKMeshBufferAllocator, device: MTLDevice) -> MTKMesh {
  let mdlMesh = MDLMesh(
    sphereWithExtent: [0.75, 0.75, 0.75],
    segments: [30, 30],
    inwardNormals: false,
    geometryType: .triangles,
    allocator: allocator)
  return try! MTKMesh(mesh: mdlMesh, device: device)
}
