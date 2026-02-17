//
//  AccelerationStructureBuilder.swift
//  YourProjectName
//
//  Created by Colin Marmond on 2026-02-05.
//

import MetalKit
import MetalPerformanceShaders

final class AccelerationStructureBuilder {
  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  var scratchBuffer: MTLBuffer!
  var descriptor: MTLPrimitiveAccelerationStructureDescriptor!
  var accelerationStructure: MTLAccelerationStructure!
    
  init(device: MTLDevice, queue: MTLCommandQueue) {
    self.device = device
    self.commandQueue = queue
  }
  
  func buildAccelerationStructure(for geometries: [MTLAccelerationStructureGeometryDescriptor]) {
    descriptor = MTLPrimitiveAccelerationStructureDescriptor()
    descriptor.geometryDescriptors = geometries
    descriptor.usage = [.refit, .minimizeMemory]
    
    let sizes = device.accelerationStructureSizes(descriptor: descriptor)
    
    guard let accelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize) else {
      fatalError("Failed to create acceleration structure")
    }
    self.accelerationStructure = accelerationStructure
    
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
      fatalError("Failed to create command buffer or encoder")
    }
    
    scratchBuffer = device.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate)
    
    encoder.build(accelerationStructure: accelerationStructure,
                  descriptor: descriptor,
                  scratchBuffer: scratchBuffer,
                  scratchBufferOffset: 0)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
  
  func refit(commandBuffer: MTLCommandBuffer) {
    guard let asEncoder = commandBuffer.makeAccelerationStructureCommandEncoder() else { fatalError() }
    asEncoder.label = "Refit Pass"

    asEncoder.refit(sourceAccelerationStructure: accelerationStructure,
                    descriptor: descriptor,
                    destinationAccelerationStructure: accelerationStructure,
                    scratchBuffer: scratchBuffer,
                    scratchBufferOffset: 0)

    asEncoder.endEncoding()
  }
}
