//
//  ContentView.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import SwiftUI
import MetalKit


struct MetalRTView: NSViewRepresentable {
  let makeRenderer: (MTKView) -> Renderer

  func makeNSView(context: Context) -> MTKView {
    let mtkView = MTKView()
    mtkView.device = MTLCreateSystemDefaultDevice()
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    
    
    context.coordinator.renderer = makeRenderer(mtkView)
    mtkView.delegate = context.coordinator.renderer
    return mtkView
  }
  
  func updateNSView(_ nsView: MTKView, context: Context) {
    return
  }
  
  func makeCoordinator() -> Coordinator {
      Coordinator()
  }

  final class Coordinator {
      var renderer: Renderer?
  }
}

struct ContentView: View {
    var body: some View {
      NavigationStack {
        MetalRTView { mtkView in
          Renderer(metalKitView: mtkView)!
        }
      }
    }
}

#Preview {
    ContentView()
}
