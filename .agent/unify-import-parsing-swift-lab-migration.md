# Unify Import Parsing Around the On-Device Model and Migrate Lab to Swift-Backed Logic

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `/Users/nadav/Desktop/Cauldron/.agent/PLANS.md`.

## Purpose / Big Picture

Today, import quality differs by source type because the app and the web model lab do not run the same parsing pipeline. After this plan, all import paths that produce freeform recipe text (URL, social captions/descriptions, pasted text, OCR text) will pass through one shared model-assisted line-classification and schema-assembly flow in Swift. Structured metadata (for example image URL, yields, total time) will still be used where reliable, but ingredient/step/note routing will be unified and model-assisted.

User-visible outcome: importing the same recipe URL in the app and in the lab produces equivalent recipe structure (title, ingredients, steps, notes), and failures can be debugged once in one place. Success is observable by running parity tests and by reproducing known breakages like the Bon Appetit cookie URL in both surfaces with matching output.

## Progress

- [x] (2026-02-13 15:15Z) Reviewed current app import routing and parser code paths across URL/text/image/social entry points.
- [x] (2026-02-13 15:15Z) Compared Python lab pipeline against Swift app pipeline and confirmed non-parity in URL extraction, label routing, and assembly post-processing.
- [x] (2026-02-13 15:15Z) Ran baseline parity audit on `CauldronTests/Fixtures/RecipeSchema` and documented mismatch rates (line-label disagreements and recipe-shape drift).
- [x] (2026-02-13 15:15Z) Authored this ExecPlan for model-first import unification and Swift migration.
- [x] (2026-02-13 23:56Z) Implemented Milestone 1 (parity harness + golden baselines): added compare scripts, baseline artifacts, and schema tests.
- [x] (2026-02-13 23:56Z) Implemented Milestone 2 (Swift parity modules): added `ModelImportTextExtractor` and `ModelRecipeAssembler` with fixture parity coverage.
- [x] (2026-02-13 23:56Z) Implemented Milestone 3 (shared model-backed app routing): URL + social + text path now converge on classifier + model assembler.
- [x] (2026-02-13 23:56Z) Implemented Milestone 4 (lab Swift bridge): `/predict` and `/assemble_recipe` now default to Swift bridge output with optional env fallback.
- [x] (2026-02-13 23:56Z) Implemented Milestone 5 (gates/docs/regression): added CI parity gate tests, Swift parity gate tests, refreshed reports/docs, and validated thresholds.

## Surprises & Discoveries

- Observation: URL imports in the app bypass the line-classifier model for recipe websites because they use `HTMLRecipeParser` directly.
  Evidence: `Cauldron/Features/Importer/ImporterViewModel.swift` routes `.recipeWebsite` and `.unknown` to `dependencies.htmlParser.parse(from:)`.

- Observation: The Python lab URL flow and the app URL flow are fundamentally different systems today.
  Evidence: lab uses `tools/recipe_schema_lab/lab_handler.py` -> `lab_recipe.py` -> `lab_predictor.py` -> `lab_recipe.py` assembly, while app URL import uses `Cauldron/Core/Parsing/HTMLRecipeParser.swift`.

- Observation: Instruction splitting behavior is a concrete source of production-visible drift.
  Evidence: app `HTMLRecipeParser.splitInstructionString` splits on `. `; lab only splits collapsed numbered lists. On Bon Appetit cookie URL, raw JSON-LD instructions are 4 entries while Swift-style split yields 25 fragments.

- Observation: Significant shape drift occurs even when labels match, indicating assembler-level non-parity.
  Evidence: parity audit found many fixtures with identical labels but different ingredient/step/note counts due to Python-only post-processing (sanitization, wrapped-line merges, sauce split, tips/metadata handling).

- Observation: Hosted unit tests were intermittently crashing in unrelated SwiftUI teardown code, obscuring parser test status.
  Evidence: `xcodebuild` crash reports repeatedly showed `SearchTabViewModel.deinit`/`ConnectionInteractionCoordinator` frames during parser-only test runs.

- Observation: Remaining label drift came from a specific header-key mismatch, not model quality.
  Evidence: Python uses exact `_header_key` membership while Swift runtime used `hasPrefix` for note headers; aligning this dropped label mismatch rate from 1.2516% to 0.0000%.

## Decision Log

- Decision: Treat Python lab behavior as migration source-of-truth until Swift parity is achieved.
  Rationale: the user already validated Python behavior and requested migration from Python to Swift, not the reverse.
  Date/Author: 2026-02-13 / Codex

