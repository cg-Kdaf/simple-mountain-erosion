//
//  RayTracingResources.swift
//

import MetalKit

/// RayTracingResources groups resource indices and placeholder uniform types. No logic yet.
public enum RayTracingBindings {
  public static let outputTextureIndex: Int = 0
  public static let accelerationStructureBufferIndex: Int = 0
  public static let cameraUniformsBufferIndex: Int = 1
  public static let frameUniformsBufferIndex: Int = 2
}

/// Placeholder camera uniforms (layout to be defined later, do not use yet).
public struct CameraUniforms { public init() {} }

/// Placeholder per-frame uniforms.
public struct FrameUniforms { public init() {} }
