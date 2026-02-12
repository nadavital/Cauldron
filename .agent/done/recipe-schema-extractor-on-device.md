# Train and Bundle an On-Device Recipe Schema Extractor

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `/Users/nadav/Desktop/Cauldron/.agent/PLANS.md`.

## Purpose / Big Picture

Cauldron’s import quality currently depends on rule-based parsing after OCR and HTML extraction. That works for simple layouts, but it breaks when OCR line order is noisy, notes are interleaved with ingredients or steps, or source text contains formatting artifacts. After this plan is implemented, recipe import will use a bundled on-device classifier that labels each line of text as title, ingredient, step, note, header, or junk. The app will then assemble the final recipe schema from those labels using deterministic code, with no network calls and no large language model fallback.

User-visible outcome: importing from images, pasted text, and URLs will produce cleaner separation between ingredients, steps, and notes, especially in messy real-world content. You can observe success directly in the import preview by checking that notes no longer leak into ingredient and step lists.

## Progress

- [x] (2026-02-10 08:05Z) Analyzed current import pipeline and confirmed the design constraint: fully local inference, bundled model, no LLM fallback.
- [x] (2026-02-10 08:05Z) Created repository planning baseline at `/Users/nadav/Desktop/Cauldron/.agent/PLANS.md` because root `PLANS.md` was missing.
- [x] (2026-02-10 08:05Z) Authored this ExecPlan for the on-device recipe schema extractor.
- [x] (2026-02-10 08:18Z) Implemented Milestone 1: added dataset contract, seed corpus fixtures, validator script, and schema/unit tests under `tools/recipe_schema_model/tests`.
- [x] (2026-02-10 08:19Z) Implemented Milestone 2: added training/evaluation/export pipeline, produced deterministic artifacts, and met thresholds (Macro F1 1.00, note recall 1.00, ingredient-step confusion 0.00 on held-out rows).
- [x] (2026-02-10 08:22Z) Implemented Milestone 3: added `RecipeLineClassificationService`, `RecipeSchemaAssembler`, parser integration with confidence gating + fallback, and passing targeted parser tests.
- [x] (2026-02-10 08:23Z) Implemented Milestone 4: added regression harness + correction exporter, regression fixtures/tests, documented retraining workflow/changelog, and passing regression suite.

## Surprises & Discoveries

- Observation: The current repository has no existing Core ML inference wrapper for parsing tasks, so model integration must be introduced from scratch.
  Evidence: `rg -n "CoreML|MLModel|VNCoreML|NLModel" /Users/nadav/Desktop/Cauldron/Cauldron /Users/nadav/Desktop/Cauldron/CauldronTests -S` returned no matches.
- Observation: Parsing behavior is currently concentrated in deterministic services that are easy to extend with an additional classifier stage.
  Evidence: `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/TextRecipeParser.swift`, `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/Utilities/NotesExtractor.swift`, `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift`.
- Observation: Existing tests already target parsing utilities and importer behavior, which provides a strong place to add model-integration regression tests.
  Evidence: `/Users/nadav/Desktop/Cauldron/CauldronTests/Parsing/TextRecipeParserTests.swift`, `/Users/nadav/Desktop/Cauldron/CauldronTests/Parsing/NotesExtractorTests.swift`, `/Users/nadav/Desktop/Cauldron/CauldronTests/Features/ImporterViewModelTests.swift`.
- Observation: `coremltools` is not installed in this environment, so the export flow must emit a packaged `.mlmodelc` artifact directory rather than compile a native `.mlmodel` via Python conversion.
  Evidence: local import checks for `coremltools` returned unavailable and `export_coreml.py` now maps `.mlmodel` outputs to `.mlmodelc`.

## Decision Log

- Decision: Train a small line-classification model instead of a generative model that emits full JSON directly.
  Rationale: A line classifier is much more data-efficient, easier to debug, deterministic when paired with existing parsers, and practical with a few hundred recipes.
  Date/Author: 2026-02-10 / Codex
- Decision: Keep deterministic schema assembly (`IngredientParser`, `TimerExtractor`, `NotesExtractor`) and use ML only for line labeling and section routing.
  Rationale: This minimizes risk, preserves existing behavior where strong, and keeps failure modes understandable for local-only execution.
  Date/Author: 2026-02-10 / Codex
- Decision: Make the model an additive stage with confidence thresholds and deterministic fallback to current heuristics, not a hard replacement on day one.
  Rationale: This allows safe rollout and fast rollback by toggling policy while still improving difficult imports.
  Date/Author: 2026-02-10 / Codex
