//
//  ContentView.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import SwiftUI
import Combine
import MetalKit

@objc protocol OrbitControllable {
    @objc func setOrbit(yaw: Double, pitch: Double, distance: Double)
}

struct MetalRTView: NSViewRepresentable {
  @Binding var renderer: Renderer?
  var yaw: Double
  var pitch: Double
  var distance: Double
  var onStats: (Renderer.Stats) -> Void = { _ in }

  let makeRenderer: (MTKView) -> Renderer

  func makeNSView(context: Context) -> MTKView {
    let mtkView = MTKView()
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

struct ContentView: View {
    @State private var yaw: Double = 0.0
    @State private var pitch: Double = -0.5
    @State private var distance: Double = 3.0
    @State private var lastDragPosition: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var renderer: Renderer?
    @State private var meshResolution: Double = 1200
    @State private var textureResolution: Double = 1200
    @State private var stats: Renderer.Stats?
    @State private var showControls: Bool = true
    @State private var showHUD: Bool = true
    @State private var autoTurn: Bool = false
    @State private var lastAutoTick: Date?
    @State private var autoTimer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()

    var body: some View {
      NavigationStack {
        ZStack(alignment: .topLeading) {
          LinearGradient(
            colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.12, green: 0.14, blue: 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
          .ignoresSafeArea()
          
          MetalRTView(renderer: $renderer, yaw: yaw, pitch: pitch, distance: distance, onStats: { stats = $0 }) { mtkView in
            Renderer(metalKitView: mtkView)!
          }
          .gesture(
            DragGesture(minimumDistance: 0)
              .onEnded { _ in
                isDragging = false
              }
              .onChanged { value in
                if (!isDragging) {
                  isDragging = true
                  lastDragPosition = value.location
                  return
                }
                let delta = CGSize(width: value.location.x - lastDragPosition.x,
                                   height: value.location.y - lastDragPosition.y)
                lastDragPosition = value.location
                let sensitivityYaw = 0.003
                let sensitivityPitch = 0.003
                let newYaw = yaw + Double(delta.width) * sensitivityYaw
                let newPitch = pitch + Double(delta.height) * sensitivityPitch
                let clampedPitch = max(-1.4, min(1.4, newPitch))
                if yaw != newYaw { yaw = newYaw }
                if pitch != clampedPitch { pitch = clampedPitch }
              }
          )
          .onReceive(autoTimer) { date in
            guard autoTurn, let renderer else { lastAutoTick = date; return }
            let dt: Double
            if let last = lastAutoTick {
              dt = max(0, date.timeIntervalSince(last))
            } else {
              dt = 1.0 / 60.0
            }
            lastAutoTick = date
            let speed: Double = 0.8 // radians per second
            yaw += dt * speed
            if yaw > .pi { yaw -= 2 * .pi } else if yaw < -.pi { yaw += 2 * .pi }
            renderer.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
          }

          if showControls {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Metal Playground")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                  Text("Live shaders, grid + stats")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button(action: { showHUD.toggle() }) {
                  Image(systemName: showHUD ? "eye" : "eye.slash")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.white.opacity(0.08), in: Circle())
                }
              }

              if showHUD {
                GroupBox {
                  VStack(alignment: .leading, spacing: 8) {
                    if let stats {
                      Text("Device: \(stats.deviceName)").font(.subheadline)
                      Text(String(format: "FPS: %.1f", stats.fps)).font(.subheadline).monospacedDigit()
                      Text(String(format: "Frame: %.2f ms", stats.frameTimeMs)).font(.subheadline).monospacedDigit()
                      Text("Mesh: \(stats.meshResolution) x \(stats.meshResolution)").font(.subheadline)
                      Text("Texture: \(stats.textureResolution) x \(stats.textureResolution)").font(.subheadline)
                      Text("Drawable: \(Int(stats.drawableSize.width)) x \(Int(stats.drawableSize.height))").font(.subheadline)
                      Text("Shader reloads: \(stats.shaderReloads)").font(.subheadline)
                    } else {
                      Text("Waiting for stats...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(.automatic)
              }

              GroupBox(label: Label("Live Controls", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 10) {
                  VStack(alignment: .leading, spacing: 8) {
                    HStack {
                      Text("Mesh resolution")
                      Spacer()
                      Text("\(Int(meshResolution))").monospacedDigit()
                    }
                    Slider(value: $meshResolution, in: 32...2048, step: 32)

                    HStack {
                      Text("Texture resolution")
                      Spacer()
                      Text("\(Int(textureResolution))").monospacedDigit()
                    }
                    Slider(value: $textureResolution, in: 32...2048, step: 32)
                  }

                  HStack(spacing: 10) {
                    Button("Apply") { applyResolution() }
                      .buttonStyle(.borderedProminent)
                      .disabled(renderer == nil)
                    Button("Fit to 512") {
                      meshResolution = 512
                      textureResolution = 512
                      applyResolution()
                    }
                    .disabled(renderer == nil)
                  }
                  HStack(spacing: 8) {
                    Button("Reload Shaders") { renderer?.reloadShaders() }
                      .buttonStyle(.borderedProminent)
                    Button("Reset Camera") { resetCamera() }
                      .buttonStyle(.bordered)
                    Button("Reset HeightField") { renderer?.heightField.resetHeightField() }
                      .buttonStyle(.bordered)
                    Button(autoTurn ? "Stop Auto" : "Auto Turn") {
                      autoTurn.toggle()
                      lastAutoTick = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(renderer == nil)
                  }
                }
              }
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding([.top, .leading], 18)
          }
        }
        .toolbar {
          ToolbarItem(placement: .automatic) {
            Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showControls.toggle() } }) {
              Image(systemName: showControls ? "rectangle.and.hand.point.up.left" : "rectangle")
            }
            .help(showControls ? "Hide controls" : "Show controls")
          }
        }
      }
    }
  
    private func applyResolution() {
      let meshTarget = UInt(meshResolution.rounded())
      let textureTarget = UInt(textureResolution.rounded())
      renderer?.updateResolutions(mesh: meshTarget, texture: textureTarget)
    }
    
    private func resetCamera() {
      yaw = 0.0
      pitch = -0.5
      distance = 3.0
      renderer?.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
    }
}

#Preview {
    ContentView()
}