- Decision: Use one shared model-backed Swift parsing pipeline for all freeform-text import paths.
  Rationale: this removes cross-path drift and ensures fixes ship everywhere.
  Date/Author: 2026-02-13 / Codex

- Decision: Keep structured metadata extraction additive (image/yield/time/category), but unify ingredient/step/note routing through classifier + assembler.
  Rationale: preserves high-value metadata while still enforcing one behavior for recipe structure.
  Date/Author: 2026-02-13 / Codex

- Decision: Do not switch lab to Swift logic until hard parity gates pass on fixtures and golden URL cases.
  Rationale: prevents replacing a trusted debugging surface with an incomplete migration.
  Date/Author: 2026-02-13 / Codex

- Decision: Add a lightweight test-mode app root during XCTest runs.
  Rationale: isolates parser/import tests from unrelated SwiftUI teardown crashes so gating reflects parser behavior rather than host-app lifecycle instability.
  Date/Author: 2026-02-13 / Codex

- Decision: Keep Python fallback for lab behind an explicit environment variable only (`CAULDRON_LAB_USE_PYTHON_FALLBACK=1`).
  Rationale: Swift path is now default and parity-gated; fallback remains controlled for temporary rollback/debugging.
  Date/Author: 2026-02-13 / Codex

## Outcomes & Retrospective

- Final parity metrics:
  - Labels: `0/1518` mismatches (`0.0000%`, threshold `<= 0.5%`) from `tools/recipe_schema_model/artifacts/parity_labels.json`.
  - Assembly shape: `1/67` mismatch docs (ingredient `1`, step `0`, note `0`; threshold `<= 2 docs`) from `tools/recipe_schema_model/artifacts/parity_assembly.json`.
- Import-path routing outcome:
  - URL website imports use migrated extraction + shared model-backed text parser path.
  - YouTube/Instagram/TikTok imports route caption/description lines through shared model-backed parser path.
  - Text imports remain model-backed through `TextRecipeParser`, now using parity-aligned `ModelRecipeAssembler`.
- Lab backend outcome:
  - `tools/recipe_schema_lab/lab_handler.py` now routes `/predict` and `/assemble_recipe` through `tools/recipe_schema_model/swift_pipeline_bridge.py` by default (`pipeline_backend=swift`).
  - Optional fallback remains available only when `CAULDRON_LAB_USE_PYTHON_FALLBACK=1`.
- Validation summary:
  - Python tool tests pass (`python3 -m unittest discover -s tools/recipe_schema_model/tests -v`).
  - Swift parser/import/parity gate tests pass (targeted `xcodebuild` suites including `LabParityGateTests`, URL/social pipeline tests, extractor/assembler parity tests, and schema regression tests).
- Remaining known gaps:
  - No parser parity blockers remain under defined thresholds. Existing unrelated Swift 6 actor-isolation warnings remain outside this migration scope.

## Context and Orientation

The app currently has multiple parser entry points:

- Import orchestration: `Cauldron/Features/Importer/ImporterViewModel.swift`.
- Website URL parser (currently parser-only): `Cauldron/Core/Parsing/HTMLRecipeParser.swift`.
- Text parser (already model-assisted): `Cauldron/Core/Parsing/TextRecipeParser.swift`.
- Social parsers (YouTube/Instagram/TikTok): `Cauldron/Core/Parsing/YouTubeRecipeParser.swift`, `Cauldron/Core/Parsing/InstagramRecipeParser.swift`, `Cauldron/Core/Parsing/TikTokRecipeParser.swift`.
- Model classifier service: `Cauldron/Core/Services/RecipeLineClassificationService.swift`.
- Swift schema assembler: `Cauldron/Core/Parsing/RecipeSchemaAssembler.swift`.

The Python lab currently contains both extraction and assembly logic:

- Request handler: `tools/recipe_schema_lab/lab_handler.py`.
- URL/text/image extraction and assembly logic: `tools/recipe_schema_lab/lab_recipe.py`.
- Model predictor wrapper: `tools/recipe_schema_lab/lab_predictor.py`.

In this plan, “model-backed pipeline” means: normalize lines, classify each line (`title`, `ingredient`, `step`, `note`, `header`, `junk`), and assemble recipe structure from those labels with deterministic post-processing. “Parity” means Swift output matches Python-defined expected behavior within explicit thresholds defined below.

This repository does not currently show a `.beads/` directory, so Beads issue creation/tracking is skipped for this plan.