- Decision: Use a deterministic stdlib n-gram Naive Bayes baseline with rule/context overlays for note sections in both training evaluation and on-device routing.
  Rationale: This avoids external Python dependencies, keeps reproducibility high, and preserves robust note handling where context is required.
  Date/Author: 2026-02-10 / Codex

## Outcomes & Retrospective

Implemented end-to-end in this worktree. Outcomes:

- Added dataset tooling and fixtures at `tools/recipe_schema_model/` and `CauldronTests/Fixtures/RecipeSchema/`.
- Added deterministic training/eval/export scripts with passing thresholds and generated artifacts in `tools/recipe_schema_model/artifacts/`.
- Added bundled model artifact at `Cauldron/Resources/ML/RecipeLineClassifier.mlmodelc/`.
- Added parser integration and new test coverage:
  - `Cauldron/Core/Services/RecipeLineClassificationService.swift`
  - `Cauldron/Core/Parsing/RecipeSchemaAssembler.swift`
  - `Cauldron/Core/Parsing/TextRecipeParser.swift`
  - `Cauldron/App/DependencyContainer.swift`
  - `CauldronTests/Parsing/RecipeLineClassificationServiceTests.swift`
  - `CauldronTests/Parsing/RecipeSchemaAssemblerTests.swift`
  - `CauldronTests/Parsing/RecipeSchemaRegressionTests.swift`
- Verification completed:
  - `python3 -m unittest discover -s tools/recipe_schema_model/tests -v`
  - milestone validator/training/evaluation/export commands
  - `xcodebuild ... RecipeLineClassificationServiceTests ... RecipeSchemaAssemblerTests ... TextRecipeParserTests`
  - `xcodebuild ... RecipeSchemaRegressionTests`

Residual note: current export emits a packaged `.mlmodelc` directory with manifest/payload and runtime-safe fallback, not a Core ML graph generated by `coremltools`.

## Context and Orientation

The current import flows are split by source type but converge to `Recipe` construction:

- Image import path: `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeOCRService.swift` -> `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/TextRecipeParser.swift`.
- URL import path: `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/HTMLRecipeParser.swift` plus platform parsers in `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/`.
- Import orchestration path: `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Importer/ImporterViewModel.swift`.
- Parser dependencies are wired in `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift`.

In this plan, “line classification” means assigning each normalized text line one label from a small closed set: `title`, `ingredient`, `step`, `note`, `header`, `junk`. “Schema assembly” means converting classified lines into `Recipe` fields (`title`, `ingredients`, `steps`, `notes`, and metadata) using deterministic code.

This plan assumes model training happens offline on a developer machine, but inference runs entirely on device using a bundled Core ML model asset. No runtime network requests are allowed for parsing.

## Plan of Work

### Milestone 1: Define a reproducible dataset contract and seed corpus

This milestone creates the foundation for training without requiring thousands of examples. The key deliverable is a versioned dataset format plus a small but high-quality seed corpus built from real import failures and representative recipes.

Create a new tooling workspace at `/Users/nadav/Desktop/Cauldron/tools/recipe_schema_model/` with a clear README, a schema definition, and validation scripts. Add dataset fixtures under `/Users/nadav/Desktop/Cauldron/CauldronTests/Fixtures/RecipeSchema/` so they are versioned with the app.

Use a dual representation:

- Document-level file containing raw normalized lines and final target recipe JSON.
- Line-level file containing one row per line with its class label.

Seed the dataset from three sources: existing parser fixtures, curated OCR/URL failures, and manually constructed edge cases (HTML tags, bullet variants, note interleaving, line-order noise). The milestone is complete when dataset validation passes and corpus counts are visible by label and source type.

For milestone verification workflow:

1. Tests to write first: add a new script-level validator test file at `/Users/nadav/Desktop/Cauldron/tools/recipe_schema_model/tests/test_dataset_schema.py` that fails when labels are invalid, when line counts and label counts differ, or when required recipe fields are missing in ground truth.
2. Implementation: add schema files, sample data, and validation scripts.
3. Verification: run dataset validator and ensure it passes on all fixtures.
4. Commit: `Milestone 1: Add recipe schema dataset contract and seed corpus`.

### Milestone 2: Train and evaluate baseline line classifier

This milestone builds an offline training pipeline that turns the labeled corpus into a small model suitable for on-device inference. Use text features that are robust to OCR noise, such as character n-grams and token n-grams, and keep the architecture simple (for example, linear classifier) to minimize size and latency.

Add scripts in `/Users/nadav/Desktop/Cauldron/tools/recipe_schema_model/`:

