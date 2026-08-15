//
//  SafariWebExtensionHandler.swift
//  BetterLectioSafariExtension
//
//  Native entry point for the Safari Web Extension.
//
//  BetterLectio's web extension does not use native messaging — everything it
//  needs lives in the WXT bundle under Resources/. Safari nonetheless requires
//  a principal class (declared as NSExtensionPrincipalClass in Info.plist) and
//  refuses to load the extension without one, so this is a deliberate stub.
//
//  If native messaging is ever added, `browser.runtime.sendNativeMessage(...)`
//  from the extension arrives here as an NSExtensionItem under SFExtensionMessageKey.
//

import SafariServices
import os.log

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey]

        os_log(.default, "BetterLectio received native message: %@", String(describing: message))

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["echo": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
