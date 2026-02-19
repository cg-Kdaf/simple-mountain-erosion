//
//  SceneContainer.swift
//  from-scratch
//
//  Created by Colin Marmond on 31/12/2025.
//

import MetalKit

public protocol SceneContainer {
  var mesh: MTKMesh { get }
}

public struct BasicScene: SceneContainer {
  public let mesh: MTKMesh
  public init(mesh: MTKMesh) {
    self.mesh = mesh
  }
}
