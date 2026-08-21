//
//  ScheduleDaySkeleton.swift
//  BetterW4
//
//  Placeholder for a timetable day while W4 is still answering. Used by the
//  signed-in student's pager and by another person's schedule on a profile.
//

import SwiftUI

struct ScheduleDaySkeleton: View {
    @State private var pulse = false

    private let heights: [CGFloat] = [52, 88, 40, 72, 56]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 36, height: 12)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(pulse ? 0.55 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Loading timetable")
    }
}
