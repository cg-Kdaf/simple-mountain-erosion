//
//  ContentView.swift
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

import SwiftUI
import Combine
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

extension HeightMapUniforms: Equatable {
    public static func == (lhs: HeightMapUniforms, rhs: HeightMapUniforms) -> Bool {
        return lhs.deltaX == rhs.deltaX &&
               lhs.deltaY == rhs.deltaY &&
               lhs.dt == rhs.dt &&
               lhs.l_pipe == rhs.l_pipe &&
               lhs.gravity == rhs.gravity &&
               lhs.A_pipe == rhs.A_pipe &&
               lhs.Kc == rhs.Kc &&
               lhs.Ks == rhs.Ks &&
               lhs.Kd == rhs.Kd &&
               lhs.Ke == rhs.Ke &&
               lhs.talusScale == rhs.talusScale &&
               lhs.thermalStrength == rhs.thermalStrength &&
               lhs.advectMultiplier == rhs.advectMultiplier &&
               lhs.velAdvMag == rhs.velAdvMag &&
               lhs.velMult == rhs.velMult
    }
}

struct CollapsibleSection<Content: View>: View {
  let title: String
  let icon: String
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content
  
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
        HStack {
          Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.white)
          Spacer()
          Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      
      if isExpanded {
        Divider()
          .padding(.horizontal, 10)
        
        content()
          .padding(.vertical, 10)
          .padding(.horizontal, 10)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

struct ContentView: View {
  @State private var yaw: Double = 0.0
  @State private var pitch: Double = 0.8
  @State private var distance: Double = 250.0
  @State private var lastDragPosition: CGPoint = .zero
  @State private var isDragging: Bool = false
  @State private var renderer: Renderer?
  @State private var meshResolution: Double = 512
  @State private var textureResolution: Double = 1024
  @State private var meshSize: Float = 500.0
  @State private var stats: Renderer.Stats?
  @State private var showControls: Bool = true
  @State private var autoTurn: Bool = false
  @State private var lastAutoTick: Date?
  @State private var renderMode: Renderer.RenderMode = .raster
  @State private var heightMapUniforms: HeightMapUniforms = .init(deltaX: Float(500.0/1024.0),
                                                                  deltaY: Float(500.0/1024.0),
                                                                  dt: 0.012,
                                                                  l_pipe: 0.2,
                                                                  gravity: 9.81,
                                                                  A_pipe: 1.0,
                                                                  Kc: 0.5,
                                                                  Ks: 0.1,
                                                                  Kd: 0.1,
                                                                  Ke: 0.015,
                                                                  talusScale: 2.0,
                                                                  thermalStrength: 0.5,
                                                                  advectMultiplier: 1.0,
                                                                  velAdvMag: 0.1,
                                                                  velMult: 0.5)
  @State private var autoTimer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
  @State private var expandedStats: Bool = false
  @State private var expandedLiveControls: Bool = false
  @State private var expandedErosion: Bool = false
  @State private var expandedHeightMap: Bool = false
  @State private var simulationPaused: Bool = true

  var body: some View {
    NavigationStack {
      ZStack(alignment: .topLeading) {
        LinearGradient(
          colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.12, green: 0.14, blue: 0.18)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
        .ignoresSafeArea()
        
        MetalRTView(renderer: $renderer, yaw: yaw, pitch: pitch, distance: distance, onStats: { stats = $0 }, onScroll: { delta in
          let sensitivity = 0.01
          distance -= delta * sensitivity
          distance = max(0.1, min(250.0, distance))
          renderer?.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
        }) { mtkView in
          Renderer(metalKitView: mtkView,
                   meshResolution: UInt(meshResolution),
                   textureResolution: UInt(textureResolution),
                   meshSize: $meshSize,
                   heightMapUniforms: heightMapUniforms)!
        }
        .onChange(of: renderMode) { _, newMode in
          renderer?.setRenderMode(newMode)
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
          VStack(alignment: .leading, spacing: 10) {
            Button(renderMode == .raytracing ? "Switch to Raster" : "Switch to Ray Tracing") {
              renderMode = renderMode == .raytracing ? .raster : .raytracing
              renderer?.setRenderMode(renderMode)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            CollapsibleSection(title: "Stats", icon: "chart.bar", isExpanded: $expandedStats) {
              VStack(alignment: .leading, spacing: 4) {
                if let stats {
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
            
            CollapsibleSection(title: "Erosion Controls", icon: "water.waves.and.arrow.down", isExpanded: $expandedErosion) {
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                  Toggle(simulationPaused ? "Resume Simulation" : "Pause Simulation", isOn: $simulationPaused)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(simulationPaused ? .green : .orange)
                    .onChange(of: simulationPaused) { _, newValue in
                      renderer?.setSimulationPaused(newValue)
                    }
                }
                .padding(.bottom, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Slider(value: $heightMapUniforms.dt, in: 0.001...0.1, label: {
                      Text("Time step (dt)").font(.caption2)
                    })
                    Text(String(format: "%.4f", heightMapUniforms.dt)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.l_pipe, in: 0.05...2.0, label: {
                      Text("Pipe length (l_pipe)").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.l_pipe)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.gravity, in: 0.0...20.0, label: {
                      Text("Gravity").font(.caption2)
                    })
                    Text(String(format: "%.2f", heightMapUniforms.gravity)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.A_pipe, in: 0.1...5.0, label: {
                      Text("Pipe area (A_pipe)").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.A_pipe)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.Kc, in: 0.0...2.0, label: {
                      Text("Capacity (Kc)").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.Kc)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.Ks, in: 0.0...1.0, label: {
                      Text("Dissolving regolith (Ks)").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.Ks)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.Kd, in: 0.0...1.0, label: {
                      Text("Deposition (Kd)").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.Kd)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.Ke, in: 0.0...0.1, label: {
                      Text("Evaporation (Ke)").font(.caption2)
                    })
                    Text(String(format: "%.4f", heightMapUniforms.Ke)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.talusScale, in: 0.0...10.0, label: {
                      Text("Talus scale").font(.caption2)
                    })
                    Text(String(format: "%.2f", heightMapUniforms.talusScale)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.thermalStrength, in: 0.0...2.0, label: {
                      Text("Thermal strength").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.thermalStrength)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.advectMultiplier, in: 0.1...5.0, label: {
                      Text("Advection multiplier").font(.caption2)
                    })
                    Text(String(format: "%.2f", heightMapUniforms.advectMultiplier)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.velAdvMag, in: 0.0...1.0, label: {
                      Text("Velocity advection mag").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.velAdvMag)).monospacedDigit().font(.caption2)
                  }
                  
                  HStack {
                    Slider(value: $heightMapUniforms.velMult, in: 0.1...5.0, label: {
                      Text("Velocity multiplier").font(.caption2)
                    })
                    Text(String(format: "%.3f", heightMapUniforms.velMult)).monospacedDigit().font(.caption2)
                  }
                }
                
                Button("Reset Defaults") {
                  resetErosionDefaults()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
              }
              .onChange(of: heightMapUniforms) { _,newval in
                renderer?.updateErosionUniform(newval)
              }
            }
            
            CollapsibleSection(title: "HeightMap Controls", icon: "square.and.pencil", isExpanded: $expandedHeightMap) {
              VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text("Definition").font(.caption2)
                    Spacer()
                    Text("\(Int(meshResolution))").monospacedDigit().font(.caption2)
                  }
                  Slider(value: $meshResolution, in: 32...2048, step: 32)
                  
                  HStack {
                    Text("Scale").font(.caption2)
                    Spacer()
                    Text("\(Int(meshSize))").monospacedDigit().font(.caption2)
                  }
                  Slider(value: $meshSize, in: 1.0...1000.0)
                  
                  HStack {
                    Text("Texture size").font(.caption2)
                    Spacer()
                    Text("\(Int(textureResolution))").monospacedDigit().font(.caption2)
                  }
                  Slider(value: $textureResolution, in: 32...2048, step: 32)
                }
                
                HStack(spacing: 6) {
                  Button("Apply") { applyResolution() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(renderer == nil)
                  Button("Reset") { resetHeightMap() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(renderer == nil)
                  Button("Fit to 512") {
                    meshResolution = 512
                    textureResolution = 512
                    applyResolution()
                  }
                  .controlSize(.small)
                  .disabled(renderer == nil)
                  Button("Reload Shaders") { renderer?.reloadShaders() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                  Button(autoTurn ? "Stop Auto Camera Turn" : "Auto Turn Camera") {
                    autoTurn.toggle()
                    lastAutoTick = nil
                  }
                  .buttonStyle(.bordered)
                  .controlSize(.small)
                }
              }
            }
          }
          .frame(maxWidth: 340)
          .padding([.top, .leading], 12)
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
  
  private func resetErosionDefaults() {
    heightMapUniforms = HeightMapUniforms(
      deltaX: Float(meshSize / Float(textureResolution)),
      deltaY: Float(meshSize / Float(textureResolution)),
      dt: 0.012,
      l_pipe: 0.2,
      gravity: 9.81,
      A_pipe: 1.0,
      Kc: 0.5,
      Ks: 0.1,
      Kd: 0.1,
      Ke: 0.015,
      talusScale: 2.0,
      thermalStrength: 0.5,
      advectMultiplier: 1.0,
      velAdvMag: 0.1,
      velMult: 0.5
    )
    renderer?.updateErosionUniform(heightMapUniforms)
  }
  
  private func resetHeightMap() {
    renderer?.heightField.resetHeightField()
  }
}

#Preview {
    ContentView()
}
