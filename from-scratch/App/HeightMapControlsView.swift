//
//  HeightMapControlsView.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI

struct HeightMapControlsView: View {
  @Binding var viewModel: ControlsViewModel
  @Binding var isExpanded: Bool
  
  var body: some View {
    CollapsibleSection(title: "HeightMap Controls", icon: "square.and.pencil", isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 6) {
        // Resolution Controls
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Definition").font(.caption2)
            Spacer()
            Text("\(Int(viewModel.meshResolution))").monospacedDigit().font(.caption2)
          }
          Slider(value: $viewModel.meshResolution, in: 32...2048, step: 32)
          
          HStack {
            Text("Scale").font(.caption2)
            Spacer()
            Text("\(Int(viewModel.meshSize))").monospacedDigit().font(.caption2)
          }
          Slider(value: $viewModel.meshSize, in: 1.0...1000.0)
          
          HStack {
            Text("Texture size").font(.caption2)
            Spacer()
            Text("\(Int(viewModel.textureResolution))").monospacedDigit().font(.caption2)
          }
          Slider(value: $viewModel.textureResolution, in: 32...2048, step: 32)
          
          HStack {
            Slider(value: $viewModel.heightMapUniforms.mountainNoiseFrequency, in: 0.1...20.0, label: {
              Text("Mountain noise frequency").font(.caption2)
            })
            Text(String(format: "%.2f", viewModel.heightMapUniforms.mountainNoiseFrequency)).monospacedDigit().font(.caption2)
          }
          .onChange(of: viewModel.heightMapUniforms) { _, newval in
            viewModel.updateErosionUniforms()
          }
        }
        
        // Action Buttons
        HStack(spacing: 6) {
          Button("Apply") { viewModel.applyResolution() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.renderer == nil)
          
          Button("Reset") { viewModel.resetHeightMap() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.renderer == nil)
          
          Button("Fit to 512") {
            viewModel.fitTo512()
          }
          .controlSize(.small)
          .disabled(viewModel.renderer == nil)
          
          Button("Reload Shaders") { viewModel.reloadShaders() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          
          Button(viewModel.autoTurn ? "Stop Auto Camera Turn" : "Auto Turn Camera") {
            viewModel.toggleAutoTurn()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
  }
}
