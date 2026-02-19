//
//  RenderModeControlsView.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI

struct RenderModeControlsView: View {
  @Binding var viewModel: ControlsViewModel
  
  var body: some View {
    Button(viewModel.renderMode == .raytracing ? "Switch to Raster" : "Switch to Ray Tracing") {
      viewModel.toggleRenderMode()
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.small)
  }
}
