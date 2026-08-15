import SwiftUI

struct ScheduleHeaderView: View {
    let subjectName: String?
    let room: String?
    let minutesValue: Int?
    let progress: Double?
    var isUpcoming: Bool = false

    var body: some View {
        if let subjectName = subjectName,
           let minutesValue = minutesValue {
            // Active lesson or upcoming within 60 min
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(subjectName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Color.blue)
                            .lineLimit(1)

                        if let room = room {
                            Text("•")
                                .font(.title3)
                                .fontWeight(.light)
                                .foregroundColor(.secondary)

                            Text(room)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                    .layoutPriority(0)

                    Spacer(minLength: 8)

                    Text(isUpcoming ? "om \(minutesValue) min" : "\(minutesValue) min")
                        .layoutPriority(1)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                // Progress Bar (only for active lesson, not upcoming)
                if !isUpcoming, let progress = progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: 6)

                            Capsule()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(Color(UIColor.systemBackground))
        } else {
            // No active lesson and no upcoming within 60 min - show minimal header or nothing
            Color.clear
                .frame(height: 0)
        }
    }
}
