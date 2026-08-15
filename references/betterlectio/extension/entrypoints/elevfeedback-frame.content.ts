import {
  ELEVFEEDBACK_FRAME_NAME,
  hideElevfeedbackChrome,
  injectElevfeedbackFrameStyles,
  parentPrefersDark,
  relocateElevfeedbackNytButtons,
} from "@/lib/elevfeedback-frame";

/**
 * Runs in the Elevfeedback editor iframe only (`window.name` survives Gem/Nyt
 * postbacks). Injects chrome-hiding CSS at document_start so Lectio's master
 * menu / subnav never paint. Do not use srcdoc — CKEditor and ASP.NET save
 * need the live Lectio document.
 */
export default defineContentScript({
  matches: ["*://*.lectio.dk/*"],
  allFrames: true,
  runAt: "document_start",
  main() {
    if (window.name !== ELEVFEEDBACK_FRAME_NAME) return;

    injectElevfeedbackFrameStyles(document, parentPrefersDark());

    let scheduled = false;
    const strip = () => {
      scheduled = false;
      relocateElevfeedbackNytButtons(document);
      hideElevfeedbackChrome(document);
    };
    const observer = new MutationObserver(() => {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(strip);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    strip();
  },
});