## Plan of Work

### Milestone 1: Build parity harnesses and lock baselines before code migration

This milestone creates objective parity gates before any behavioral port. Add two harnesses: one for label parity and one for assembled recipe parity. The label harness compares Python lab predictor labels with Swift classifier labels over `CauldronTests/Fixtures/RecipeSchema/lines/*.lines.jsonl`. The recipe harness compares Python assembled output versus Swift assembled output over `CauldronTests/Fixtures/RecipeSchema/documents/*.doc.json`.

Add golden URL cases under `CauldronTests/Fixtures/RecipeSchema/regression/` including the Bon Appetit cookies URL and at least 5 additional known-problem pages (mixed abbreviations, subsection headers, noisy metadata lines).

Acceptance for this milestone is not “pass”; it is “measured.” The output must include baseline mismatch counts and top confusion categories checked into repository artifacts so later milestones prove improvements.

For milestone verification workflow:

1. Tests to write first:
   - `CauldronTests/Parsing/ModelParityBaselineTests.swift` with tests that execute harness scripts and assert report files exist.
   - `tools/recipe_schema_model/tests/test_swift_python_parity_report.py` asserting report schema and required fields.
2. Implementation:
   - Add parity scripts in `tools/recipe_schema_model/`:
     - `compare_swift_python_labels.py`
     - `compare_swift_python_assembly.py`
   - Add golden URL fixture definitions and expected report paths in `tools/recipe_schema_model/artifacts/`.
3. Verification:
   - Run parity scripts and confirm reports are generated with non-empty mismatch summaries.
4. Commit:
   - `Milestone 1: Add Swift-vs-Python parity harness and baseline reports`.

### Milestone 2: Port Python extraction and assembly behaviors to Swift for parity

This milestone ports Python logic into Swift modules so app behavior can match the validated lab behavior:

- URL extraction behavior from `tools/recipe_schema_lab/lab_recipe.py`:
  - JSON-LD candidate parsing and recipe-node scoring.
  - Instruction extraction that only splits collapsed numbered blobs (not generic sentence splits).
- Assembly behavior from Python `_assemble_app_recipe` into Swift equivalents:
  - metadata-line extraction (`serves`, prep/cook/total lines),
  - tips/variations note routing,
  - ingredient sanitization and drop rules,
  - wrapped-step and wrapped-ingredient merges,
  - sauce/for-serving section inference.

Introduce a dedicated Swift component for this migrated logic, for example:

- `Cauldron/Core/Parsing/ModelImportTextExtractor.swift`
- `Cauldron/Core/Parsing/ModelRecipeAssembler.swift`

Do not delete existing parsers in this milestone. Keep migration additive and wire new components behind tests.

For milestone verification workflow:

1. Tests to write first:
   - `CauldronTests/Parsing/ModelImportTextExtractorTests.swift` with failing tests for JSON-LD extraction and Bon Appetit instruction splitting parity.
   - `CauldronTests/Parsing/ModelRecipeAssemblerParityTests.swift` with failing fixture-driven tests comparing Swift assembly to Python expected output for selected fixtures.
2. Implementation:
   - Port extraction and assembly logic from Python into Swift.
3. Verification:
   - Run new tests plus parity scripts; assert mismatch metrics improve from Milestone 1 baseline and no Bon Appetit step-fragmentation regression remains.
4. Commit:
   - `Milestone 2: Port Python extraction and assembly logic to Swift parity modules`.

### Milestone 3: Route all app import paths that produce freeform text through model-backed pipeline

This milestone updates app routing so structure extraction is model-assisted everywhere it makes sense:

- URL recipe websites and unknown websites: use migrated Swift extractor -> classifier -> assembler path for ingredients/steps/notes, while preserving structured metadata when present.
- YouTube/Instagram/TikTok: keep source-specific metadata extraction but send extracted description/caption lines through the same classifier+assembler path.
- Text and image imports: keep using `TextRecipeParser`, but move shared assembly rules to the new unified components so behavior is consistent with URL/social imports.

Required wiring changes include:

- `Cauldron/Features/Importer/ImporterViewModel.swift`
- `Cauldron/App/DependencyContainer.swift`
- `Cauldron/Core/Parsing/HTMLRecipeParser.swift`
- `Cauldron/Core/Parsing/YouTubeRecipeParser.swift`
- `Cauldron/Core/Parsing/InstagramRecipeParser.swift`
- `Cauldron/Core/Parsing/TikTokRecipeParser.swift`
- `Cauldron/Core/Parsing/TextRecipeParser.swift`

