# AGENTS.md

## Project orientation
- This repo is notebook-first: `data_pipeline.ipynb` is the real application; `main.py` is template code and not part of the pipeline.
- The pipeline implements an ELT flow for MENA COVID + resilience analysis: extract from DataCommons, load to local Postgres warehouse (`dw.*`), then build marts + QA artifacts.
- Strategy and scope context lives in `DATA_PIPELINE_STATUS.md` (especially 16-country scope, exclusions, and analysis intent).

## Canonical execution flow (run in notebook order)
- **Phase 1-5 (Extract + EDA):** build in-memory DataFrames (`df_deaths_cases`, `df_population`, `df_fertility`, `df_life_expectancy`, `df_socio_economic`, `df_vaccination`) using `fetch_and_process_data(...)` and `apply_country_mapping(...)`.
- **Phase 6 (Load):** convert frames to observation rows (`dataframe_to_observations`) and load star-schema tables:
  - `dw.dim_country`, `dw.dim_indicator`, `dw.dim_source`, `dw.fact_observation`
- Load is full-refresh (`TRUNCATE ... RESTART IDENTITY CASCADE`) and deduplicates fact rows by warehouse key before insert.
- **Phase 7 (Transform):** create curated outputs:
  - `mart_panel_long`, `mart_panel_yearly`, `mart_health_outcomes`, `mart_vaccination`, `mart_context`
  - QA tables: `qa_missingness_by_country_variable`, `qa_completeness_matrix`, `qa_outlier_manual_review`, `qa_invalid_value_log`, `qa_vaccination_consistency_issues`
- **Phase 8:** box plots over numeric columns in transformed marts.

## Data contracts and project-specific rules
- Geography is hard-filtered by `ALLOWLIST_CODES` derived from `COUNTRY_CODES` (16 countries; Cyprus excluded).
- Input long schema expected by transforms: `date`, `entity`, `variable`, `value` (+ optional `country`).
- Normalization conventions (implemented in Phase 7):
  - selected count variables -> `per_million` using same-date population
  - fraction variables (0-1) -> percent (`* 100`)
  - GDP per capita (`worldBank/NY_GDP_PCAP_CD`) stays direct USD
- Derived features expected by downstream analysis:
  - `case_fatality_rate_pct`, `urbanization_ratio`, `demographic_vulnerability_index`
  - vaccination progression gaps + lag columns via `add_month_lag(..., months=2|3)`
- Frequency is inferred per variable via `infer_frequency_flag(...)` and stored in marts.

## Integration points and environment assumptions
- External API: `DataCommonsClient` (`datacommons_client`) with `API_KEY` currently hardcoded in `data_pipeline.ipynb`.
- Database: local PostgreSQL via SQLAlchemy; connection attempts are hardcoded in `try_default_postgres_connection()`.
- Transform outputs are saved to `Data Gathering/transformed/` if that directory exists, else fallback to `./transformed/`.
- Parquet write is attempted first; CSV fallback is expected when parquet engine is unavailable.

## Practical guardrails for AI agents
- Prefer editing `data_pipeline.ipynb` cells, not `main.py`, for pipeline behavior changes.
- Preserve naming conventions for global DataFrames and `mart_*`/`qa_*` outputs; many later cells depend on exact names.
- When adding variables, update both extraction lists and Phase 7 maps/sets (`UNIT_BY_VARIABLE`, validation sets, context maps) to avoid silent drops.
- Keep QA artifacts in sync with any transformation-rule changes; they are part of the reproducibility contract.
- If you introduce new dependencies (e.g., `sqlalchemy`, `datacommons-client`, plotting libs), update `pyproject.toml` accordingly (current manifest is minimal vs actual notebook usage).

