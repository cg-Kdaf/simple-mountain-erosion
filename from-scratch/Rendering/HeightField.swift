import MetalKit

final class HeightField {
  let device: MTLDevice
  var displacementTexture: MTLTexture
  var normalTexture: MTLTexture
  var displacePipelineState: MTLComputePipelineState?
  var displaceTexturePipelineState: MTLComputePipelineState?
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
    if let displaceFn = library.makeFunction(name: "compute_vertices") {
      displacePipelineState = try? device.makeComputePipelineState(function: displaceFn)
    }
    if let displaceTexFn = library.makeFunction(name: "compute_texture") {
      displaceTexturePipelineState = try? device.makeComputePipelineState(function: displaceTexFn)
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
  }
}
