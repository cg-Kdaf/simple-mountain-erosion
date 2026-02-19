//
//  HeightFieldSimulation.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import MetalKit

extension HeightField {
  func resetHeightField() {
    resetField = true
  }
  
  func setPaused(_ paused: Bool) {
    isPaused = paused
  }
  
  private func createDisplatchGrid(pipelineState: MTLComputePipelineState) -> (MTLSize, MTLSize) {
    // Returns threadsPerGrid, threadsPerThreadgroup
    let w_texture = pipelineState.threadExecutionWidth
    let h_texture = pipelineState.maxTotalThreadsPerThreadgroup / w_texture
    let threadsPerThreadgroup = MTLSizeMake(w_texture, h_texture, 1)
    let threadsPerGrid = MTLSize(width: (textureResolution + w_texture - 1) / w_texture,
                                 height: (textureResolution + h_texture - 1) / h_texture,
                                 depth: 1)
    return (threadsPerGrid, threadsPerThreadgroup)
  }
  
  private func resetHeightField(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    encoder.label = "Reset Height Field Pass"
    encoder.setComputePipelineState(pipelineStates.reset)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.flux, index: 1)
    
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    
    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.reset)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
    
    // Calculate the normals for the first time
    recalculateNormals(commandBuffer: commandBuffer)
  }
  
  private func blurHeightField(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    encoder.label = "Progressive Blur Height Field Pass"
    encoder.setComputePipelineState(pipelineStates.progressiveBlur)
    encoder.setTexture(textures.terrain, index: 0)
    
    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.progressiveBlur)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func liveAnimation(commandBuffer: MTLCommandBuffer, currentTime: Float) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    var currentTime = currentTime
    
    encoder.label = "Live animation Texture Pass"
    encoder.setComputePipelineState(pipelineStates.displace)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setBytes(&currentTime,
                     length: MemoryLayout<Float>.size,
                     index: 0)
    
    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.displace)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func recalculateNormals(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    encoder.label = "Normal Texture Recalculation Pass"
    encoder.setComputePipelineState(pipelineStates.recalculateNormals)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.normal, index: 1)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    
    let (threadsPerGrid, threadsPerThreadgroup) =
    createDisplatchGrid(pipelineState: pipelineStates.recalculateNormals)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func erosionStep(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    encoder.label = "Erosion Simulation Passes"
    
    func terrainFlip() {
      let terrain_swap = textures.terrain
      textures.terrain = textures.terrainTemp
      textures.terrainTemp = terrain_swap
    }
    
    func fluxFlip() {
      let flux_swap = textures.flux
      textures.flux = textures.fluxTemp
      textures.fluxTemp = flux_swap
    }
    
    func sedimentFlip() {
      let sediment_swap = textures.sediment
      textures.sediment = textures.sedimentTemp
      textures.sedimentTemp = sediment_swap
    }
    
    func velocityFlip() {
      let velocity_swap = textures.velocity
      textures.velocity = textures.velocityTemp
      textures.velocityTemp = velocity_swap
    }
    
    // 1. Compute Flows (flow_compute)
    encoder.setComputePipelineState(pipelineStates.flow)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.flux, index: 1)
    encoder.setTexture(textures.fluxTemp, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    var (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.flow)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    fluxFlip()
    
    // 2. Compute Water Height (waterheight_compute)
    encoder.setComputePipelineState(pipelineStates.waterheight)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setTexture(textures.flux, index: 2)
    encoder.setTexture(textures.velocity, index: 3)
    encoder.setTexture(textures.velocityTemp, index: 4)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.waterheight)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    terrainFlip()
    velocityFlip()
    
    // 3. Compute Sediment (sediment_compute)
    encoder.setComputePipelineState(pipelineStates.sediment)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setTexture(textures.sediment, index: 2)
    encoder.setTexture(textures.sedimentTemp, index: 3)
    encoder.setTexture(textures.velocity, index: 4)
    encoder.setTexture(textures.normal, index: 5)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.sediment)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    terrainFlip()
    sedimentFlip()
    
    // 4. Compute Advection (advection_compute)
    encoder.setComputePipelineState(pipelineStates.advection)
    encoder.setTexture(textures.velocity, index: 0)
    encoder.setTexture(textures.sediment, index: 1)
    encoder.setTexture(textures.sedimentTemp, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.advection)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    sedimentFlip()
    
    // 5. Compute Slipperage (slipperage_compute)
    encoder.setComputePipelineState(pipelineStates.slipperage)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.slipperage, index: 1)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.slipperage)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    
    // 6. Compute Thermal Flux (thermal_flux_compute)
    encoder.setComputePipelineState(pipelineStates.thermalFlux)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.slipperage, index: 1)
    encoder.setTexture(textures.slipperageFlux, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.thermalFlux)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    
    // 7. Compute Thermal Apply (thermal_apply_compute)
    encoder.setComputePipelineState(pipelineStates.thermalApply)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setTexture(textures.slipperageFlux, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.thermalApply)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    terrainFlip()
    
    // 8. Compute Evaporation (evaporation)
    encoder.setComputePipelineState(pipelineStates.evaporation)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.evaporation)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    terrainFlip()
    
    encoder.endEncoding()
  }
  
  func executeStep(commandBuffer: MTLCommandBuffer, currentTime: Float) {
    if (resetField) {
      resetHeightField(commandBuffer: commandBuffer)
      resetField = false
    }
    
    if isPaused {
      return
    }
    
    for _ in 0..<5 {
      erosionStep(commandBuffer: commandBuffer)
    }
    recalculateNormals(commandBuffer: commandBuffer)
  }
  
  func addRainUniformly(commandBuffer: MTLCommandBuffer, rainAmount: Float) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { return }
    
    encoder.label = "Add Uniform Rain Pass"
    encoder.setComputePipelineState(pipelineStates.rain)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    
    var rainAmountBuffer = rainAmount
    encoder.setBytes(&rainAmountBuffer,
                     length: MemoryLayout<Float>.size,
                     index: 1)
    
    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.rain)
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
    
    // Flip the terrain texture since rain shader writes to terrainTemp
    let terrain_swap = textures.terrain
    textures.terrain = textures.terrainTemp
    textures.terrainTemp = terrain_swap
  }
}

