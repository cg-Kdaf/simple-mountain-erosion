//
//  CollapsibleSection.swift
//  from-scratch
//
//  Created by Colin Marmond on 19/02/2026.
//

import SwiftUI

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