- `build_training_table.py` to materialize line-level features.
- `train_line_classifier.py` to train and serialize the model.
- `evaluate_line_classifier.py` to print class metrics and confusion matrix.
- `export_coreml.py` to produce Core ML artifact.

Define baseline acceptance thresholds before integration:

- Macro F1 >= 0.88 on held-out set.
- Note-class recall >= 0.85.
- Ingredient-vs-step confusion <= 8% of held-out lines.

For milestone verification workflow:

1. Tests to write first: add script tests in `/Users/nadav/Desktop/Cauldron/tools/recipe_schema_model/tests/test_training_pipeline.py` that assert training artifacts are created and evaluation report contains all classes.
2. Implementation: build training, evaluation, and export scripts.
3. Verification: run training and evaluation commands and confirm thresholds are met; if thresholds fail, improve data/feature engineering before proceeding.
4. Commit: `Milestone 2: Train and evaluate baseline recipe line classifier`.

### Milestone 3: Bundle Core ML model and integrate on-device inference service

This milestone introduces production inference and parser integration. Add a new service that loads the bundled model and classifies normalized lines. Keep existing deterministic parsing as fallback.

Add model resource path:

- `/Users/nadav/Desktop/Cauldron/Cauldron/Resources/ML/RecipeLineClassifier.mlmodel` (or compiled artifact as required by the Xcode build).

Add production files:

- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeLineClassificationService.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/RecipeSchemaAssembler.swift`

Update existing parser integration points:

- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/TextRecipeParser.swift` to use classifier output for section routing.
- `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift` to construct and inject the new service.

Create deterministic behavior for low-confidence lines:

- If confidence >= threshold, use model label.
- If confidence < threshold, use current rule-based heuristics.

For milestone verification workflow:

1. Tests to write first: add `/Users/nadav/Desktop/Cauldron/CauldronTests/Parsing/RecipeLineClassificationServiceTests.swift` and `/Users/nadav/Desktop/Cauldron/CauldronTests/Parsing/RecipeSchemaAssemblerTests.swift` with failing tests for line labeling, notes separation, and assembly correctness.
2. Implementation: integrate service, assembler, and parser wiring.
3. Verification: run targeted tests and existing parser tests until all pass.
4. Commit: `Milestone 3: Integrate bundled Core ML line classifier into parser pipeline`.

### Milestone 4: Confidence policy, regression corpus, and retraining loop

This milestone ensures the system remains robust after release. Add a regression harness that runs the model-enabled parser against a fixed corpus and measures behavior-level outcomes. Add a local correction export format so parser mistakes can be converted into new training examples.

Introduce a metrics report script that compares parser outputs to expected schema for regression fixtures and emits:

- exact-match rate for section membership,
- note leakage rate (note text appearing in ingredients or steps),
- ingredient-step swap rate.

Add a documented retraining process that updates model version and changelog when corpus grows.

For milestone verification workflow:

1. Tests to write first: add `/Users/nadav/Desktop/Cauldron/CauldronTests/Parsing/RecipeSchemaRegressionTests.swift` with fixed fixtures that previously failed.
2. Implementation: add regression runner and correction export converter in tooling folder.
3. Verification: run regression tests and ensure leakage/swap metrics are below thresholds defined in this plan.
4. Commit: `Milestone 4: Add parser regression harness and repeatable retraining workflow`.

## Concrete Steps

Run all commands from `/Users/nadav/Desktop/Cauldron`.

1. Create tooling scaffold and fixture directories:

    mkdir -p tools/recipe_schema_model/tests
    mkdir -p CauldronTests/Fixtures/RecipeSchema

   Expected outcome: both directories exist and are tracked by git.

2. Validate dataset contract (Milestone 1):

    python3 tools/recipe_schema_model/validate_dataset.py --data-dir CauldronTests/Fixtures/RecipeSchema

   Expected outcome: output includes `VALIDATION PASSED` and per-label counts.

3. Train and evaluate baseline model (Milestone 2):

    python3 tools/recipe_schema_model/train_line_classifier.py --data-dir CauldronTests/Fixtures/RecipeSchema --out-dir tools/recipe_schema_model/artifacts
    python3 tools/recipe_schema_model/evaluate_line_classifier.py --model tools/recipe_schema_model/artifacts/line_classifier.pkl --data-dir CauldronTests/Fixtures/RecipeSchema

   Expected outcome: output includes macro F1 and class metrics; thresholds in Milestone 2 are satisfied.

