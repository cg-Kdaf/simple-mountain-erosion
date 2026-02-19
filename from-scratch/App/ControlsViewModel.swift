//
//  ControlsViewModel.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI
import Combine

@Observable
final class ControlsViewModel {
  // Camera controls
  var yaw: Double = 0.0
  var pitch: Double = 0.8
  var distance: Double = 250.0
  var lastDragPosition: CGPoint = .zero
  var isDragging: Bool = false
  var autoTurn: Bool = false
  var lastAutoTick: Date?
  
  // Renderer state
  var renderer: Renderer?
  var stats: Renderer.Stats?
  
  // HeightMap configuration
  var meshResolution: Double = 512
  var textureResolution: Double = 1024
  var meshSize: Float = 500.0
  
  // Erosion simulation
  var simulationPaused: Bool = true
  var heightMapUniforms: HeightMapUniforms = .init(
    deltaX: Float(500.0 / 1024.0),
    deltaY: Float(500.0 / 1024.0),
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
    velMult: 0.5,
    mountainNoiseFrequency: 5.0
  )
  
  // UI state
  var showControls: Bool = true
  var renderMode: Renderer.RenderMode = .raster
  var debugTextureMode: TextureOverlay = Shading
  var expandedStats: Bool = false
  var expandedLiveControls: Bool = false
  var expandedErosion: Bool = false
  var expandedHeightMap: Bool = false
  
  // MARK: - Camera Methods
  
  func handleScroll(_ delta: Double) {
    let sensitivity = 0.01
    distance -= delta * sensitivity
    distance = max(0.1, min(1000.0, distance))
    renderer?.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
  }
  
  func handleDragChanged(_ value: DragGesture.Value) {
    if !isDragging {
      isDragging = true
      lastDragPosition = value.location
      return
    }
    
    let delta = CGSize(
      width: value.location.x - lastDragPosition.x,
      height: value.location.y - lastDragPosition.y
    )
    lastDragPosition = value.location
    
    let sensitivityYaw = 0.003
    let sensitivityPitch = 0.003
    let newYaw = yaw + Double(delta.width) * sensitivityYaw
    let newPitch = pitch + Double(delta.height) * sensitivityPitch
    let clampedPitch = max(-1.4, min(1.4, newPitch))
    
    if yaw != newYaw { yaw = newYaw }
    if pitch != clampedPitch { pitch = clampedPitch }
  }
  
  func handleDragEnded() {
    isDragging = false
  }
  
  func updateAutoTurn(deltaTime: TimeInterval) {
    guard autoTurn, let renderer else {
      lastAutoTick = Date()
      return
    }
    
    let dt: Double
    if let last = lastAutoTick {
      dt = max(0, Date().timeIntervalSince(last))
    } else {
      dt = 1.0 / 60.0
    }
    lastAutoTick = Date()
    
    let speed: Double = 0.8 // radians per second
    yaw += dt * speed
    if yaw > .pi { yaw -= 2 * .pi } else if yaw < -.pi { yaw += 2 * .pi }
    renderer.setOrbit(yaw: yaw, pitch: pitch, distance: distance)
  }
  
  // MARK: - Erosion Controls
  
  func toggleSimulation() {
    simulationPaused.toggle()
    renderer?.setSimulationPaused(simulationPaused)
  }
  
  func addWater() {
    renderer?.applyUniformRain(amount: 5.0)
  }
  
  func updateErosionUniforms() {
    renderer?.updateErosionUniform(heightMapUniforms)
  }
  
  func resetErosionDefaults() {
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
      velMult: 0.5,
      mountainNoiseFrequency: 5.0
    )
    renderer?.updateErosionUniform(heightMapUniforms)
  }
  
  // MARK: - HeightMap Controls
  
  func applyResolution() {
    let meshTarget = UInt(meshResolution.rounded())
    let textureTarget = UInt(textureResolution.rounded())
    renderer?.updateResolutions(mesh: meshTarget, texture: textureTarget)
  }
  
  func resetHeightMap() {
    renderer?.heightField.resetHeightField()
  }
  
  func fitTo512() {
    meshResolution = 512
    textureResolution = 512
    applyResolution()
  }
  
  func toggleRenderMode() {
    renderMode = renderMode == .raytracing ? .raster : .raytracing
    renderer?.setRenderMode(renderMode)
  }
  
  func setDebugTextureMode(_ mode: TextureOverlay) {
    debugTextureMode = mode
    renderer?.setDebugTextureMode(mode)
  }
  
  func toggleAutoTurn() {
    autoTurn.toggle()
    lastAutoTick = nil
  }
  
  func reloadShaders() {
    renderer?.reloadShaders()
  }
}
