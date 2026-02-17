import MetalKit
import SwiftUI

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

final class HeightField {
  let device: MTLDevice
  private(set) var textures: HeightFieldTextures
  private var pipelineStates: HeightFieldPipelineStates
  private var resetField: Bool = true
  private var isPaused: Bool = true
  private(set) var textureResolution: Int
  
  private var simulationUniforms: HeightMapUniforms
  private var simulationUniformsBuffer: MTLBuffer

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

    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.reset)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
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
    
    // Skip simulation steps if paused
    if isPaused {
      return
    }
    
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    recalculateNormals(commandBuffer: commandBuffer)
  }
  
  /// Execute a single erosion pass with uniform rain amount, without pausing the simulation
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

