# BetterW4 — running the TestFlight beta

How to get the app onto students' phones before it is on the App Store, and what to do with what
comes back.

**Why this matters more than usual for this app.** `W4_PORT_PLAN.md` §0 is blunt about it: there are
five real captures of W4's markup, all taken from a **holiday week in August 2026 containing zero
lessons**. Mail, assessments, grades, trips, absence lists and *every lesson block* rest on fixtures
written by hand. The tests verify the parser, not W4.

So the first time a student opens BetterW4 during a normal school week is the first time anyone finds
out whether the timetable parser works on a real timetable. That is a fine thing to discover in a
beta and a terrible thing to discover in a release. **Run the beta in term time**, not over a break —
a holiday week would reproduce exactly the blind spot that created the problem.

---

## 1. Internal or external — pick deliberately

| | Internal | External |
|---|---|---|
| Who they are | **Members of your App Store Connect team** | Anyone with an email address |
| Cap | 100 people, 30 devices each | 10,000 |
| What they get access to | Your **developer account** — builds, and depending on role, app metadata, sales and reports | The app, and nothing else |
| Beta App Review | Not required | Required for the first build (~24–48h), then only for significant changes |
| How they are invited | Must accept an App Store Connect invitation | Email, or a public link |
| Build availability | Immediately after processing | After Beta App Review passes |

**Students should be external testers.** Internal testing means adding each person to your Apple
Developer account with a role — that is an access grant, not a distribution channel, and it does not
scale past a handful. Keep internal for yourself and anyone actually writing code.

The sign-up form covers both and asks testers which they are; the answer for almost everyone is
external.

---

## 2. Collect the testers

`ios/scripts/create-tester-form.gs` builds the sign-up form. Paste it into a new project at
[script.google.com](https://script.google.com), run `createTesterForm`, and read the three URLs out
of the execution log.

The form exists mostly to get **one field** right: the tester's **Apple Account email**. An invite
sent to the wrong address fails silently — the tester simply never receives anything, and there is no
bounce and no error anywhere in App Store Connect. So the form spends a whole section on finding it
in Settings ▸ (your name), and asks them to confirm they read it off the actual device.

The linked response sheet puts **First name · Last name · Apple Account** in that order on purpose:
it is the column order TestFlight's CSV importer expects, so adding a batch of testers is an export
and an upload rather than a typing exercise.

---

## 3. Prerequisite: a build App Store Connect will accept

Nothing below works until a build has been uploaded and finished processing, and that is currently
blocked — see [`../../IOSGuide.md`](../../IOSGuide.md). Apple rejects the current toolchain:

> SDK version issue. This app was built with the iOS 18.5 SDK. All iOS and iPadOS apps must be
> built with the iOS 26 SDK or later, included in Xcode 26 or later.

Xcode 26 needs macOS Sequoia 15.6 (for Xcode 26.0–26.3) or macOS Tahoe 26.2 (for 26.4.1+).

---

## 4. Add internal testers

1. **App Store Connect ▸ Users and Access ▸ +** — invite them by Apple Account email.
2. Give the **least role that works**. *Developer* can upload and see builds. *Customer Support* and
   *Marketing* cannot upload. Avoid *Admin* and *Account Holder*.
3. They accept the invitation by email.
4. **Your app ▸ TestFlight ▸ Internal Testing ▸** create a group, add them, and pick which builds it
   receives (or enable automatic distribution).

Builds reach internal testers as soon as processing finishes — no review.

---

## 5. Add external testers

1. **Your app ▸ TestFlight ▸ External Testing ▸ +** — create a group, e.g. *Students, term 1*.
2. Add testers by **Import from CSV** using the response sheet's first three columns, or paste emails
   in directly.
3. Attach a build to the group.
4. Fill in **Test Information** — this is what Beta App Review reads:
   - **Beta App Description** — what to try. Point at the timetable and assessments specifically,
     since those are the surfaces that need real-world exposure.
   - **Feedback email** — where TestFlight feedback lands.
   - **Sign-in required** — leave unchecked, and paste the demo-mode note from
     [`RELEASE.md`](RELEASE.md) §1. Beta App Review needs to get into the app the same way App Review
     does, and for the same reason you must not hand over a real student's W4 account.
5. Submit for Beta App Review. First build only, typically 24–48 hours.

**Public link.** Once a group is approved you can enable a public link — anyone with the URL joins,
up to a cap you set. Convenient for a whole year group; it also means the link can be forwarded
outside the college, so set the cap deliberately and treat it as public.

---

## 6. What testers should send back

TestFlight has built-in feedback and it is much better than a message:

- **Screenshot feedback** — take a screenshot, tap the preview, **Share ▸ TestFlight**. The
  screenshot arrives with the device, iOS version and build attached.
- **From the app's TestFlight page** — press and hold the app, **Send Beta Feedback**.
- **Crashes** are collected automatically and appear under **TestFlight ▸ Crashes**, symbolicated.
  This is the only crash reporting the app has, by design — there is no third-party SDK in it.

Feedback appears in **App Store Connect ▸ your app ▸ TestFlight ▸ Feedback**.

Ask specifically for **a screenshot of anything that looks wrong on the timetable**. A screenshot of
a mangled lesson block is worth more than any description, because it is the markup shape nobody has
ever captured. If a block renders wrongly, that is a fixture the project does not have.

---

## 7. Housekeeping

- **Builds expire after 90 days.** Upload a fresh one before then or testers lose access.
- **Bump the build number on every upload.** `CURRENT_PROJECT_VERSION` must be unique per version
  string; `MARKETING_VERSION` only changes when the public version does.
- **Screenshots of the app for the store must come from demo mode.** Same rule as App Review — the
  timetable, mail list and directory all show real students' names at a 200-person college.
- **Delete tester data when the beta ends.** The form promises this. Testers in Norway, GDPR applies,
  and the promise is cheap to keep.
