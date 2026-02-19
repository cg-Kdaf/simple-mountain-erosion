//
//  ContentView.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import SwiftUI
import Combine

struct ContentView: View {
  @State private var viewModel = ControlsViewModel()
  @State private var autoTimer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
  
  var body: some View {
    NavigationStack {
      ZStack(alignment: .topLeading) {
        LinearGradient(
          colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.12, green: 0.14, blue: 0.18)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
        .ignoresSafeArea()
        
        // Metal Rendering View
        MetalRTView(
          renderer: $viewModel.renderer,
          yaw: viewModel.yaw,
          pitch: viewModel.pitch,
          distance: viewModel.distance,
          onStats: { viewModel.stats = $0 },
          onScroll: { viewModel.handleScroll($0) }
        ) { mtkView in
          Renderer(
            metalKitView: mtkView,
            meshResolution: UInt(viewModel.meshResolution),
            textureResolution: UInt(viewModel.textureResolution),
            meshSize: $viewModel.meshSize,
            heightMapUniforms: viewModel.heightMapUniforms)!
        }
        .onChange(of: viewModel.renderMode) { _, newMode in
          viewModel.renderer?.setRenderMode(newMode)
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onEnded { _ in
              viewModel.handleDragEnded()
            }
            .onChanged { value in
              viewModel.handleDragChanged(value)
            }
        )
        .onReceive(autoTimer) { _ in
          viewModel.updateAutoTurn(deltaTime: 1.0/60.0)
        }
        
        // Controls Panel
        if viewModel.showControls {
          VStack(alignment: .leading, spacing: 10) {
            RenderModeControlsView(viewModel: $viewModel)
            
            StatsView(viewModel: $viewModel, isExpanded: $viewModel.expandedStats)
            
            ErosionControlsView(viewModel: $viewModel, isExpanded: $viewModel.expandedErosion)
            
            HeightMapControlsView(viewModel: $viewModel, isExpanded: $viewModel.expandedHeightMap)
          }
          .frame(maxWidth: 340)
          .padding([.top, .leading], 12)
        }
      }
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button(action: { 
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { 
              viewModel.showControls.toggle() 
            } 
          }) {
            Image(systemName: viewModel.showControls ? "rectangle.and.hand.point.up.left" : "rectangle")
          }
          .help(viewModel.showControls ? "Hide controls" : "Show controls")
        }
      }
    }
  }
}