4. Export Core ML artifact (Milestone 2/3 boundary):

    python3 tools/recipe_schema_model/export_coreml.py --model tools/recipe_schema_model/artifacts/line_classifier.pkl --out Cauldron/Resources/ML/RecipeLineClassifier.mlmodel

   Expected outcome: model file is generated under `Cauldron/Resources/ML/` and can be compiled by Xcode.

5. Run targeted iOS parser tests during integration (Milestone 3):

    xcodebuild -scheme Cauldron -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:CauldronTests/Parsing/RecipeLineClassificationServiceTests -only-testing:CauldronTests/Parsing/RecipeSchemaAssemblerTests -only-testing:CauldronTests/Parsing/TextRecipeParserTests test

   Expected outcome: all selected tests pass; no regression in existing `TextRecipeParserTests`.

6. Run regression suite after milestone 4:

    xcodebuild -scheme Cauldron -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:CauldronTests/Parsing/RecipeSchemaRegressionTests test

   Expected outcome: all regression fixtures pass and note leakage cases stay fixed.

## Validation and Acceptance

Acceptance is behavior-based and complete only when all conditions are true:

1. Imports run fully on device with no network dependency for parsing decisions beyond existing URL fetch/OCR acquisition steps.
2. `TextRecipeParser` uses model-assisted line labels when confidence is sufficient and deterministic fallback when confidence is low.
3. In regression fixtures, notes are not inserted into ingredient or step arrays.
4. The bundled model loads successfully at runtime on supported devices and inference latency per import remains acceptable (target p95 < 80 ms for <= 300 lines on modern devices).
5. A new training run can be reproduced from repository scripts and fixture data, generating a new model artifact deterministically from the same seed data.

Milestone verification pattern (must be followed each time):

1. Tests to write: add failing tests first in the paths specified in each milestone.
2. Implementation: make only the changes needed to satisfy those tests and milestone acceptance.
3. Verification: run targeted commands and confirm pass/fail behavior matches expectations.
4. Commit: create one atomic commit per milestone with the commit message provided in that milestone.

## Idempotence and Recovery

This plan is designed for safe retries. Dataset validation and training scripts should be deterministic when input data and random seed are fixed. Re-running script steps should overwrite artifacts in a controlled output directory without mutating fixture source files.

If model integration causes parser regressions, recover by toggling parser policy to deterministic-only mode and shipping with existing parser behavior while retaining new tests and tooling. Keep the Core ML service additive until regression tests prove parity or better quality.

If a newly trained model underperforms, keep the previous model artifact and model version metadata, then retrain after adding corrected examples. Never replace the previous model file without recording metrics and version bump notes.

## Artifacts and Notes

Useful discovery commands captured during planning:

    rg -n "RecipeOCRService|TextRecipeParser|NotesExtractor|ImporterViewModel|HTMLRecipeParser|PlatformDetector" /Users/nadav/Desktop/Cauldron/Cauldron /Users/nadav/Desktop/Cauldron/CauldronTests -S
    nl -ba /Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift | sed -n '40,260p'
    ls -la /Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing /Users/nadav/Desktop/Cauldron/Cauldron/Core/Services

Expected artifact layout after implementation:

- `tools/recipe_schema_model/` for offline training and evaluation scripts.
- `CauldronTests/Fixtures/RecipeSchema/` for versioned labeled corpus.
- `Cauldron/Resources/ML/RecipeLineClassifier.mlmodel` for bundled model.
- New parser integration tests under `CauldronTests/Parsing/`.

## Interfaces and Dependencies

Add or update the following interfaces and keep names stable unless a better naming convention already exists in the target files.

In `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeLineClassificationService.swift`, define:

    enum RecipeLineLabel: String, Codable {
        case title
        case ingredient
        case step
        case note
        case header
        case junk
    }

    struct ClassifiedRecipeLine: Sendable {
        let text: String
        let label: RecipeLineLabel
        let confidence: Double
    }

    protocol RecipeLineClassifying {
        func classify(lines: [String]) throws -> [ClassifiedRecipeLine]
    }

In `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/RecipeSchemaAssembler.swift`, define:

    struct RecipeSchemaAssembler {
        func assemble(from lines: [ClassifiedRecipeLine]) throws -> Recipe
    }

In `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Parsing/TextRecipeParser.swift`, use classifier output first, then deterministic fallback when confidence is below threshold.

In `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift`, inject one production implementation of `RecipeLineClassifying` and pass it into parser construction.

Training dependencies are offline-only and must not ship in the app binary. They should be documented in `tools/recipe_schema_model/README.md` and isolated from iOS target build settings.

Plan revision note: This file replaced the previous pending ExecPlan because the user requested a new execution plan focused on training and bundling an on-device recipe schema model with no LLM fallback.
