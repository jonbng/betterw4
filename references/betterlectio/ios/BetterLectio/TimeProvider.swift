//
//  TimeProvider.swift
//  BetterLectio
//
//  Testing with different times:
//  1. Xcode → Product → Scheme → Edit Scheme…
//  2. Select "Run" → "Arguments" tab
//  3. Under "Environment Variables", click + and add:
//     Name:  SIMULATED_DATE
//     Value: 2025-02-21T14:30:00   (date + time, e.g. 8:10 AM = 08:10:00)
//  4. Run the app — schedule UI will behave as if it's that date/time
//  Omit the variable or remove it to use real time.
//

import Foundation

enum TimeProvider {
    /// Current date/time. Uses SIMULATED_DATE from environment when set (for testing).
    static var now: Date {
        guard let value = ProcessInfo.processInfo.environment["SIMULATED_DATE"] else {
            return Date()
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return Date()
    }
}
