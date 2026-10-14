import SwiftUI

@main
struct HawadaarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item and its panel are AppKit (see StatusItemController); SwiftUI needs a scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ACStore

    var body: some View {
        Group {
            switch store.phase {
            case .signedOut: SignInView(error: nil)
            case .failed(let message): SignInView(error: message)
            case .loading:
                VStack(spacing: 14) {
                    BrandHeader(subtitle: "Connecting to MirAIe…")
                    ProgressView().controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            case .ready: ControlView()
            }
        }
        .frame(width: 340)
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// App icon and name, used on the sign-in and loading screens.
struct BrandHeader: View {
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hawadaar").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(subtitle).font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }
}

enum About {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static func show() {
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        let credits = NSMutableAttributedString(
            string: "ہوادار · airy, breezy\nControl your MirAIe air conditioner from the menu bar.\n\nMade by Abdul Ghani · ", attributes: body)
        var link = body
        link[.link] = URL(string: "https://abdulghani.tech")!
        credits.append(NSAttributedString(string: "abdulghani.tech", attributes: link))
        credits.append(NSAttributedString(
            string: "\n\nIndependent project, not affiliated with Panasonic. MIT License.", attributes: body))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

enum Palette {
    static let background = LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.13),
                                                    Color(red: 0.08, green: 0.08, blue: 0.11)],
                                           startPoint: .top, endPoint: .bottom)
    static let tile = Color.white.opacity(0.06)
    static let secondary = Color.white.opacity(0.55)
    static let accent = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.6, blue: 0.25)
}
