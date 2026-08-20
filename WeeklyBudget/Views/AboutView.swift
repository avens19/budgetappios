import SwiftUI
import BudgetCore

/// Who wrote this, how to reach him, and where the rest of it is.
///
/// There are no accounts and no support desk, so someone with a problem has
/// nowhere to go: a review is one-way and slow, and the address in the privacy
/// policy is a page on the web app that nobody would think to open. This is the
/// one screen that answers "who is behind this and how do I ask them
/// something", and it carries the version so a bug report says which build it
/// came from without anyone having to ask.
///
/// This build says less than the other two on purpose, and "Learn more" carries
/// the difference. The Android screen and the web page both end with a tip jar;
/// a button in an iOS build that asks for money outside StoreKit is the kind of
/// thing 3.1.1 is written about, and a rejection over it would hold up whatever
/// else is in that submission. Pointing at the web page instead is the move this
/// app already makes for guideline 2.3.10 — the page off the end of the link is
/// free to say things a build is not — so the ask lives there and the link out
/// stays a plain "there is more about this on the web".
struct AboutView: View {

    private static let supportAddress = "avens19@gmail.com"

    /// `action=write-review` opens the listing with the rating sheet already up.
    /// Without it the listing opens at the top and the ratings section is a
    /// scroll away, which is far enough that most people never arrive.
    private static let reviewURL =
        URL(string: "https://apps.apple.com/app/id6803146065?action=write-review")!

    /// Both built from the API host rather than written out again, for the same
    /// reason the apps page is: a move takes the links with it.
    private static let aboutPage = LiveAPIClient.productionURL.appending(path: "About")
    private static let privacyURL = LiveAPIClient.productionURL.appending(path: "privacy")

    private static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    private static let supportURL: URL = {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AboutView.supportAddress
        components.queryItems = [
            URLQueryItem(name: "subject",
                         value: "Weekly Budget \(AboutView.version) for iPhone"),
        ]
        return components.url!
    }()

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    Text("Weekly Budget")
                        .font(.title3.weight(.semibold))
                    Text("Version \(Self.version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("I'm Andrew — just a guy in Calgary who loves making software and thinks more of it should be free. This app has no ads, no accounts and no price, and it is not going to grow any. I build it because I use it every week myself.")
                Text("If something is broken, or you want it to do something it doesn't, email me. I read all of it.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Section {
                Link(destination: Self.supportURL) {
                    Label("Need help? Email me", systemImage: "envelope")
                }
                Link(destination: Self.reviewURL) {
                    Label("Leave a review", systemImage: "star")
                }
            }

            Section {
                Link(destination: Self.aboutPage) {
                    Label("Learn more", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("A little more about the project, on the web.")
            }

            Section {
                Link(destination: Self.privacyURL) {
                    Label("Privacy", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
