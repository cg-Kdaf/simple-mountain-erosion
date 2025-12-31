//
// SceneContainer.swift
// Created on 2025-12-31
//

import MetalKit

/// A minimal scene container that exposes the primary mesh for rendering.
public protocol SceneContainer {
    var mesh: MTKMesh { get }
}

public struct BasicScene: SceneContainer {
    public let mesh: MTKMesh
    public init(mesh: MTKMesh) {
        self.mesh = mesh
    }
}
