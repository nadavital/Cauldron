import SwiftUI
import WebKit

/// The original input stays separate from the parser's editable interpretation.
struct ImportSourceReferenceView: View {
    let text: String?
    let image: UIImage?
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Original source", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .padding(.horizontal)
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 640)
                        .accessibilityLabel("Original recipe photo")
                }
            } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                ImportSourceWebView(url: url)
                Link("Open original in browser", destination: url)
                    .font(.subheadline)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color.secondary.opacity(0.06))
    }
}

private struct ImportSourceWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