For milestone verification workflow:

1. Tests to write first:
   - Extend `CauldronTests/Parsing/TextRecipeParserTests.swift` with cross-source parity fixtures.
   - Add `CauldronTests/Parsing/URLImportModelPipelineTests.swift` asserting model-backed path is invoked for website URLs.
   - Add `CauldronTests/Parsing/SocialImportModelPipelineTests.swift` asserting descriptions/captions are assembled through shared model-backed pipeline.
2. Implementation:
   - Wire all relevant import parsers to shared model-backed assembly.
3. Verification:
   - Run parser test suite and targeted importer tests. Confirm known failing URL imports now produce stable ingredient/step boundaries.
4. Commit:
   - `Milestone 3: Route URL and social imports through shared model-backed parsing pipeline`.

### Milestone 4: Switch web model lab backend to Swift pipeline only after parity gates pass

This milestone changes the lab backend so it no longer owns independent parsing logic. Instead, Python lab server invokes a Swift executable wrapper around the shared production parser modules.

Add a Swift CLI target (or scriptable executable) in the repo, for example:

- `tools/swift_recipe_pipeline_cli/` (or equivalent), outputting JSON for:
  - classify lines,
  - assemble recipe,
  - URL extraction + assembly.

Update lab endpoints in `tools/recipe_schema_lab/lab_handler.py` to call this CLI for `/predict` and `/assemble_recipe`. Keep a temporary fallback flag to Python path (`CAULDRON_LAB_USE_PYTHON_FALLBACK=1`) during rollout, then remove fallback in Milestone 5 after stability confirmation.

For milestone verification workflow:

1. Tests to write first:
   - `tools/recipe_schema_model/tests/test_lab_swift_bridge.py` failing tests that call lab endpoints and assert they are served by Swift pipeline output contract.
   - `CauldronTests/Parsing/LabParityGateTests.swift` that reads latest parity reports and fails if thresholds are not met.
2. Implementation:
   - Build Swift CLI and integrate lab handler bridge.
3. Verification:
   - Run lab backend locally and verify same URL in app and lab returns equivalent structure.
   - Confirm parity gate thresholds pass before defaulting lab to Swift path.
4. Commit:
   - `Milestone 4: Migrate web model lab backend to Swift parser pipeline`.

### Milestone 5: Enforce parity gates in CI, remove temporary dual-path logic, finalize docs

This milestone makes parity and unified routing permanent:

- Add CI step to run parity scripts and fail on threshold breaches.
- Remove temporary fallback toggles and dead code.
- Update docs:
  - `tools/recipe_schema_lab/README.md`
  - `tools/recipe_schema_model/README.md`
  - parser architecture notes in code comments near importer routing.

Required parity thresholds at completion:

- Line-label disagreement (Swift vs Python baseline spec) <= 0.5% on fixture lines.
- Assembled recipe count mismatches (ingredient/step/note) <= 2 docs total, each documented with rationale.
- Golden URL set: 100% pass on required assertions (including Bon Appetit cookie case).

For milestone verification workflow:

1. Tests to write first:
   - CI-parity test wrappers in `tools/recipe_schema_model/tests/test_ci_parity_gate.py`.
   - Swift regression tests for remaining documented exceptions.
2. Implementation:
   - Wire CI checks, remove fallback/dead paths, update docs.
3. Verification:
   - Full command suite passes locally and in CI simulation.
4. Commit:
   - `Milestone 5: Enforce parser parity gates and finalize unified model-first import architecture`.

## Concrete Steps

Run all commands from `/Users/nadav/Desktop/Cauldron`.

1. Generate/update parity baselines:

    python3 tools/recipe_schema_model/compare_swift_python_labels.py \
      --fixtures CauldronTests/Fixtures/RecipeSchema/lines \
      --out tools/recipe_schema_model/artifacts/parity_labels.json

    python3 tools/recipe_schema_model/compare_swift_python_assembly.py \
      --fixtures CauldronTests/Fixtures/RecipeSchema/documents \
      --out tools/recipe_schema_model/artifacts/parity_assembly.json

   Expected outcome: both report files exist with totals, mismatch rates, and per-case detail.

2. Run Python tooling tests:

    python3 -m unittest discover -s tools/recipe_schema_model/tests -v

   Expected outcome: all tooling tests pass.

