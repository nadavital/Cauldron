# Cauldron Model Lab (Local-only)

This tool runs outside the repo so you can test/correct model behavior without committing anything.

## Run

From repo root:

```bash
./tools/recipe_schema_lab/run.sh
```

Then open:

- http://127.0.0.1:8765

Model artifacts used by this lab are in-repo:

- `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_model/artifacts/line_classifier.pkl`
- `/Users/nadav/.codex/worktrees/b2d8/Cauldron/Cauldron/Resources/ML/RecipeLineClassifier.mlmodelc/line_classifier.pkl`

## What it does

- Input modes: `text`, `url`, `image` (OCR via Apple Vision on macOS, with local `tesseract` fallback)
- Shows per-line predicted label + confidence
- Lets you edit labels manually
- Shows an **App Save Preview** panel that assembles your corrected labels into an app-like recipe shape:
  - `ingredients[]` with parsed `quantity`/`unit` (best-effort) and `section`
  - `steps[]` with `section` and extracted `timers`
  - grouped `ingredientSections[]` / `stepSections[]`
- `Save Local JSON`: writes correction files to:
  - `/Users/nadav/.codex/local/recipe_schema_lab/cases/`
- `Append To Dataset`: writes directly into repo fixtures via:
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_model/export_corrections.py`
- `Run Metrics`: runs evaluation + regression scripts and shows output inline
- Fixed holdout eval: any dataset fixture with ID prefix `holdout_` is excluded from retraining and evaluated separately in Metrics

## Layout

- Backend entrypoint: `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/app.py`
- Backend modules:
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/lab_server.py`
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/lab_handler.py`
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/lab_recipe.py`
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/lab_predictor.py`
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/lab_config.py`
- Frontend files:
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/static/index.html`
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/static/js/*.js`
  - `/Users/nadav/.codex/worktrees/b2d8/Cauldron/tools/recipe_schema_lab/static/css/*.css`

## Optional: point to a different repo checkout

```bash
CAULDRON_REPO=/absolute/path/to/Cauldron ./tools/recipe_schema_lab/run.sh
```

To override where local QA cases/tmp are stored:

```bash
CAULDRON_QA_LOCAL_ROOT=/absolute/path ./tools/recipe_schema_lab/run.sh
```

Optional OCR engine override:

```bash
# one of: apple | tesseract | auto
CAULDRON_LAB_OCR_ENGINE=apple ./tools/recipe_schema_lab/run.sh
```
