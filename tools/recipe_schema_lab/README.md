# Cauldron Recipe Schema Lab

Interactive local UI for testing recipe import parsing and dataset corrections.

## Run

From repository root:

```bash
./tools/recipe_schema_lab/run.sh
```

Open: http://127.0.0.1:8765

## Pipeline behavior

- `/predict` and `/assemble_recipe` use the Swift-backed parser pipeline by default (via `tools/recipe_schema_model/swift_pipeline_bridge.py`).
- Set `CAULDRON_LAB_USE_PYTHON_FALLBACK=1` only if you need temporary fallback to legacy Python predictor/assembler behavior.

## What the lab supports

- Input modes: `text`, `url`, `image` (OCR)
- Per-line labels + confidence
- Manual label edits
- Assembled recipe preview (`ingredients`, `steps`, `notes`, grouped sections)
- Save local correction cases
- Append corrections into `CauldronTests/Fixtures/RecipeSchema`
- Run metrics/evaluation scripts from the UI

## Key files

- Backend: `tools/recipe_schema_lab/lab_handler.py`
- Frontend: `tools/recipe_schema_lab/static/index.html`
- Swift bridge: `tools/recipe_schema_model/swift_pipeline_bridge.py`
