# Data Pipeline Status

**Project:** MENA COVID and Resilience ELT Analysis  
**Last Updated:** 2026-04-07  
**Canonical Implementation:** `data_pipeline.ipynb` (notebook-first)

---

## 1) Current Scope and Orientation

- This repo is notebook-first: all operational pipeline logic is in `data_pipeline.ipynb`.
- `main.py` is template code and is not part of the active ELT pipeline.
- Geographic scope is fixed by allowlist (`ALLOWLIST_CODES`) to **16 countries**.
- **Cyprus is excluded** from analysis and marts.

### In-scope countries (16)
- Bahrain
- Egypt
- Iran
- Iraq
- Israel
- Jordan
- Kuwait
- Lebanon
- Oman
- Palestine
- Qatar
- Saudi Arabia
- Syria
- Turkey
- United Arab Emirates
- Yemen

---

## 2) Study Goals and Research Questions (Current Scope)

### Overall study objective
- Build a reproducible ELT-driven evidence base to analyze how COVID-19 health outcomes in MENA relate to vaccination progress, demographic structure, and socioeconomic context.

### Core goals
- Produce analysis-ready country-time datasets from heterogeneous public indicators with clear transformation rules.
- Quantify and document data limitations (missingness, coverage gaps, validation issues) before modeling.
- Derive interpretable resilience features (for example: per-capita burden, CFR, urbanization ratio, demographic vulnerability) that support comparable inference.
- Enable both cross-country and within-country analysis while making temporal overlap constraints explicit.

### Study questions the pipeline should answer
- How did COVID-19 burden vary across the 16-country MENA scope after normalization?
- What relationship is observed between vaccination progression and mortality outcomes?
- Which contextual factors (demographic and socioeconomic) are associated with better or worse outcome trajectories?
- Are conclusions stable across unbalanced coverage views and stricter balanced-core sensitivity views?

### Success criteria
- Marts and QA outputs are reproducible from warehouse-backed runs.
- Missingness and date-coverage limitations are reported alongside results.
- Main findings are supported in `ds_unbalanced_panel` and tested for robustness in `ds_balanced_core`.

---

## 3) Canonical ELT Flow (Notebook Order)

### Phase 1-5: Extract and domain shaping
Build source DataFrames using `fetch_and_process_data(...)` and `apply_country_mapping(...)`.

Expected DataFrames:
- `df_deaths_cases`
- `df_population`
- `df_fertility`
- `df_life_expectancy`
- `df_socio_economic`
- `df_vaccination`

### Phase 6: Load to warehouse (`dw.*`)
- Convert source frames to standardized long observations via `dataframe_to_observations`.
- Full refresh load pattern:
  - `TRUNCATE ... RESTART IDENTITY CASCADE`
- Load tables:
  - `dw.dim_country`
  - `dw.dim_indicator`
  - `dw.dim_source`
  - `dw.fact_observation`
- Fact deduplication before insert is applied on warehouse key.

### Pre-Phase-7 checkpoint (required for reruns)
A checkpoint block should reload required variables from `dw.fact_observation` (+ dimensions) when in-memory source DataFrames are missing, so Phase 7+ can run without re-running all extraction cells.

### Phase 7: Transform to marts + QA
Create curated outputs:
- `mart_panel_long`
- `mart_panel_yearly`
- `mart_health_outcomes`
- `mart_vaccination`
- `mart_context`

Create QA outputs:
- `qa_missingness_by_country_variable`
- `qa_completeness_matrix`
- `qa_outlier_manual_review`
- `qa_invalid_value_log`
- `qa_vaccination_consistency_issues`
- `qa_date_coverage_country_feature`
- `qa_date_coverage_feature_summary`

### Phase 8: Diagnostics
- Box plots and quick diagnostics over numeric transformed variables.

### Phase 9: Stage 3 Forecasting (R script)
- Forecasting implementation is in `stage_3_forecasting.R`.
- Default source is PostgreSQL (`dw.*`) with optional file/auto source modes.
- Forecasting is performed per country and per COVID-related metric.
- Outputs are written to `transformed/`.

---

## 4) Data Contracts and Normalization Rules

