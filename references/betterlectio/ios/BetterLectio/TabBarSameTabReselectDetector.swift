//
//  TabBarSameTabReselectDetector.swift
//  BetterLectio
//
//  Detects when the user taps the already-selected tab bar item (scroll-to-top).
//  Tab index must match the Lektier tab order in ContentView's TabView.
//

import SwiftUI
import UIKit

/// Zero-based index of the Lektier tab in `ContentView`’s `TabView`.
private enum LektierTabBarIndex {
    static let value = 2
}

/// Calls `onReselect` when the user taps the Lektier tab while it is already selected.
struct TabBarSameTabReselectDetector: UIViewRepresentable {
    var onReselect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onReselect = onReselect
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachIfNeeded()
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: () -> Void
        private weak var tabBarController: UITabBarController?
        private weak var forwardDelegate: UITabBarControllerDelegate?
        private var lastSelectedIndex: Int?
        private var didInstall = false

        init(onReselect: @escaping () -> Void) {
            self.onReselect = onReselect
        }

        func attachIfNeeded(from view: UIView) {
            guard let tbc = view.nearestViewController()?.tabBarController else { return }
            if !didInstall || tabBarController !== tbc {
                detachIfNeeded()
                tabBarController = tbc
                forwardDelegate = tbc.delegate as? UITabBarControllerDelegate
                lastSelectedIndex = tbc.selectedIndex
                tbc.delegate = self
                didInstall = true
            }
        }

        func detachIfNeeded() {
            guard let tbc = tabBarController, didInstall else { return }
            if tbc.delegate === self {
                tbc.delegate = forwardDelegate
            }
            tabBarController = nil
            forwardDelegate = nil
            didInstall = false
            lastSelectedIndex = nil
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            forwardDelegate?.tabBarController?(tabBarController, didSelect: viewController)

            let idx = tabBarController.selectedIndex
            let lektierIndex = LektierTabBarIndex.value
            if idx == lektierIndex, lastSelectedIndex == lektierIndex {
                DispatchQueue.main.async { [onReselect] in
                    onReselect()
                }
            }
            lastSelectedIndex = idx
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            forwardDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }
    }
}

private extension UIView {
    func nearestViewController() -> UIViewController? {
        var r: UIResponder? = self
        while let rr = r {
            if let vc = rr as? UIViewController { return vc }
            r = rr.next
        }
        return nil
    }
}
