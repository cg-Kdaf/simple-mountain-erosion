//
//  MetalRTView.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI
import MetalKit
import AppKit

@objc protocol OrbitControllable {
  @objc func setOrbit(yaw: Double, pitch: Double, distance: Double)
}

struct MetalRTView: NSViewRepresentable {
  @Binding var renderer: Renderer?
  var yaw: Double
  var pitch: Double
  var distance: Double
  var onStats: (Renderer.Stats) -> Void = { _ in }
  var onScroll: (Double) -> Void = { _ in }
  
  let makeRenderer: (MTKView) -> Renderer
  
  func makeNSView(context: Context) -> MTKView {
    class OrbitMTKView: MTKView {
      var onScroll: ((Double) -> Void)?
      override func scrollWheel(with event: NSEvent) {
        onScroll?(Double(event.scrollingDeltaY))
        super.scrollWheel(with: event)
      }
    }
    
    let mtkView = OrbitMTKView()
    mtkView.onScroll = onScroll
    mtkView.device = MTLCreateSystemDefaultDevice()
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.clearColor = MTLClearColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
    
    let rendererInstance = makeRenderer(mtkView)
    rendererInstance.onStats = onStats
    context.coordinator.renderer = rendererInstance
    // Defer state mutation to the next runloop to avoid changing SwiftUI state during view updates
    DispatchQueue.main.async {
      renderer = rendererInstance
    }
    rendererInstance.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
    mtkView.delegate = rendererInstance
    return mtkView
  }
  
  func updateNSView(_ nsView: MTKView, context: Context) {
    if let orbitable = context.coordinator.renderer {
      orbitable.onStats = onStats
      orbitable.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
    }
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }
  
  final class Coordinator {
    var renderer: Renderer?
  }
}
