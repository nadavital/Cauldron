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
        if ProcessInfo.processInfo.arguments.contains("--cauldron-pcc-import-smoke-test") {
            await runImport()
            return
        }
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
    @MainActor
    private func runImport() async {
        let lines = ["Dough", "2 cups flour", "1 cup water", "Filling", "3 apples, diced", "1 tsp cinnamon",
                     "Instructions", "Mix flour and water to form a dough.", "Roll out the dough.",
                     "Combine apples and cinnamon, then fill the dough.", "Bake for 25 minutes at 180 C."]
        var evidence: [String: String] = ["result": "started", "source": lines.joined(separator: "\n")]
        func save() {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cauldron-pcc-import-smoke.json")
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
                report = String(decoding: data, as: UTF8.self)
            }
        }
        save()
        let recorder = ImportSmokeRecorder()
        let parser = TextRecipeParser(importStructurer: recorder)
        let start = Date()
        do {
            let baseline = try await TextRecipeParser().parse(lines: lines, sourceURL: URL(string: "https://example.com/apple-pastry"), sourceTitle: "Apple Pastry", imageURL: nil)
            let recipe = try await parser.parse(lines: lines, sourceURL: URL(string: "https://example.com/apple-pastry"), sourceTitle: "Apple Pastry", imageURL: nil)
            evidence["baselineSections"] = baseline.ingredients.map { $0.section ?? "none" }.joined(separator: ",")
            evidence["sections"] = recipe.ingredients.map { $0.section ?? "none" }.joined(separator: ",")
            evidence["ingredients"] = recipe.ingredients.map { "\($0.quantity.map { String(describing: $0) } ?? "") \($0.name)" }.joined(separator: "\n")
            evidence["steps"] = recipe.steps.map(\.text).joined(separator: "\n")
            evidence["plan"] = await recorder.planDescription
            let hasCloudPlan = await recorder.hasCloudPlan
            evidence["result"] = hasCloudPlan && recipe.ingredients.map(\.section) == ["Dough", "Dough", "Filling", "Filling"]
                && recipe.steps.count == 4 ? "cloudImportSuccess" : "qualityCheckFailedOrFallback"
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
private actor ImportSmokeRecorder: RecipeImportStructuring {
    var hasCloudPlan = false
    var planDescription = ""
    func structure(lines: [String]) async throws -> RecipeImportPlan? {
        let plan = try await PCCRecipeImportStructurer().structure(lines: lines)
        hasCloudPlan = plan != nil
        planDescription = plan?.items.map { "\($0.line):\($0.role.rawValue):\($0.sectionLine ?? -1)" }.joined(separator: ",") ?? "unavailable"
        return plan
    }
}
#endif
