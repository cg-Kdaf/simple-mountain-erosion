//
//  ContentView.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import SwiftUI
import MetalKit

@objc protocol OrbitControllable {
    @objc func setOrbit(yaw: Double, pitch: Double, distance: Double)
}

struct MetalRTView: NSViewRepresentable {
  var yaw: Double
  var pitch: Double
  var distance: Double

  let makeRenderer: (MTKView) -> Renderer

  func makeNSView(context: Context) -> MTKView {
    let mtkView = MTKView()
    mtkView.device = MTLCreateSystemDefaultDevice()
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    
    
    context.coordinator.renderer = makeRenderer(mtkView)
    if let orbitable = context.coordinator.renderer {
      orbitable.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
    }
    mtkView.delegate = context.coordinator.renderer
    return mtkView
  }
  
  func updateNSView(_ nsView: MTKView, context: Context) {
    if let orbitable = context.coordinator.renderer {
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

struct ContentView: View {
    @State private var yaw: Double = 0.0
    @State private var pitch: Double = -0.5
    @State private var distance: Double = 3.0
    @State private var drag_start_position: CGPoint = .zero
    @State private var is_draging: Bool = false

    var body: some View {
      NavigationStack {
        MetalRTView(yaw: yaw, pitch: pitch, distance: distance) { mtkView in
          Renderer(metalKitView: mtkView)!
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onEnded { _ in
              is_draging = false
            }
            .onChanged { value in
              if (!is_draging) {
                is_draging = true
                drag_start_position = value.location
              }
              let delta = CGSize(width: value.location.x - drag_start_position.x, height: value.location.y - drag_start_position.y)
              let sensitivityYaw = 0.0005
              let sensitivityPitch = 0.0005
              let newYaw = yaw + Double(delta.width) * sensitivityYaw
              let newPitch = pitch + Double(delta.height) * sensitivityPitch
              // Clamp pitch to avoid flipping over the top
              let clampedPitch = max(-1.4, min(1.4, newPitch))
              if yaw != newYaw { yaw = newYaw }
              if pitch != clampedPitch { pitch = clampedPitch }
            }
        )
      }
    }
}

#Preview {
    ContentView()
}
