export default defineBackground(() => {
  browser.runtime.onInstalled.addListener((details) => {
    console.log('[BetterW4] installed', details.reason, browser.runtime.getManifest().version);
  });

  browser.action.onClicked.addListener(async (tab) => {
    if (!tab.id) return;
    try {
      await browser.tabs.sendMessage(tab.id, { action: 'openSettings' });
    } catch {
      // Tab is not a W4 page, or the content script is not injected yet.
    }
  });
});
