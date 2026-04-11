# Stage 2 Modeling Pipeline

This project uses `data_pipeline_stage_2.ipynb` for Stage 2 machine learning.

## What it does

- Loads `ds_unbalanced_panel` (required) and `ds_balanced_core` (optional robustness) from:
  - in-memory DataFrames, or
  - warehouse tables in `dw`/`public`.
- Trains time-aware regression models for `case_fatality_rate_pct`:
  - `country_mean_baseline`
  - `ridge`
  - `random_forest`
- Exports artifacts to:
  - `Data Gathering/transformed/` if present, else `./transformed/`

## Output files

- `stage2_split_summary.csv`
- `stage2_model_metrics.csv`
- `stage2_model_predictions.csv`
- `stage2_robustness_delta.csv` (when balanced view is available)

## Quick run

1. Run Stage 1 through Phase 7 so analysis views are available.
2. Open and run `data_pipeline_stage_2.ipynb` from top to bottom.
3. Review `stage2_model_metrics.csv` test rows for model selection.

