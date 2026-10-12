import AppKit
import CoreImage.CIFilterBuiltins
import HostCore
import SwiftUI

/// The first-run guide: walks a new user from a fresh Mac to a paired Remote, checking each step live
/// and doing the ones the Host can do itself.
struct SetupWindow: View {
    static let id = "setup"
    let host: Host
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private static let tailscaleDownload = URL(string: "https://tailscale.com/download/mac")!
    private static let tailscaleDNSSettings = URL(string: "https://login.tailscale.com/admin/dns")!
    private static let tailscaleIOS = "https://apps.apple.com/app/tailscale/id1470499037"

    var body: some View {
        let setup = host.setup
        VStack(alignment: .leading, spacing: 0) {
            header(setup)
                .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(Setup.Step.allCases.enumerated()), id: \.element) { index, step in
                        row(step, number: index + 1, setup: setup)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("You can open this again from the MyRemote menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(setup.complete ? "Done" : "Finish Later") { dismiss() }
                    .keyboardShortcut(setup.complete ? .defaultAction : .cancelAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 680)
        .onAppear(perform: Self.bringToFront)
        .task {
            while !Task.isCancelled {
                await host.refreshSetup()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// A menubar app opens its windows behind the active app's, and wherever the last screen was:
    /// put Setup in front, in the middle of the screen with the menu bar.
    private static func bringToFront() {
        NSApp.activate()
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) else { return }
            if let screen = NSScreen.screens.first {
                let area = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func header(_ setup: Setup) -> some View {
        HStack(spacing: 16) {
            // The app's icon (scripts/icons.swift), not an SF Symbol, which Apple's terms keep out of logos.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(setup.complete ? "MyRemote is ready" : "Set up MyRemote").font(.title2.bold())
                Text(setup.complete
                     ? "Open MyRemote from your iPhone's Home Screen to control this Mac."
                     : "Control this Mac from your iPhone over Tailscale, your own private network. A few steps, once.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func row(_ step: Setup.Step, number: Int, setup: Setup) -> some View {
        let state = setup.state(of: step)
        HStack(alignment: .top, spacing: 12) {
            badge(state, number: number)
            VStack(alignment: .leading, spacing: 8) {
                Text(title(step))
                    .font(.headline)
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                if state == .todo {
                    detail(step, setup: setup)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ state: Setup.State, number: Int) -> some View {
        ZStack {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .todo:
                Image(systemName: "\(number).circle.fill").foregroundStyle(.tint)
            case .waiting:
                Image(systemName: "\(number).circle").foregroundStyle(.tertiary)
            }
        }
        .font(.title2)
    }

    private func title(_ step: Setup.Step) -> String {
        switch step {
        case .installTailscale: "Install Tailscale on this Mac"
        case .logIn: "Log in to Tailscale"
        case .https: "Turn on MagicDNS and HTTPS Certificates"
        case .serve: "Give the Remote an HTTPS address"
        case .accessibility: "Let MyRemote control the pointer and keyboard"
        case .iPhoneTailscale: "Install Tailscale on your iPhone"
        case .pair: "Add the Remote to your iPhone and pair it"
        }
    }

    @ViewBuilder private func detail(_ step: Setup.Step, setup: Setup) -> some View {
        switch step {
        case .installTailscale:
            Text("Your iPhone reaches this Mac through Tailscale, a free private network between your own devices.")
            HStack {
                Button("Download Tailscale") { NSWorkspace.shared.open(Self.tailscaleDownload) }
                Text("then open it once.").foregroundStyle(.secondary)
            }
        case .logIn:
            Text(setup.tailscale == nil
                 ? "Open Tailscale and make sure it's running."
                 : "Open Tailscale from the menu bar, log in and connect. Use the same account on your iPhone.")
            Button("Open Tailscale") { Self.openTailscale() }
        case .https:
            let missing = [setup.tailscale?.magicDNS == true ? nil : "MagicDNS",
                           setup.tailscale?.httpsCertificates == true ? nil : "HTTPS Certificates"].compactMap { $0 }
            Text("In the Tailscale admin console's DNS page, enable \(missing.joined(separator: " and ")). The Remote needs an HTTPS address to work as a Home Screen app.")
            Button("Open DNS Settings") { NSWorkspace.shared.open(Self.tailscaleDNSSettings) }
        case .serve:
            Text("MyRemote asks Tailscale to pass \(setup.tailscale?.dnsName.map { "https://\($0)" } ?? "your Mac's tailnet address") on to it. Only your own devices can open it.")
            HStack {
                Button("Turn On") { host.turnOnServe() }.disabled(host.serveStarting)
                if host.serveStarting { ProgressView().controlSize(.small) }
            }
            if let problem = host.serveProblem { Text(problem).foregroundStyle(.red) }
        case .accessibility:
            Text("macOS asks before an app can move the pointer or type. Turn on MyRemote in the list that opens.")
            Button("Allow…") { host.requestAccessibility() }
        case .iPhoneTailscale:
            HStack(alignment: .top, spacing: 16) {
                QRCode(text: Self.tailscaleIOS).frame(width: 110, height: 110)
                Text("Scan with the iPhone's camera to get Tailscale from the App Store, then log in with the same account as this Mac. This turns green once the iPhone joins.")
            }
        case .pair:
            if let url = setup.remoteURL {
                HStack(alignment: .top, spacing: 16) {
                    QRCode(text: url).frame(width: 140, height: 140)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. With Tailscale connected on the iPhone, scan this and open it in Safari.")
                        Text("2. Tap Share → Add to Home Screen, then open MyRemote from the Home Screen.")
                        Text("3. Click Pair and type the code into the Remote.")
                        HStack {
                            Button("Pair…") {
                                host.pairings.newCode()
                                openWindow(id: PairWindow.id)
                            }
                            .keyboardShortcut(.defaultAction)
                            Button("Copy Address") { host.copy(url) }
                        }
                        Text(url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// The standalone Tailscale app and the App Store one have different bundle IDs.
    private static func openTailscale() {
        let app = ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]
            .lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            ?? URL(filePath: "/Applications/Tailscale.app")
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}

/// A QR code the iPhone's camera can open.
private struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .padding(6)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}
