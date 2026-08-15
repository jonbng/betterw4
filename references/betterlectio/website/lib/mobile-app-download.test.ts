import assert from "node:assert/strict"
import { describe, test } from "node:test"

import {
  isValidStudentId,
  mobileAppTargetForUserAgent,
} from "./mobile-app-download"
import { DOWNLOAD_LINKS } from "./download-links"
import { detectPlatformFromSignals } from "./platform"

describe("mobile app download routing", () => {
  test("routes iPhone and iPad user agents to the App Store", () => {
    assert.equal(
      mobileAppTargetForUserAgent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
      ),
      DOWNLOAD_LINKS.ios,
    )
    assert.equal(
      mobileAppTargetForUserAgent(
        "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)",
      ),
      DOWNLOAD_LINKS.ios,
    )
  })

  test("routes Android to Google Play", () => {
    assert.equal(
      mobileAppTargetForUserAgent(
        "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36",
      ),
      DOWNLOAD_LINKS.android,
    )
  })

  test("routes desktop and unknown agents to the download chooser", () => {
    assert.equal(
      mobileAppTargetForUserAgent(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/18 Safari/605.1.15",
      ),
      "/download",
    )
    assert.equal(mobileAppTargetForUserAgent(""), "/download")
  })

  test("client signals still recognize desktop-mode iPadOS", () => {
    assert.equal(
      detectPlatformFromSignals(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15",
        "MacIntel",
        5,
      ),
      "ios",
    )
  })

  test("accepts only canonical Lectio student IDs", () => {
    assert.equal(isValidStudentId("123_Ab-c"), true)
    assert.equal(isValidStudentId(" student "), true)
    assert.equal(isValidStudentId("bad/id"), false)
    assert.equal(isValidStudentId(""), false)
    assert.equal(isValidStudentId("a".repeat(49)), false)
  })
})
