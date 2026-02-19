//
//  HeightField.swift
//  from-scratch
//
//  Created by Colin Marmond on 25/01/2026.
//

import MetalKit
import SwiftUI

final class HeightField {
  let device: MTLDevice
  internal var textures: HeightFieldTextures
  internal var pipelineStates: HeightFieldPipelineStates
  internal var resetField: Bool = true
  internal var isPaused: Bool = true
  internal var textureResolution: Int
  
  internal var simulationUniforms: HeightMapUniforms
  internal var simulationUniformsBuffer: MTLBuffer
  
  init(device: MTLDevice,
       textureResolution: Int,
       library: MTLLibrary? = nil,
       simulationUniforms: HeightMapUniforms) {
    self.device = device
    self.textureResolution = textureResolution
    textures = HeightField.createTextures(device: device, resolution: textureResolution)
    
    if let lib = library {
      pipelineStates = try! HeightField.buildPipelines(device: device, library: lib)
    } else {
      let defaultLib = device.makeDefaultLibrary()!
      pipelineStates = try! HeightField.buildPipelines(device: device, library: defaultLib)
    }
    
    self.simulationUniforms = simulationUniforms
    simulationUniformsBuffer = device.makeBuffer(length: MemoryLayout<HeightMapUniforms>.stride, options: .storageModeShared)!
    updateErosionUniformBuffer(simulationUniforms)
  }
  
  func updateErosionUniformBuffer(_ data: HeightMapUniforms) {
    let _ = withUnsafeBytes(of: data) { bytes in
      memcpy(simulationUniformsBuffer.contents(), bytes.baseAddress!, MemoryLayout<HeightMapUniforms>.stride)
    }
  }
  
  static private func loadShader(device: MTLDevice, library: MTLLibrary, shader_name: String) throws -> MTLComputePipelineState {
    if let shaderFn = library.makeFunction(name: shader_name) {
      guard let pipelineState = try? device.makeComputePipelineState(function: shaderFn) else {
        throw HeightFieldError.shaderLoadError
      }
      return pipelineState
    } else {
      throw HeightFieldError.shaderLoadError
    }
  }
  
  static func createTextures(device: MTLDevice, resolution: Int) -> HeightFieldTextures {
    // Helper function to create texture with standard usage
    func createTexture(format: MTLPixelFormat) -> MTLTexture {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format,
        width: resolution,
        height: resolution,
        mipmapped: false)
      desc.usage = [.shaderRead, .shaderWrite]
      return device.makeTexture(descriptor: desc)!
    }
    
    // RG32: R(ground height) G(water level)
    let terrainA = createTexture(format: .rg32Float)
    let terrainB = createTexture(format: .rg32Float)
    
    // RGBA16: R(left) G(right) B(top) A(bottom)
    let fluxA = createTexture(format: .rgba16Float)
    let fluxB = createTexture(format: .rgba16Float)
    
    // RG16: R(velocity X) G(velocity Y)
    let velocityA = createTexture(format: .rg16Float)
    let velocityB = createTexture(format: .rg16Float)
    
    // R16: R(suspended sediment)
    let sedimentA = createTexture(format: .r16Float)
    let sedimentB = createTexture(format: .r16Float)
    
    // R16: R(slipperage)
    let slipperage = createTexture(format: .r16Float)
    
    // RGBA16: R(left) G(right) B(top) A(bottom)
    let slipperageFlux = createTexture(format: .rgba16Float)
    
    // RGB16: classical normal texture
    let normal = createTexture(format: .rgba16Float)
    
    return HeightFieldTextures(
      terrain: terrainA,
      terrainTemp: terrainB,
      flux: fluxA,
      fluxTemp: fluxB,
      velocity: velocityA,
      velocityTemp: velocityB,
      sediment: sedimentA,
      sedimentTemp: sedimentB,
      slipperage: slipperage,
      slipperageFlux: slipperageFlux,
      normal: normal)
  }
  
  static private func buildPipelines(device: MTLDevice, library: MTLLibrary) throws -> HeightFieldPipelineStates {
    let displace = try HeightField.loadShader(device: device, library: library, shader_name: "live_animation_heightmap")
    let recalculateNormals = try HeightField.loadShader(device: device, library: library, shader_name: "recalculate_normals")
    let reset = try HeightField.loadShader(device: device, library: library, shader_name: "reset_heightmap")
    let progressiveBlur = try HeightField.loadShader(device: device, library: library, shader_name: "progressive_blur")
    
    let rain = try HeightField.loadShader(device: device, library: library, shader_name: "add_rain")
    let flow = try HeightField.loadShader(device: device, library: library, shader_name: "flow_compute")
    let waterheight = try HeightField.loadShader(device: device, library: library, shader_name: "waterheight_compute")
    let advection = try HeightField.loadShader(device: device, library: library, shader_name: "advection_compute")
    let velocity = try HeightField.loadShader(device: device, library: library, shader_name: "waterheight_compute")
    let sediment = try HeightField.loadShader(device: device, library: library, shader_name: "sediment_compute")
    let slipperage = try HeightField.loadShader(device: device, library: library, shader_name: "slipperage_compute")
    let thermalFlux = try HeightField.loadShader(device: device, library: library, shader_name: "thermal_flux_compute")
    let thermalApply = try HeightField.loadShader(device: device, library: library, shader_name: "thermal_apply_compute")
    let evaporation = try HeightField.loadShader(device: device, library: library, shader_name: "evaporation")
    
    return HeightFieldPipelineStates(
      displace: displace,
      reset: reset,
      recalculateNormals: recalculateNormals,
      progressiveBlur: progressiveBlur,
      rain: rain,
      flow: flow,
      waterheight: waterheight,
      advection: advection,
      velocity: velocity,
      sediment: sediment,
      slipperage: slipperage,
      thermalFlux: thermalFlux,
      thermalApply: thermalApply,
      evaporation: evaporation)
  }
  
  func rebuildPipeline(with library: MTLLibrary) throws {
    self.pipelineStates = try HeightField.buildPipelines(device: device, library: library)
  }
  
  func resize(to newResolution: Int) {
    guard newResolution != textureResolution else { return }
    textureResolution = newResolution
    textures = HeightField.createTextures(device: device, resolution: textureResolution)
    resetField = true
  }
}
