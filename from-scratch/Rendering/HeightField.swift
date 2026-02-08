import MetalKit
import SwiftUI

struct HeightFieldTextures {
  // RGBA32 st: R(bedrock(b)) G(Regolith(r)) B(Water(d)) A(Suspended sediments(s))
  var terrain: MTLTexture
  var terrainTemp: MTLTexture
  
  // RGBA16 st: R(left) G(right) B(top) A(bottom)
  var flux: MTLTexture
  var fluxTemp: MTLTexture
  
  // RG16 st: R(velocity X) G(velocity Y)
  var velocity: MTLTexture
  
  // RGB16 classical normal texture
  var normal: MTLTexture
}

struct HeightFieldPipelineStates {
  var displace: MTLComputePipelineState
  var reset: MTLComputePipelineState
  var recalculateNormals: MTLComputePipelineState
  var progressiveBlur: MTLComputePipelineState
  
  var rain: MTLComputePipelineState
  var flux: MTLComputePipelineState
  var velocity: MTLComputePipelineState
  var deposition: MTLComputePipelineState
  var advection: MTLComputePipelineState
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
    let terrainDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba32Float,
      width: resolution,
      height: resolution,
      mipmapped: false)
    terrainDesc.usage = [.shaderRead, .shaderWrite]
    let terrainA = device.makeTexture(descriptor: terrainDesc)!
    let terrainB = device.makeTexture(descriptor: terrainDesc)!
    
    let fluxDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: resolution,
      height: resolution,
      mipmapped: false)
    fluxDesc.usage = [.shaderRead, .shaderWrite]
    let fluxA = device.makeTexture(descriptor: fluxDesc)!
    let fluxB = device.makeTexture(descriptor: fluxDesc)!
    
    let velocityDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg16Float,
      width: resolution,
      height: resolution,
      mipmapped: false)
    velocityDesc.usage = [.shaderRead, .shaderWrite]
    let velocity = device.makeTexture(descriptor: velocityDesc)!
    
    let normalDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: resolution,
      height: resolution,
      mipmapped: false)
    normalDesc.usage = [.shaderRead, .shaderWrite]
    let normal = device.makeTexture(descriptor: normalDesc)!
    return HeightFieldTextures(
      terrain: terrainA,
      terrainTemp: terrainB,
      flux: fluxA,
      fluxTemp: fluxB,
      velocity: velocity,
      normal: normal)
  }

  static private func buildPipelines(device: MTLDevice, library: MTLLibrary) throws -> HeightFieldPipelineStates {
    let displace = try HeightField.loadShader(device: device, library: library, shader_name: "live_animation_heightmap")
    let recalculateNormals = try HeightField.loadShader(device: device, library: library, shader_name: "recalculate_normals")
    let reset = try HeightField.loadShader(device: device, library: library, shader_name: "reset_heightmap")
    let progressiveBlur = try HeightField.loadShader(device: device, library: library, shader_name: "progressive_blur")
    
    let add_rain = try HeightField.loadShader(device: device, library: library, shader_name: "add_rain")
    let calc_flux = try HeightField.loadShader(device: device, library: library, shader_name: "calc_flux")
    let water_velocity = try HeightField.loadShader(device: device, library: library, shader_name: "water_velocity")
    let erosion_deposition = try HeightField.loadShader(device: device, library: library, shader_name: "erosion_deposition")
    let sediment_transport = try HeightField.loadShader(device: device, library: library, shader_name: "sediment_transport")
    let evaporation = try HeightField.loadShader(device: device, library: library, shader_name: "evaporation")
    return HeightFieldPipelineStates(
      displace: displace,
      reset: reset,
      recalculateNormals: recalculateNormals,
      progressiveBlur: progressiveBlur,
      rain: add_rain,
      flux: calc_flux,
      velocity: water_velocity,
      deposition: erosion_deposition,
      advection: sediment_transport,
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
    
    // 1. Add Rain
    encoder.setComputePipelineState(pipelineStates.rain)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    let (threadsPerGrid1, threadsPerThreadgroup1) = createDisplatchGrid(pipelineState: pipelineStates.rain)
    encoder.dispatchThreadgroups(threadsPerGrid1, threadsPerThreadgroup: threadsPerThreadgroup1)
    
    // 2. Calculate Flux
    encoder.setComputePipelineState(pipelineStates.flux)
    encoder.setTexture(textures.terrainTemp, index: 0)
    encoder.setTexture(textures.flux, index: 1)
    encoder.setTexture(textures.fluxTemp, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    let (threadsPerGrid2, threadsPerThreadgroup2) = createDisplatchGrid(pipelineState: pipelineStates.flux)
    encoder.dispatchThreadgroups(threadsPerGrid2, threadsPerThreadgroup: threadsPerThreadgroup2)
    
    // 3. Update Water and Calculate Velocity
    encoder.setComputePipelineState(pipelineStates.velocity)
    encoder.setTexture(textures.terrainTemp, index: 0)
    encoder.setTexture(textures.terrain, index: 1)
    encoder.setTexture(textures.fluxTemp, index: 2)
    encoder.setTexture(textures.velocity, index: 3)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    let (threadsPerGrid3, threadsPerThreadgroup3) = createDisplatchGrid(pipelineState: pipelineStates.velocity)
    encoder.dispatchThreadgroups(threadsPerGrid3, threadsPerThreadgroup: threadsPerThreadgroup3)

    // 4. Erosion and Deposition
    encoder.setComputePipelineState(pipelineStates.deposition)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setTexture(textures.velocity, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    let (threadsPerGrid4, threadsPerThreadgroup4) = createDisplatchGrid(pipelineState: pipelineStates.deposition)
    encoder.dispatchThreadgroups(threadsPerGrid4, threadsPerThreadgroup: threadsPerThreadgroup4)
    
    // 5. Sediment Advection
    encoder.setComputePipelineState(pipelineStates.advection)
    encoder.setTexture(textures.terrainTemp, index: 0)
    encoder.setTexture(textures.terrain, index: 1)
    encoder.setTexture(textures.velocity, index: 2)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    let (threadsPerGrid5, threadsPerThreadgroup5) = createDisplatchGrid(pipelineState: pipelineStates.advection)
    encoder.dispatchThreadgroups(threadsPerGrid5, threadsPerThreadgroup: threadsPerThreadgroup5)
    
    // 6. Evaporation
    encoder.setComputePipelineState(pipelineStates.evaporation)
    encoder.setTexture(textures.terrain, index: 0)
    encoder.setTexture(textures.terrainTemp, index: 1)
    encoder.setBuffer(simulationUniformsBuffer, offset: 0, index: 0)
    let (threadsPerGrid6, threadsPerThreadgroup6) = createDisplatchGrid(pipelineState: pipelineStates.evaporation)
    encoder.dispatchThreadgroups(threadsPerGrid6, threadsPerThreadgroup: threadsPerThreadgroup6)
    
    let terrain_swap = textures.terrain
    textures.terrain = textures.terrainTemp
    textures.terrainTemp = terrain_swap

    let flux_swap = textures.flux
    textures.flux = textures.fluxTemp
    textures.fluxTemp = flux_swap
    
    encoder.endEncoding()
  }
  
  func executeStep(commandBuffer: MTLCommandBuffer, currentTime: Float) {
    if (resetField) {
      resetHeightField(commandBuffer: commandBuffer)
      resetField = false
    }
//    blurHeightField(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    erosionStep(commandBuffer: commandBuffer)
    recalculateNormals(commandBuffer: commandBuffer)
  }
}

