# Recipe Schema Model Tooling

Offline tooling for Cauldron's line-level recipe schema extraction.

## Dataset Contract

Fixtures live in `CauldronTests/Fixtures/RecipeSchema/` using two synchronized representations:

- `documents/<id>.doc.json`: document-level normalized lines plus target recipe schema.
- `lines/<id>.lines.jsonl`: one JSON record per normalized line with a class label.

Allowed labels:

- `title`
- `ingredient`
- `step`
- `note`
- `header`
- `junk`

## Commands

Run from repository root.

```bash
python3 tools/recipe_schema_model/validate_dataset.py --data-dir CauldronTests/Fixtures/RecipeSchema
python3 tools/recipe_schema_model/build_training_table.py --data-dir CauldronTests/Fixtures/RecipeSchema --out tools/recipe_schema_model/artifacts/training_table.jsonl
python3 tools/recipe_schema_model/train_line_classifier.py --data-dir CauldronTests/Fixtures/RecipeSchema --out-dir tools/recipe_schema_model/artifacts
python3 tools/recipe_schema_model/evaluate_line_classifier.py --model tools/recipe_schema_model/artifacts/line_classifier.pkl --data-dir CauldronTests/Fixtures/RecipeSchema --split tools/recipe_schema_model/artifacts/split.json --report tools/recipe_schema_model/artifacts/eval_report.json
python3 tools/recipe_schema_model/export_coreml.py --model tools/recipe_schema_model/artifacts/line_classifier.pkl --out Cauldron/Resources/ML/RecipeLineClassifier.mlmodel
python3 tools/recipe_schema_model/regression_metrics.py --model tools/recipe_schema_model/artifacts/line_classifier.pkl --regression-dir CauldronTests/Fixtures/RecipeSchema/regression --report tools/recipe_schema_model/artifacts/regression_report.json
```

## Acceptance Thresholds

- Macro F1 (present labels) >= 0.88
- Note-class recall >= 0.85 (only when note support > 0)
- Ingredient-vs-step confusion <= 8% of evaluated lines

`evaluate_line_classifier.py` exits non-zero when these thresholds are not met.

Training/eval split notes:

- `train_line_classifier.py` now uses a deterministic **doc-level** holdout split.
- This avoids leaking structure from the same recipe into both train and eval.

## Fixed Holdout Convention

- Use fixture IDs prefixed with `holdout_` for fixed eval-only cases.
- `train_line_classifier.py` excludes `holdout_*` by default.
- To evaluate only fixed holdout fixtures:

```bash
python3 tools/recipe_schema_model/evaluate_line_classifier.py \
  --model tools/recipe_schema_model/artifacts/line_classifier.pkl \
  --data-dir CauldronTests/Fixtures/RecipeSchema \
  --include-doc-prefix holdout_ \
  --skip-threshold-check
```

## Retraining Workflow

1. Add new corrected examples via `export_corrections.py` or manual fixtures.
2. Re-run `validate_dataset.py`.
3. Rebuild training table and retrain model.
4. Re-run `evaluate_line_classifier.py` and verify thresholds pass.
5. Re-run `regression_metrics.py` and verify leakage/swap rates stay below limits.
6. Export the artifact to `Cauldron/Resources/ML/RecipeLineClassifier.mlmodelc`.
7. Update `MODEL_CHANGELOG.md` with date, corpus size, and metrics.

## Notes

- The baseline model is a deterministic n-gram Naive Bayes implementation in pure Python stdlib.
- `export_coreml.py` emits a bundled `.mlmodelc`-style artifact directory with manifest and payload for on-device packaging.
