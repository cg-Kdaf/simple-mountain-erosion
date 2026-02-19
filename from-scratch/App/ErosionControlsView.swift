//
//  ErosionControlsView.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI

struct ErosionControlsView: View {
  @Binding var viewModel: ControlsViewModel
  @Binding var isExpanded: Bool
  
  var body: some View {
    CollapsibleSection(title: "Erosion Controls", icon: "water.waves.and.arrow.down", isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 6) {
        // Simulation Control
        HStack(spacing: 8) {
          Toggle(
            viewModel.simulationPaused ? "Resume Simulation" : "Pause Simulation",
            isOn: Binding(
              get: { !viewModel.simulationPaused },
              set: { viewModel.simulationPaused = !$0; viewModel.renderer?.setSimulationPaused(viewModel.simulationPaused) }
            )
          )
          .toggleStyle(.button)
          .controlSize(.small)
          .buttonStyle(.borderedProminent)
          .tint(viewModel.simulationPaused ? .green : .orange)
          
          Button("Add Water") {
            viewModel.addWater()
          }
          .controlSize(.small)
          .buttonStyle(.borderedProminent)
          .tint(.blue)
        }
        .padding(.bottom, 4)
        
        // Physics Parameters
        VStack(alignment: .leading, spacing: 4) {
          ErosionSliderRow(label: "Time step (dt)", value: $viewModel.heightMapUniforms.dt, range: 0.001...0.1, format: "%.4f")
          ErosionSliderRow(label: "Pipe length (l_pipe)", value: $viewModel.heightMapUniforms.l_pipe, range: 0.05...2.0, format: "%.3f")
          ErosionSliderRow(label: "Gravity", value: $viewModel.heightMapUniforms.gravity, range: 0.0...20.0, format: "%.2f")
          ErosionSliderRow(label: "Pipe area (A_pipe)", value: $viewModel.heightMapUniforms.A_pipe, range: 0.1...5.0, format: "%.3f")
          ErosionSliderRow(label: "Capacity (Kc)", value: $viewModel.heightMapUniforms.Kc, range: 0.0...2.0, format: "%.3f")
          ErosionSliderRow(label: "Dissolving regolith (Ks)", value: $viewModel.heightMapUniforms.Ks, range: 0.0...1.0, format: "%.3f")
          ErosionSliderRow(label: "Deposition (Kd)", value: $viewModel.heightMapUniforms.Kd, range: 0.0...1.0, format: "%.3f")
          ErosionSliderRow(label: "Evaporation (Ke)", value: $viewModel.heightMapUniforms.Ke, range: 0.0...0.1, format: "%.4f")
          ErosionSliderRow(label: "Talus scale", value: $viewModel.heightMapUniforms.talusScale, range: 0.0...10.0, format: "%.2f")
          ErosionSliderRow(label: "Thermal strength", value: $viewModel.heightMapUniforms.thermalStrength, range: 0.0...2.0, format: "%.3f")
          ErosionSliderRow(label: "Advection multiplier", value: $viewModel.heightMapUniforms.advectMultiplier, range: 0.1...5.0, format: "%.2f")
          ErosionSliderRow(label: "Velocity advection mag", value: $viewModel.heightMapUniforms.velAdvMag, range: 0.0...1.0, format: "%.3f")
          ErosionSliderRow(label: "Velocity multiplier", value: $viewModel.heightMapUniforms.velMult, range: 0.1...5.0, format: "%.3f")
        }
        
        // Debug Texture Mode
        VStack(alignment: .leading, spacing: 4) {
          Picker("Debug Texture", selection: Binding(
            get: { viewModel.debugTextureMode },
            set: { viewModel.setDebugTextureMode($0) }
          )) {
            Text("Shading").tag(Shading)
            Text("Velocity").tag(Velocity)
            Text("Terrain").tag(Terrain)
            Text("Flux").tag(Flux)
            Text("Normal").tag(Normal)
            Text("Slipperage").tag(Slipperage)
            Text("Sediment").tag(Sediment)
            Text("Slipperage Flux").tag(SlipperageFlux)
          }
          .pickerStyle(.radioGroup)
        }
        .font(.caption2)
        
        Button("Reset Defaults") {
          viewModel.resetErosionDefaults()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
      .onChange(of: viewModel.heightMapUniforms) { _, newval in
        viewModel.updateErosionUniforms()
      }
    }
  }
}

// MARK: - Helper Component

struct ErosionSliderRow: View {
  let label: String
  @Binding var value: Float
  let range: ClosedRange<Float>
  let format: String
  
  var body: some View {
    HStack {
      Slider(value: $value, in: range, label: {
        Text(label).font(.caption2)
      })
      Text(String(format: format, value)).monospacedDigit().font(.caption2)
    }
  }
}
