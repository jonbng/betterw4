//
//  TabBarSameTabReselectDetector.swift
//  BetterW4
//
//  Detects a tap on the already-selected tab bar item, which is the platform gesture for
//  "scroll this tab to the top" (and, on More, "pop to root").
//
//  SwiftUI has no API for it, so the coordinator borrows the hosting `UITabBarController`'s
//  delegate, forwards every message to whoever held it before, and calls back only when the
//  selected index did not change.
//

import SwiftUI
import UIKit

/// Calls `onReselect` when the user taps `tabIndex` while it is already selected.
///
/// The index defaults to the Absence tab, which is where the app first needed this, but any
/// tab can opt in by passing its own index — the tab order lives in `ContentView`.
struct TabBarSameTabReselectDetector: UIViewRepresentable {
    var tabIndex: Int = AuthenticatedTabIndex.absences
    var onReselect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tabIndex: tabIndex, onReselect: onReselect)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.tabIndex = tabIndex
        context.coordinator.onReselect = onReselect
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachIfNeeded()
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var tabIndex: Int
        var onReselect: () -> Void
        private weak var tabBarController: UITabBarController?
        private weak var forwardDelegate: UITabBarControllerDelegate?
        private var lastSelectedIndex: Int?
        private var didInstall = false

        init(tabIndex: Int, onReselect: @escaping () -> Void) {
            self.tabIndex = tabIndex
            self.onReselect = onReselect
        }

        func attachIfNeeded(from view: UIView) {
            guard let controller = view.nearestViewController()?.tabBarController else { return }
            if !didInstall || tabBarController !== controller {
                detachIfNeeded()
                tabBarController = controller
                forwardDelegate = controller.delegate as? UITabBarControllerDelegate
                lastSelectedIndex = controller.selectedIndex
                controller.delegate = self
                didInstall = true
            }
        }

        func detachIfNeeded() {
            guard let controller = tabBarController, didInstall else { return }
            if controller.delegate === self {
                controller.delegate = forwardDelegate
            }
            tabBarController = nil
            forwardDelegate = nil
            didInstall = false
            lastSelectedIndex = nil
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            forwardDelegate?.tabBarController?(tabBarController, didSelect: viewController)

            let index = tabBarController.selectedIndex
            if index == tabIndex, lastSelectedIndex == tabIndex {
                DispatchQueue.main.async { [onReselect] in
                    onReselect()
                }
            }
            lastSelectedIndex = index
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            forwardDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }
    }
}

private extension UIView {
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
