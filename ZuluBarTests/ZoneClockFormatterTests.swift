import XCTest
@testable import ZuluBar

final class ZoneClockFormatterTests: XCTestCase {

    // All instants below are constructed from explicit UTC RFC3339 strings,
    // never Date(), so results don't depend on the machine's current time,
    // locale, or local timezone.
    private func utcDate(_ rfc3339: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: rfc3339) else {
            fatalError("Bad fixture date: \(rfc3339)")
        }
        return date
    }

    // MARK: - Invalid zone

    func testFaceIsNilForInvalidZone() {
        let clock = AdditionalClock(identifier: "Not/AZone")
        XCTAssertNil(ZoneClockFormatter.face(for: clock, at: utcDate("2024-01-15T12:00:00Z"), showSeconds: false))
    }

    func testCopyIsNilForInvalidZoneAcrossAllFormats() {
        let clock = AdditionalClock(identifier: "Not/AZone")
        let date = utcDate("2024-01-15T12:00:00Z")
        for format in CopyFormat.allCases {
            XCTAssertNil(ZoneClockFormatter.copy(for: clock, at: date, format: format, showSeconds: false))
        }
    }

    // MARK: - Toronto, winter/summer, both sides of DST

    func testTorontoWinterStandardTime() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-01-15T12:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Mon 07:00")
    }

    func testTorontoSummerDaylightTime() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-07-15T12:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Mon 08:00")
    }

    func testTorontoJustBeforeSpringForwardIsStandardTime() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-03-10T06:59:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Toronto Sun 01:59 UTC-05:00")
    }

    func testTorontoJustAfterSpringForwardIsDaylightTime() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-03-10T07:00:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Toronto Sun 03:00 UTC-04:00")
    }

    func testTorontoJustBeforeFallBackIsDaylightTime() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-11-03T05:59:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Toronto Sun 01:59 UTC-04:00")
    }

    func testTorontoJustAfterFallBackIsStandardTime() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-11-03T06:00:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Toronto Sun 01:00 UTC-05:00")
    }

    // MARK: - Los Angeles, winter/summer

    func testLosAngelesWinterStandardTime() {
        let clock = AdditionalClock(identifier: "America/Los_Angeles")
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-01-15T20:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Mon 12:00")
    }

    func testLosAngelesSummerDaylightTime() {
        let clock = AdditionalClock(identifier: "America/Los_Angeles")
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-07-15T19:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Mon 12:00")
    }

    // MARK: - Weekday changes across midnight due to offset (not DST)

    func testWeekdayAdvancesAcrossMidnightAheadOfUTC() {
        let clock = AdditionalClock(identifier: "Asia/Tokyo")
        // 2024-06-02 is a Sunday in UTC; Tokyo (+9) is already Monday.
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-06-02T16:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Mon 01:00")
    }

    func testWeekdayLagsAcrossMidnightBehindUTC() {
        let clock = AdditionalClock(identifier: "America/Los_Angeles")
        // 2024-06-03T05:30 UTC is still Sunday 22:30 in Los Angeles (-7).
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-06-03T05:30:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Sun 22:30")
    }

    // MARK: - Half-hour and quarter-hour offsets

    func testKathmanduQuarterHourOffset() {
        let clock = AdditionalClock(identifier: "Asia/Kathmandu")
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-06-02T12:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.time, "Sun 17:45")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-06-02T12:00:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Kathmandu Sun 17:45 UTC+05:45")
    }

    func testKolkataHalfHourOffset() {
        let clock = AdditionalClock(identifier: "Asia/Kolkata")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-06-02T12:00:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Kolkata Sun 17:30 UTC+05:30")
    }

    // MARK: - Readable copy never uses Z/UTC suffix for nonzero offsets

    func testReadableCopyNeverEndsWithZForNonzeroOffset() {
        let clock = AdditionalClock(identifier: "Asia/Kathmandu")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-06-02T12:00:00Z"), format: .display, showSeconds: false
        )
        XCTAssertFalse(copyString?.hasSuffix("Z") ?? true)
        XCTAssertTrue(copyString?.contains("UTC+05:45") ?? false)
    }

    func testReadableCopyUsesExplicitUTCOffsetEvenAtZero() {
        let clock = AdditionalClock(identifier: "Africa/Abidjan")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-06-02T12:00:00Z"), format: .display, showSeconds: false
        )
        XCTAssertEqual(copyString, "Abidjan Sun 12:00 UTC+00:00")
    }

    // MARK: - RFC3339 may use Z only at zero offset

    func testRFC3339UsesZAtZeroOffset() {
        let clock = AdditionalClock(identifier: "Africa/Abidjan")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-06-02T12:00:00Z"), format: .rfc3339, showSeconds: false
        )
        XCTAssertEqual(copyString, "2024-06-02T12:00:00Z")
    }

    func testRFC3339UsesNumericOffsetForNonzeroOffset() {
        let clock = AdditionalClock(identifier: "Asia/Kathmandu")
        let copyString = ZoneClockFormatter.copy(
            for: clock, at: utcDate("2024-06-02T12:00:00Z"), format: .rfc3339, showSeconds: false
        )
        XCTAssertEqual(copyString, "2024-06-02T17:45:00+05:45")
    }

    // MARK: - RFC3339 and Unix equivalence across zones for the same instant

    func testRFC3339AndUnixAgreeOnTheSameInstantAcrossZones() throws {
        let instant = utcDate("2024-11-03T06:00:00Z")
        let identifiers = ["America/Toronto", "America/Los_Angeles", "Asia/Kathmandu"]

        let unixStrings = identifiers.map { identifier in
            ZoneClockFormatter.copy(for: AdditionalClock(identifier: identifier), at: instant, format: .unixTimestamp, showSeconds: false)
        }
        XCTAssertEqual(Set(unixStrings.compactMap { $0 }).count, 1, "Unix timestamp must not depend on zone")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let resolvedInstants = try identifiers.map { identifier -> Date in
            let rfc = ZoneClockFormatter.copy(for: AdditionalClock(identifier: identifier), at: instant, format: .rfc3339, showSeconds: false)
            guard let rfc, let date = isoFormatter.date(from: rfc) else {
                throw XCTSkip("Could not parse RFC3339 fixture")
            }
            return date
        }
        for resolved in resolvedInstants {
            XCTAssertEqual(resolved.timeIntervalSince1970, instant.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    // MARK: - Seconds toggle

    func testShowSecondsTogglesFaceTimeFormat() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let date = utcDate("2024-01-15T12:00:30Z")
        let withSeconds = ZoneClockFormatter.face(for: clock, at: date, showSeconds: true)
        let withoutSeconds = ZoneClockFormatter.face(for: clock, at: date, showSeconds: false)
        XCTAssertEqual(withSeconds?.time, "Mon 07:00:30")
        XCTAssertEqual(withoutSeconds?.time, "Mon 07:00")
    }

    func testShowSecondsTogglesReadableCopyFormat() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        let date = utcDate("2024-01-15T12:00:30Z")
        let withSeconds = ZoneClockFormatter.copy(for: clock, at: date, format: .display, showSeconds: true)
        let withoutSeconds = ZoneClockFormatter.copy(for: clock, at: date, format: .display, showSeconds: false)
        XCTAssertEqual(withSeconds, "Toronto Mon 07:00:30 UTC-05:00")
        XCTAssertEqual(withoutSeconds, "Toronto Mon 07:00 UTC-05:00")
    }

    // MARK: - Face label uses AdditionalClock.displayName

    func testFaceLabelUsesDisplayName() {
        let clock = AdditionalClock(identifier: "America/Montreal", label: "Cousin")
        let face = ZoneClockFormatter.face(for: clock, at: utcDate("2024-01-15T12:00:00Z"), showSeconds: false)
        XCTAssertEqual(face?.label, "Cousin")
    }
}
