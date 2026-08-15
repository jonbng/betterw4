# Referral App Clip rollout

The referral App Clip is code-complete but only becomes invocable after its signing and App Store Connect setup is published.

1. Register `dk.echolabs.betterlectio.app.Clip` as an App Clip child of `dk.echolabs.betterlectio.app` for team `9ULRK8DH95`.
2. Enable Associated Domains and the shared App Group `group.dk.echolabs.betterlectio.app.referral` for both identifiers.
3. Create the default App Clip experience for `https://betterlectio.dk/r/` and use the Danish invitation copy/artwork.
4. Deploy the website AASA routes and confirm that `https://betterlectio.dk/.well-known/apple-app-site-association` returns JSON directly with no redirect.
5. Deploy `referral-click`, `referral-finalize`, `profile-picture-submit`, and the new database migration before releasing the iOS build.
6. Validate the real tokenless invocation `https://betterlectio.dk/r/123`: the App Clip must create the click token itself before showing the install action. Also test a pre-tokenized URL and confirm the token is server-validated before persistence.

Attribution tokens expire after seven days. The first valid token stored for an installation wins and the full app removes it only after a definitive finalization response.
