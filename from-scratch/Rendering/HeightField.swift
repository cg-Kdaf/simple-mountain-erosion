import MetalKit

struct HeightFieldTextures {
  var displacement: MTLTexture
  var normal: MTLTexture
}

struct HeightFieldPipelineStates {
  var displace: MTLComputePipelineState
  var reset: MTLComputePipelineState
  var recalculateNormals: MTLComputePipelineState
  var progressiveBlur: MTLComputePipelineState
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

  init(device: MTLDevice, textureResolution: Int, library: MTLLibrary? = nil) {
    self.device = device
    self.textureResolution = textureResolution
    textures = HeightField.createTextures(device: device, resolution: textureResolution)

    if let lib = library {
      pipelineStates = try! HeightField.buildPipelines(device: device, library: lib)
    } else {
      let defaultLib = device.makeDefaultLibrary()!
      pipelineStates = try! HeightField.buildPipelines(device: device, library: defaultLib)
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
    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float,
      width: resolution,
      height: resolution,
      mipmapped: false)
    texDesc.usage = [.shaderRead, .shaderWrite]
    let displacement = device.makeTexture(descriptor: texDesc)!

    let normalDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: resolution,
      height: resolution,
      mipmapped: false)
    normalDesc.usage = [.shaderRead, .shaderWrite]
    let normal = device.makeTexture(descriptor: normalDesc)!
    return HeightFieldTextures(displacement: displacement, normal: normal)
  }

  static private func buildPipelines(device: MTLDevice, library: MTLLibrary) throws -> HeightFieldPipelineStates {
    let displace = try HeightField.loadShader(device: device, library: library, shader_name: "live_animation_heightmap")
    let recalculateNormals = try HeightField.loadShader(device: device, library: library, shader_name: "recalculate_normals")
    let reset = try HeightField.loadShader(device: device, library: library, shader_name: "reset_heightmap")
    let progressiveBlur = try HeightField.loadShader(device: device, library: library, shader_name: "progressive_blur")
    return HeightFieldPipelineStates(
      displace: displace,
      reset: reset,
      recalculateNormals: recalculateNormals,
      progressiveBlur: progressiveBlur)
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
    encoder.setTexture(textures.displacement, index: 0)

    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: pipelineStates.reset)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func blurHeightField(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
  
    encoder.label = "Progressive Blur Height Field Pass"
    encoder.setComputePipelineState(pipelineStates.progressiveBlur)
    encoder.setTexture(textures.displacement, index: 0)

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
    encoder.setTexture(textures.displacement, index: 0)
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
    encoder.setTexture(textures.displacement, index: 0)
    encoder.setTexture(textures.normal, index: 1)

    let (threadsPerGrid, threadsPerThreadgroup) =
      createDisplatchGrid(pipelineState: pipelineStates.recalculateNormals)

    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  func executeStep(commandBuffer: MTLCommandBuffer, currentTime: Float) {
    if (resetField) {
      resetHeightField(commandBuffer: commandBuffer)
      resetField = false
    }
    blurHeightField(commandBuffer: commandBuffer)
    recalculateNormals(commandBuffer: commandBuffer)
  }
}
