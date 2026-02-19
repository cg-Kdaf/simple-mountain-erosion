//
//  StatsView.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI

struct StatsView: View {
  @Binding var viewModel: ControlsViewModel
  @Binding var isExpanded: Bool
  
  var body: some View {
    CollapsibleSection(title: "Stats", icon: "chart.bar", isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 4) {
        if let stats = viewModel.stats {
          Text("Device: \(stats.deviceName)").font(.caption)
          Text(String(format: "FPS: %.1f", stats.fps)).font(.caption).monospacedDigit()
          Text(String(format: "Frame: %.2f ms", stats.frameTimeMs)).font(.caption).monospacedDigit()
          Text("Mesh: \(stats.meshResolution) x \(stats.meshResolution)").font(.caption)
          Text("Texture: \(stats.textureResolution) x \(stats.textureResolution)").font(.caption)
          Text("Drawable: \(Int(stats.drawableSize.width)) x \(Int(stats.drawableSize.height))").font(.caption)
          Text("Shader reloads: \(stats.shaderReloads)").font(.caption)
        } else {
          Text("Waiting for stats...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
