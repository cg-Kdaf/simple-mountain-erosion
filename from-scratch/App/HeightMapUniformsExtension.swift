//
//  HeightMapUniformsExtension.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import Foundation

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
    lhs.velMult == rhs.velMult &&
    lhs.mountainNoiseFrequency == rhs.mountainNoiseFrequency
  }
}