### Long schema contract (input to transforms)
Required columns:
- `date`
- `entity`
- `variable`
- `value`

Optional:
- `country`

### Normalization conventions
- Selected count variables are normalized to `per_million` using same-date population.
- Fraction variables in `[0, 1]` are converted to percent (`* 100`).
- `worldBank/NY_GDP_PCAP_CD` remains direct USD (no additional per-capita normalization).

### Expected derived features
- `case_fatality_rate_pct`
- `urbanization_ratio`
- `demographic_vulnerability_index`
- Vaccination progression and lagged fields using `add_month_lag(..., months=2|3)`

### Frequency handling
- Frequency inferred per variable using `infer_frequency_flag(...)` and stored in marts.

---

## 5) Missingness and Imputation Policy (Current)

This policy is now the project default.

### Tiered policy by country-variable missingness
- **`missing_pct >= 80%`**: exclude country-variable pair from modeling datasets.
- **`30% <= missing_pct < 80%`**: conservative short-gap fill only, keep remaining values as missing.
- **`missing_pct < 30%`**: normal interpolation and limited carry-forward/carry-back rules.

### Important interpretation rule
- Nulls can remain after imputation by design.
- Imputation is bounded and conservative; it does not force complete fill when data support is weak.

### Specific decision already applied
- Highly sparse `Count_MedicalCondition*` style country-variable pairs are excluded from downstream modeling when they meet the `>= 80%` threshold.

---

## 6) Date Coverage and Time-Series Alignment

The pipeline now tracks start/end coverage for each country-feature pair and summarizes by feature.

Outputs:
- `qa_date_coverage_country_feature`: detailed coverage at country-feature level.
- `qa_date_coverage_feature_summary`: aggregate coverage summary per feature.

Purpose:
- make temporal non-overlap explicit,
- support dataset view selection (balanced vs unbalanced),
- prevent accidental inference on non-comparable windows.

---

## 7) Analysis Dataset Strategy (Simplified Three-View)

### A) `ds_unbalanced_panel`
- Keeps maximum country coverage.
- Uses available observations with documented missingness.
- Best for exploratory relationships and broad regional narrative.

### B) `ds_balanced_core`
- Uses stricter predictor set and country eligibility filters.
- Intended for comparability-focused modeling.
- If no strict common time window exists, fallback behavior should use `complete_rows` for eligible countries instead of forcing an empty dataset.

### C) `country_longitudinal_views`
- Country-specific longitudinal perspective with wider temporal retention.
- Best for within-country trajectory analysis.

### Current practical guidance
- Treat `ds_unbalanced_panel` as primary default for cross-country analyses.
- Use `ds_balanced_core` as sensitivity/robustness view when sample size is adequate.

### Stage 2 cluster analysis question bank (descriptive segmentation)

Current clustering basis (latest Stage 2 run):
- `LifeExpectancy_Person`
- `Count_Person`
- `demographic_vulnerability_index`
- `Count_Person_15To64Years_InLaborForce_AsFractionOf_Count_Person_15To64Years`

Per-cluster questions to guide interpretation:

1. Structural profile
- Is this cluster characterized by higher/lower life expectancy than the full 16-country median?
- Are countries in this cluster systematically larger/smaller by population scale?
- Does this cluster show higher demographic vulnerability than other clusters?
- Is labor-force participation structurally stronger/weaker relative to peer clusters?

2. COVID burden and severity
- What are cluster-level medians and IQRs for `cases_per_million`, `deaths_per_million`, and `case_fatality_rate_pct`?
- Which cluster reaches the highest CFR peak, and at what date window?
- Which cluster has the fastest post-peak decline in deaths per million?

3. Vaccination progression and outcome linkage
- How quickly does each cluster progress across `vax_at_least_one_pct`, `vax_primary_pct`, and `vax_booster_pct`?
- Are larger vaccination progression gaps (`gap_one_to_primary_pct`, `gap_primary_to_booster_pct`) concentrated in specific clusters?
- After vaccination increases, do clusters differ in lagged CFR/death improvements?

