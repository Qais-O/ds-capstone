# Data Pipeline Status

**Project:** MENA COVID and Resilience ELT Analysis  
**Last Updated:** 2026-03-23  
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

## 2) Canonical ELT Flow (Notebook Order)

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

---

## 3) Data Contracts and Normalization Rules

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

## 4) Missingness and Imputation Policy (Current)

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

## 5) Date Coverage and Time-Series Alignment

The pipeline now tracks start/end coverage for each country-feature pair and summarizes by feature.

Outputs:
- `qa_date_coverage_country_feature`: detailed coverage at country-feature level.
- `qa_date_coverage_feature_summary`: aggregate coverage summary per feature.

Purpose:
- make temporal non-overlap explicit,
- support dataset view selection (balanced vs unbalanced),
- prevent accidental inference on non-comparable windows.

---

## 6) Analysis Dataset Strategy (Simplified Three-View)

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

---

## 7) Latest Reported Run Snapshot (User-verified)

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

## 8) Known Operational Notes

- Local Postgres connectivity can differ by IDE/runtime environment.
- If `try_default_postgres_connection()` fails in one IDE but works in another, compare:
  - Python interpreter/venv,
  - environment variables,
  - host/port/user defaults,
  - local auth settings (`pg_hba.conf`) and active server instance.
- Phase 7 requires either in-memory source DataFrames or the warehouse checkpoint loader.

---

## 9) Explicit Exclusions and Cleanup Decisions

To keep document and pipeline aligned, the following legacy items are removed from active scope:
- 17-country framing (replaced by 16-country allowlist).
- Cyprus inclusion.
- Legacy hospitalization/exchange-rate narrative as core modeling pillars.
- Any strategy text that conflicts with current missingness and conservative imputation policy.

---

## 10) Next Implementation Priorities

1. Keep checkpoint-before-Phase-7 cell stable and rerun-safe.
2. Persist run-level QA metadata (counts, min/max dates, exclusions) to warehouse QA tables per execution.
3. Add compact model-readiness report per dataset view:
   - available countries,
   - predictors retained,
   - overlap window,
   - effective sample size.
4. Continue derived-metric analysis using unbalanced panel as primary and balanced core as robustness check.
