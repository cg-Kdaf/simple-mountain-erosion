//
//  HeightFieldStructures.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//
import MetalKit

struct HeightFieldTextures {
  // RG32 st: R(ground height) G(Water level)
  var terrain: MTLTexture
  var terrainTemp: MTLTexture
  
  // RGBA16 st: R(left) G(right) B(top) A(bottom)
  var flux: MTLTexture
  var fluxTemp: MTLTexture
  
  // RG16 st: R(velocity X) G(velocity Y)
  var velocity: MTLTexture
  var velocityTemp: MTLTexture
  
  // R16 st: R(suspended sediment)
  var sediment: MTLTexture
  var sedimentTemp: MTLTexture
  
  // R16 st: R(slipperage)
  var slipperage: MTLTexture
  
  // RGBA16 st: R(left) G(right) B(top) A(bottom)
  var slipperageFlux: MTLTexture
  
  // RGB16 classical normal texture
  var normal: MTLTexture
}

struct HeightFieldPipelineStates {
  // General
  var displace: MTLComputePipelineState
  var reset: MTLComputePipelineState
  var recalculateNormals: MTLComputePipelineState
  var progressiveBlur: MTLComputePipelineState
  
  // Erosion - Hydraulic
  var rain: MTLComputePipelineState
  var flow: MTLComputePipelineState
  var waterheight: MTLComputePipelineState
  var advection: MTLComputePipelineState
  var velocity: MTLComputePipelineState
  
  // Erosion - Sediment
  var sediment: MTLComputePipelineState
  
  // Erosion - Thermal
  var slipperage: MTLComputePipelineState
  var thermalFlux: MTLComputePipelineState
  var thermalApply: MTLComputePipelineState
  
  var evaporation: MTLComputePipelineState
}

enum HeightFieldError: Error {
  case shaderLoadError
}