4. Resilience and heterogeneity
- Are there within-cluster outlier countries that materially outperform or underperform cluster medians?
- Which cluster combines weaker structural context with better-than-expected COVID outcomes (positive deviance)?
- Which cluster appears most sensitive to shocks (high volatility over time in outcomes)?

5. Robustness checks
- Do cluster-level conclusions remain directionally consistent between `ds_unbalanced_panel` and `ds_balanced_core`?
- Are findings stable when using median-based summaries vs mean-based summaries?
- Do results persist when excluding single-country outliers from each cluster?

Interpretation guardrail:
- Cluster findings are descriptive/associational and should not be framed as causal effects.

---

## 8) Latest Reported Run Snapshot (User-verified)

Derived marts:
- `mart_panel_long`: 75,928 rows
- `mart_panel_yearly`: 7,231 rows
- `mart_health_outcomes`: 35,388 rows
- `mart_vaccination`: 35,388 rows
- `mart_context`: 35,388 rows

Date coverage QA:
- `qa_date_coverage_country_feature`: 162 rows
- `qa_date_coverage_feature_summary`: 12 rows

Three-view artifacts (latest successful result shared):
- `ds_balanced_core`: 45 rows, 15 countries, 2021-01-01 to 2023-01-01
- `ds_unbalanced_panel`: 91 rows, 16 countries, 2021-01-01 to 2024-01-01
- `country_longitudinal_views`: 34,481 rows, 16 countries, 1960-01-01 to 2025-11-23

Balanced predictors in latest run:
- `urbanization_ratio`
- `demographic_vulnerability_index`
- `worldBank/NY_GDP_PCAP_CD`

---

## 9) Stage 3 Forecasting Status (Current)

### Implementation summary
- Stage 3 is implemented as an R-based forecasting workflow in `stage_3_forecasting.R`.
- The script pulls directly from Postgres by default (`--source postgres`).
- Forecasts are generated for COVID-related metrics detected from the input panel.

### Current Stage 3 defaults
- Source: `postgres`
- Aggregation: `month`
- Model family: `auto.arima` with bounded runtime defaults (`approximation=TRUE`, `stepwise=TRUE`)
- Forecast horizon default: `6`

### Stage 3 outputs
- `transformed/stage3_forecasts.csv`
- `transformed/stage3_model_metrics.csv`
- `transformed/stage3_forecast_panels.png`

### Canonical Stage 3 run command
- `Rscript stage_3_forecasting.R --source postgres --aggregate month --max-series 120`

### Notes from latest implementation cycle
- Forecast generation completed after fixing aggregation and plotting issues.
- Plot rendering is now interactive-session aware (`interactive()`), so charts display in RStudio while still saving PNG artifacts.
- Package-version warnings (for example, packages built under R 4.3.3) are non-fatal unless paired with runtime errors.

---

## 10) Known Operational Notes

- Local Postgres connectivity can differ by IDE/runtime environment.
- If `try_default_postgres_connection()` fails in one IDE but works in another, compare:
  - Python interpreter/venv,
  - environment variables,
  - host/port/user defaults,
  - local auth settings (`pg_hba.conf`) and active server instance.
- Phase 7 requires either in-memory source DataFrames or the warehouse checkpoint loader.

---

## 11) Explicit Exclusions and Cleanup Decisions

To keep document and pipeline aligned, the following legacy items are removed from active scope:
- 17-country framing (replaced by 16-country allowlist).
- Cyprus inclusion.
- Legacy hospitalization/exchange-rate narrative as core modeling pillars.
- Any strategy text that conflicts with current missingness and conservative imputation policy.

---

## 12) Next Implementation Priorities

1. Keep checkpoint-before-Phase-7 cell stable and rerun-safe.
2. Persist run-level QA metadata (counts, min/max dates, exclusions) to warehouse QA tables per execution.
3. Add compact model-readiness report per dataset view:
   - available countries,
   - predictors retained,
   - overlap window,
   - effective sample size.
4. Continue derived-metric analysis using unbalanced panel as primary and balanced core as robustness check.
5. Add Stage 3 forecast governance checks:
  - minimum data points by country-metric,
  - forecast plausibility thresholds,
  - automatic fallback model logging for failed ARIMA fits.
