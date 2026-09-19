#if DEBUG
import SwiftUI
import FoundationModels

/// Explicit developer-only probe. Uses a fixed, non-personal prompt and the
/// production recipe service; it never opens or changes the recipe library.
struct PCCSmokeTestView: View {
    @State private var report = "Checking Private Cloud Compute…"
    @State private var didRun = false

    var body: some View {
        ScrollView { Text(report).textSelection(.enabled).padding() }
            .task {
                guard !didRun else { return }
                didRun = true
                await run()
            }
    }

    @MainActor
    private func run() async {
        let service = FoundationModelsService()
        var evidence: [String: String] = ["result": "started"]
        func save() {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cauldron-pcc-smoke.json")
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
                report = String(decoding: data, as: UTF8.self)
            }
        }
        let status = await service.generationStatus()
        evidence["initialRoute"] = status.selectedRoute.rawValue
        #if canImport(FoundationModels, _version: 2.0)
        if #available(iOS 27.0, macCatalyst 27.0, *) {
            evidence["cloudAvailability"] = String(describing: PrivateCloudComputeLanguageModel().availability)
        }
        #endif
        guard status.selectedRoute == .privateCloudCompute else {
            evidence["result"] = "cloudUnavailable"
            save()
            return
        }
        let route = PCCSmokeRouteRecorder()
        let start = Date()
        save()
        do {
            var last: GeneratedRecipe.PartiallyGenerated?
            for try await partial in service.generateRecipe(
                from: "Create a vegetarian chickpea and spinach skillet for two servings, ready in 20 minutes. Use no nuts. Include precise quantities and clear cooking steps.",
                onStatus: { status in await route.record(status.selectedRoute) }
            ) {
                if last == nil { evidence["firstOutputSeconds"] = String(Date().timeIntervalSince(start)) }
                last = partial
            }
            let routes = await route.routes
            evidence["routes"] = routes.map(\.rawValue).joined(separator: ",")
            evidence["title"] = last?.title ?? ""
            evidence["servings"] = last?.yields ?? ""
            evidence["minutes"] = last?.totalMinutes.map { String($0) } ?? ""
            evidence["ingredients"] = last?.ingredients?.map {
                "\($0.quantityValue.map { String($0) } ?? "") \($0.quantityUnit ?? "") \($0.name ?? "")"
            }.joined(separator: "\n") ?? ""
            evidence["steps"] = last?.steps?.compactMap(\.text).joined(separator: "\n") ?? ""
            evidence["ingredientCount"] = String(last?.ingredients?.count ?? 0)
            evidence["stepCount"] = String(last?.steps?.count ?? 0)
            let complete = !(last?.title?.isEmpty ?? true)
                && !(last?.ingredients?.isEmpty ?? true) && !(last?.steps?.isEmpty ?? true)
            evidence["result"] = complete && routes == [.privateCloudCompute] ? "cloudSuccess" : "notCloudSuccess"
        } catch {
            evidence["result"] = "failed"
            evidence["error"] = String(describing: error)
        }
        evidence["elapsedSeconds"] = String(Date().timeIntervalSince(start))
        save()
    }
}

private actor PCCSmokeRouteRecorder {
    var routes: [RecipeModelRoute] = []
    func record(_ route: RecipeModelRoute) { routes.append(route) }
}
#endif