3. Run targeted iOS parser/import tests:

    xcodebuild test \
      -project Cauldron.xcodeproj \
      -scheme Cauldron \
      -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
      -only-testing:CauldronTests/URLImportModelPipelineTests \
      -only-testing:CauldronTests/SocialImportModelPipelineTests \
      -only-testing:CauldronTests/Parsing/ModelImportTextExtractorTests \
      -only-testing:CauldronTests/Parsing/ModelRecipeAssemblerParityTests \
      -only-testing:CauldronTests/Parsing/RecipeSchemaRegressionTests

   Expected outcome: all listed tests pass.

4. Run parity gate after migration:

    python3 tools/recipe_schema_model/compare_swift_python_labels.py --gate
    python3 tools/recipe_schema_model/compare_swift_python_assembly.py --gate

   Expected outcome: gate mode exits 0 and prints threshold summary.

5. Run lab in Swift-backed mode and manually verify golden URL behavior:

    ./tools/recipe_schema_lab/run.sh

   Expected outcome: lab UI at `http://127.0.0.1:8765` shows outputs matching app structure for golden URLs.

## Validation and Acceptance

The plan is accepted only when all of the following are true:

1. App import paths for URL website, URL social captions/descriptions, pasted text, and OCR text all use the shared model-backed structure pipeline (classifier + assembler) for ingredient/step/note routing.
2. Website URL imports no longer fragment instruction lines on generic sentence periods; golden Bon Appetit case passes.
3. Swift and Python parity reports meet final thresholds in Milestone 5.
4. Web model lab endpoints use Swift pipeline output by default; Python-only parsing path is removed or disabled by default with documented fallback only if explicitly retained.
5. Regression tests and tooling tests pass from a clean checkout following only this plan.

For each milestone, implementation must follow this order:

1. Write failing tests first (test file paths and assertions defined in the milestone).
2. Implement the minimal required code.
3. Run verification commands; milestone completes only when all pass.
4. Commit with the milestone commit message.

## Idempotence and Recovery

All parity scripts must be idempotent: re-running them overwrites report artifacts deterministically. New migration code should be additive until parity gates pass; avoid destructive deletions until Milestone 5.

If a milestone introduces regressions, recovery path is:

- revert only that milestone commit,
- keep parity artifacts,
- re-run tests and parity scripts,
- re-implement with narrower scope.

If lab bridge to Swift fails, temporary fallback can be enabled via environment variable during Milestone 4 only; this fallback must be removed or default-disabled by Milestone 5.

## Artifacts and Notes

During implementation, keep these artifacts updated:

- `tools/recipe_schema_model/artifacts/parity_labels.json`
- `tools/recipe_schema_model/artifacts/parity_assembly.json`
- `tools/recipe_schema_model/artifacts/parity_golden_urls.json`

Include concise evidence snippets in this plan as implementation progresses, especially:

- before/after mismatch rates,
- golden URL comparison outputs,
- failing-test to passing-test transitions per milestone.

## Interfaces and Dependencies

At completion, maintain these stable interfaces (names may be adjusted only if all tests and call sites are updated in same milestone):

- Shared model-backed extraction/assembly interfaces in Swift, callable from app parsers and CLI bridge.
- Swift CLI interface used by lab, returning JSON objects that include:
  - line labels and confidences,
  - assembled `title`, `ingredients`, `steps`, `notes`,
  - extracted metadata fields used by app preview (`yields`, `totalMinutes`, `sourceURL`, `sourceTitle`).

Core files expected to exist or be updated:

- `Cauldron/Core/Services/RecipeLineClassificationService.swift`
- `Cauldron/Core/Parsing/RecipeSchemaAssembler.swift`
- `Cauldron/Core/Parsing/TextRecipeParser.swift`
- `Cauldron/Core/Parsing/HTMLRecipeParser.swift`
- `Cauldron/Core/Parsing/YouTubeRecipeParser.swift`
- `Cauldron/Core/Parsing/InstagramRecipeParser.swift`
- `Cauldron/Core/Parsing/TikTokRecipeParser.swift`
- `Cauldron/Features/Importer/ImporterViewModel.swift`
- `Cauldron/App/DependencyContainer.swift`
- `tools/recipe_schema_lab/lab_handler.py`
- `tools/recipe_schema_model/compare_swift_python_labels.py`
- `tools/recipe_schema_model/compare_swift_python_assembly.py`

Plan revision note: Created this plan in response to the request to make all import paths model-backed where appropriate, enforce parity with Python-first behavior, and only then migrate the web model lab to Swift-backed logic.
