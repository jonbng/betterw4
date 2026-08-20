/**
 * create-tester-form.gs — BetterW4 TestFlight beta sign-up
 *
 * Builds the whole Google Form in one run, so the questions live in version control
 * rather than in a form somebody edited by hand and cannot reproduce.
 *
 * HOW TO RUN
 *   1. Go to https://script.google.com and create a new project.
 *   2. Replace the contents of Code.gs with this file.
 *   3. Run `createTesterForm`. Google will ask for authorisation the first time —
 *      it needs permission to create a Form and a Sheet in your Drive.
 *   4. The two URLs you need are printed to the execution log (View ▸ Logs).
 *
 * WHAT IT PRODUCES
 *   * A form, in five short sections, that walks a student from "what is this"
 *     to "I have TestFlight installed and here is my Apple Account".
 *   * A linked response spreadsheet. Its First name / Last name / Apple Account
 *     columns are deliberately separate and in that order, because that is the
 *     shape TestFlight's external-tester CSV import expects.
 *
 * THE ONE FIELD THAT MATTERS
 *   The Apple Account email. Everything else is nice to have. An invite sent to
 *   the wrong address is the single most common reason a tester never gets the
 *   build, and the failure is silent — they simply never receive anything. Hence
 *   an entire section explaining how to find it, and a confirmation question.
 */

// Change these two if you fork the beta for another cohort.
var FORM_TITLE = 'BetterW4 — TestFlight beta sign-up';
var SHEET_TITLE = 'BetterW4 — TestFlight testers';

/** Minimum iOS the app runs on. Must match IPHONEOS_DEPLOYMENT_TARGET. */
var MINIMUM_IOS = '18.5';

