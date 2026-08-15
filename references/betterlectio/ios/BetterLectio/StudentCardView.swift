//
//  StudentCardView.swift
//  BetterLectio
//
//  Created by Antigravity on 14/03/2026.
//

import SwiftUI

struct StudentCardView: View {
    let student: Student

    @State private var isFlipped = false
    @State private var rotation: Double = 0
    @State private var birthdayDisplay: String?

    private var studentPictureURL: URL? {
        guard let pictureId = student.pictureId else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(student.gymId)/GetImage.aspx?pictureid=\(pictureId)&fullsize=1")
    }

    private var qrCodeURLString: String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return "https://www.lectio.dk/lectio/\(student.gymId)/GetImage.aspx?type=studiekortqr&studentid=\(student.studentId)&time=\(timestamp)"
    }

    private var birthdayCacheKey: String {
        "lectio.studentCard.birthday.\(student.studentId)_\(student.gymId)"
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // The Card
                ZStack {
                    // Physical Card Background
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 0.5)
                        )
                    
                    if !isFlipped {
                        frontSide
                            .transition(.opacity)
                    } else {
                        backSide
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    }
                }
                .aspectRatio(0.63, contentMode: .fit) // Portrait Card Aspect Ratio
                .padding(.horizontal, 48)
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        isFlipped.toggle()
                        rotation += 180
                    }
                }
                
                VStack(spacing: 8) {
                    Text(isFlipped ? "Tryk på kortet for at se forside" : "Tryk på kortet for at se QR-kode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if isFlipped {
                        Image(systemName: "arrow.left.and.right.circle.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 24))
                    } else {
                        Image(systemName: "qrcode")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 24))
                    }
                }
                
                Spacer()
                
                // Instruction Text
                VStack(spacing: 12) {
                    Label("Vis dette kort ved studiekontrol", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Studiekort")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if birthdayDisplay == nil {
                birthdayDisplay = UserDefaults.standard.string(forKey: birthdayCacheKey)
            }
            await refreshBirthday()
        }
    }

    private func refreshBirthday() async {
        guard !student.isDemo,
              let credentials = KeychainManager.shared.loadCredentials(for: student.studentId) else { return }
        do {
            let birthday = try await LectioHTTPClient().fetchDigitalStudentCardBirthday(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId
            )
            if let birthday {
                UserDefaults.standard.set(birthday, forKey: birthdayCacheKey)
                birthdayDisplay = birthday
            }
        } catch {
            print("⚠️ Failed to fetch digital student card: \(error)")
        }
    }

    // MARK: - Front Side
    
    private var frontSide: some View {
        VStack(spacing: 0) {
            // Top: Profile Picture
            RateLimitedAvatarImage(url: studentPictureURL, size: 140, clipsToCircle: false) {
                Rectangle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
            .padding(.top, 40)
            
            // Middle: Details
            VStack(spacing: 8) {
                Text("STUDIEKORT")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(1.5)
                    .padding(.bottom, 8)
                
                Text(student.name ?? "Elev Navn")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(student.schoolName ?? "Skole Navn")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let birthday = birthdayDisplay {
                    Text(birthday)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Bottom: ID and Class
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("ELEV NR.")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                    Text(student.studentId)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                }
                
                if let classLabel = student.classLabel {
                    VStack(spacing: 4) {
                        Text("KLASSE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))
                        Text(classLabel)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Back Side
    
    private var backSide: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("STUDIEKONTROL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(1.5)
            
            if let qrURL = URL(string: qrCodeURLString) {
                RateLimitedAvatarImage(url: qrURL, size: 200, clipsToCircle: false) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 200, height: 200)
                        .overlay(ProgressView())
                }
                .padding(16)
                .background(Color.white)
            }
            
            Text(student.name ?? "")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

struct StudentCardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StudentCardView(student: Student(
                studentId: "72721770937",
                gymId: 94,
                name: "Elliott Friedrich",
                pictureId: "74096219865",
                classLabel: "1x",
                schoolName: "Sorø Akademis Skole"
            ))
        }
    }
}
