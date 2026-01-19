import MetalKit

final class HeightField {
  let device: MTLDevice
  private(set) var displacementTexture: MTLTexture
  private(set) var normalTexture: MTLTexture
  private var displaceTexturePipelineState: MTLComputePipelineState?
  private var resetHeightFieldPipelineState: MTLComputePipelineState?
  private var recalculateNormalTexturePipelineState: MTLComputePipelineState?
  private var progressiveBlurPipelineState: MTLComputePipelineState?
  private var resetField: Bool = true
  private(set) var textureResolution: Int

  init(device: MTLDevice, textureResolution: Int, library: MTLLibrary? = nil) {
    self.device = device
    self.textureResolution = textureResolution

    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float,
      width: textureResolution,
      height: textureResolution,
      mipmapped: false)
    texDesc.usage = [.shaderRead, .shaderWrite]
    displacementTexture = device.makeTexture(descriptor: texDesc)!

    let normalDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: textureResolution,
      height: textureResolution,
      mipmapped: false)
    normalDesc.usage = [.shaderRead, .shaderWrite]
    normalTexture = device.makeTexture(descriptor: normalDesc)!

    if let lib = library {
      buildPipelines(library: lib)
    } else if let defaultLib = device.makeDefaultLibrary() {
      buildPipelines(library: defaultLib)
    }
  }

  func buildPipelines(library: MTLLibrary) {
    if let shaderFn = library.makeFunction(name: "compute_texture") {
      displaceTexturePipelineState = try? device.makeComputePipelineState(function: shaderFn)
    }
    if let shaderFn = library.makeFunction(name: "recalculate_normals") {
      recalculateNormalTexturePipelineState = try? device.makeComputePipelineState(function: shaderFn)
    }
    if let shaderFn = library.makeFunction(name: "reset_texture") {
      resetHeightFieldPipelineState = try? device.makeComputePipelineState(function: shaderFn)
    }
    if let shaderFn = library.makeFunction(name: "progressive_blur") {
      progressiveBlurPipelineState = try? device.makeComputePipelineState(function: shaderFn)
    }
  }

  func resize(to newResolution: Int) {
    guard newResolution != textureResolution else { return }
    textureResolution = newResolution
    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float,
      width: newResolution,
      height: newResolution,
      mipmapped: false)
    texDesc.usage = [.shaderRead, .shaderWrite]
    displacementTexture = device.makeTexture(descriptor: texDesc)!

    let normalDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: newResolution,
      height: newResolution,
      mipmapped: false)
    normalDesc.usage = [.shaderRead, .shaderWrite]
    normalTexture = device.makeTexture(descriptor: normalDesc)!
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
    encoder.setComputePipelineState(resetHeightFieldPipelineState!)
    encoder.setTexture(displacementTexture, index: 0)

    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: resetHeightFieldPipelineState!)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func blurHeightField(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
  
    encoder.label = "Progressive Blur Height Field Pass"
    encoder.setComputePipelineState(progressiveBlurPipelineState!)
    encoder.setTexture(displacementTexture, index: 0)

    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: progressiveBlurPipelineState!)
    
    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func liveAnimation(commandBuffer: MTLCommandBuffer, currentTime: Float) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    var currentTime = currentTime
    
    encoder.label = "Live animation Texture Pass"
    encoder.setComputePipelineState(displaceTexturePipelineState!)
    encoder.setTexture(displacementTexture, index: 0)
    encoder.setBytes(&currentTime,
                     length: MemoryLayout<Float>.size,
                     index: 0)

    let (threadsPerGrid, threadsPerThreadgroup) = createDisplatchGrid(pipelineState: displaceTexturePipelineState!)

    encoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func recalculateNormals(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder()
    else { fatalError() }
    
    encoder.label = "Normal Texture Recalculation Pass"
    encoder.setComputePipelineState(recalculateNormalTexturePipelineState!)
    encoder.setTexture(displacementTexture, index: 0)
    encoder.setTexture(normalTexture, index: 1)

    let (threadsPerGrid, threadsPerThreadgroup) =
      createDisplatchGrid(pipelineState: recalculateNormalTexturePipelineState!)

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