function createTesterForm() {
  var form = FormApp.create(FORM_TITLE);

  form.setDescription(
    'BetterW4 is a native iPhone and iPad app for W4 — your timetable, assessments, mail, ' +
    'attendance and grades, without the desktop website.\n\n' +
    'It is looking for students to try it before it goes on the App Store.\n\n' +
    'BetterW4 is unofficial. It is not made by, endorsed by or affiliated with UWC Red Cross ' +
    'Nordic. It has no server of its own: it talks to the college’s W4 and nothing else, and ' +
    'everything it knows stays on your phone.\n\n' +
    'This takes about three minutes.'
  );

  form.setProgressBarEnabled(true);
  form.setAllowResponseEdits(true);
  form.setLimitOneResponsePerUser(true);   // set false if testers lack Google accounts
  form.setCollectEmail(false);             // their Google address is NOT their Apple Account

  // ── 1. What you are signing up for ──────────────────────────────────────────
  form.addSectionHeaderItem()
    .setTitle('What you are signing up for')
    .setHelpText(
      'You will get the app early, through Apple’s TestFlight, and it will have bugs.\n\n' +
      'Be aware of one in particular: the parts of the app that read your timetable have only ' +
      'ever been tested against a holiday week with no lessons in it. Nobody has seen it run ' +
      'during a normal school week yet — that is exactly what this beta is for. Do not rely on ' +
      'it for a deadline or for knowing where to be. Keep using W4 for anything that matters ' +
      'until it has earned your trust.\n\n' +
      'Builds expire after 90 days, and the beta may end at any time.'
    );

  form.addMultipleChoiceItem()
    .setTitle('Are you happy to try a pre-release app, knowing it may be wrong or break?')
    .setChoiceValues(['Yes', 'No — I would rather wait for the App Store release'])
    .setRequired(true);

  // ── 2. About you ────────────────────────────────────────────────────────────
  form.addPageBreakItem()
    .setTitle('About you')
    .setHelpText('So we know who is testing and can spot gaps in coverage.');

  form.addTextItem()
    .setTitle('First name')
    .setRequired(true);

  form.addTextItem()
    .setTitle('Last name')
    .setRequired(true);

  form.addMultipleChoiceItem()
    .setTitle('Which year are you?')
    .setChoiceValues(['1st year', '2nd year', 'Staff', 'Other'])
    .setHelpText(
      'The app shows different things depending on your year, and some screens are built ' +
      'from guesses about what a real account looks like. Testers from both years matter.'
    )
    .setRequired(true);

  form.addMultipleChoiceItem()
    .setTitle('How would you like to test?')
    .setChoiceValues([
      'External tester — I just want the app (recommended)',
      'Internal tester — I help develop BetterW4 and need access to the developer account'
    ])
    .setHelpText(
      'Internal testing gives you a role in the Apple Developer account itself, so it is only ' +
      'for people working on the app. If you are not sure, pick the first one — you get exactly ' +
      'the same app either way.'
    )
    .setRequired(true);

  // ── 3. Your Apple Account ───────────────────────────────────────────────────
  form.addPageBreakItem()
    .setTitle('Your Apple Account')
    .setHelpText(
      'This is the important one, and it is the one people get wrong.\n\n' +
      'The invite goes to your Apple Account email. If you give us a different address — your ' +
      'school Google address, say, when your iPhone is signed in with a personal one — the ' +
      'invitation will not reach you, and nothing will tell you why.\n\n' +
      'HOW TO FIND IT, on the iPhone or iPad you will be testing on:\n' +
      '   1. Open Settings.\n' +
      '   2. Tap your name, at the very top.\n' +
      '   3. The email under your name is your Apple Account. That is the one we need.\n\n' +
      'You can also see it at appleid.apple.com after signing in.'
    );

  var appleEmail = form.addTextItem()
    .setTitle('Your Apple Account email')
    .setHelpText('Copy it exactly as it appears in Settings.')
    .setRequired(true);
  // No .setHelpText() on the validation builders — it is not part of TextValidationBuilder or
  // CheckboxValidationBuilder, and calling it throws at runtime. Google supplies its own error
  // text; the guidance that matters lives in the item's own help text above.
  appleEmail.setValidation(
    FormApp.createTextValidation()
      .requireTextIsEmail()
      .build()
  );

  form.addMultipleChoiceItem()
    .setTitle('Did you read that address off the device you will be testing on?')
    .setChoiceValues([
      'Yes — I opened Settings and checked',
      'No — I typed the address I usually use'
    ])
    .setHelpText(
      'Please check. It costs you thirty seconds and saves an invitation that silently ' +
      'goes nowhere.'
    )
    .setRequired(true);

  // ── 4. Your device ──────────────────────────────────────────────────────────
  form.addPageBreakItem()
    .setTitle('Your device')
    .setHelpText(
      'BetterW4 needs iOS ' + MINIMUM_IOS + ' or later. Check in Settings ▸ General ▸ About ▸ ' +
      'iOS Version. If you are on something older, update first — TestFlight will refuse to ' +
      'install the app otherwise.'
    );

  form.addMultipleChoiceItem()
    .setTitle('What will you test on?')
    .setChoiceValues(['iPhone', 'iPad', 'Both'])
    .setRequired(true);

  form.addTextItem()
    .setTitle('Which model?')
    .setHelpText('Settings ▸ General ▸ About ▸ Model Name. For example "iPhone 14" or "iPad Air".')
    .setRequired(true);

  form.addTextItem()
    .setTitle('Which iOS version?')
    .setHelpText('Settings ▸ General ▸ About ▸ iOS Version. For example "18.6".')
    .setRequired(true);

  form.addMultipleChoiceItem()
    .setTitle('Have you installed TestFlight from the App Store?')
    .setChoiceValues([
      'Yes',
      'Not yet — I will install it before accepting the invite'
    ])
    .setHelpText(
      'TestFlight is Apple’s free app for trying betas. Search the App Store for ' +
      '"TestFlight" and install it now — the invitation will not work without it.'
    )
    .setRequired(true);

  // ── 5. Feedback and consent ─────────────────────────────────────────────────
  form.addPageBreakItem()
    .setTitle('Feedback and permission')
    .setHelpText('Nearly done.');

  form.addParagraphTextItem()
    .setTitle('Anything you particularly want from a W4 app?')
    .setHelpText('Optional. What do you find slowest or most annoying about W4 today?')
    .setRequired(false);

  var consent = form.addCheckboxItem()
    .setTitle('Please confirm all three')
    .setChoiceValues([
      'I understand BetterW4 is unofficial and not made by UWC Red Cross Nordic.',
      'I understand it is a beta, that it may show wrong information, and that I should not ' +
        'rely on it for deadlines or lesson times.',
      'I am happy to be contacted about the beta, and for my name, email and device details ' +
        'to be used only to send me the app and to fix bugs.'
    ])
    .setRequired(true);
  consent.setValidation(
    FormApp.createCheckboxValidation()
      .requireSelectExactly(3)
      .build()
  );

  form.addSectionHeaderItem()
    .setTitle('About your data')
    .setHelpText(
      'Your name, email and device details are used only to send you the beta and to ' +
      'understand bug reports. They are not shared with anyone and are deleted when the beta ' +
      'ends. Ask at any time and they will be deleted sooner.\n\n' +
      'Your W4 password is never asked for here and never leaves your phone — the app sends it ' +
      'straight to the college’s own W4 server and nowhere else.'
    );

  form.setConfirmationMessage(
    'Thank you — you are on the list.\n\n' +
    'WHAT HAPPENS NEXT\n' +
    '   1. You will get an email from TestFlight, to the Apple Account address you gave.\n' +
    '   2. Open it on your iPhone or iPad and tap "View in TestFlight".\n' +
    '   3. Install BetterW4 from TestFlight, then open it and sign in with your W4 account.\n\n' +
    'Not sure yet? Tap "Try demo" on the sign-in screen to look around with sample data, ' +
    'without an account.\n\n' +
    'FOUND A BUG?\n' +
    'Take a screenshot, then send it straight from TestFlight — screenshot, tap the preview, ' +
    'then Share ▸ TestFlight. Or press and hold the app in TestFlight and choose "Send ' +
    'Beta Feedback". Say what you expected and what happened; a screenshot of the wrong ' +
    'screen is worth more than a description of it.\n\n' +
    'If the invite has not arrived within a day, check your junk folder — and check the ' +
    'address in Settings ▸ (your name) actually matches what you gave us.'
  );

  // A linked sheet, with the columns already in TestFlight's CSV import order.
  var sheet = SpreadsheetApp.create(SHEET_TITLE);
  form.setDestination(FormApp.DestinationType.SPREADSHEET, sheet.getId());

  Logger.log('Form (edit):    ' + form.getEditUrl());
  Logger.log('Form (share):   ' + form.getPublishedUrl());
  Logger.log('Responses:      ' + sheet.getUrl());

  return {
    editUrl: form.getEditUrl(),
    shareUrl: form.getPublishedUrl(),
    sheetUrl: sheet.getUrl()
  };
}
