//
//  AccelerationStructureBuilder.swift
//  YourProjectName
//
//  Created by YourName on 2025-12-31.
//

import MetalKit
import MetalPerformanceShaders

/// Acceleration structure building utilities.

 // MARK: - AccelerationStructureBuilder

final class AccelerationStructureBuilder {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = queue
    }
    
    func buildAccelerationStructure(for geometries: [MTLAccelerationStructureGeometryDescriptor]) -> MTLAccelerationStructure {
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = geometries
        
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        
        guard let accelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize) else {
            fatalError("Failed to create acceleration structure")
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            fatalError("Failed to create command buffer or encoder")
        }
        
        encoder.build(accelerationStructure: accelerationStructure,
                      descriptor: descriptor,
                      scratchBuffer: device.makeBuffer(length: sizes.buildScratchBufferSize, options: [])!,
                      scratchBufferOffset: 0)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return accelerationStructure
    }
}
