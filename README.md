# MENA COVID and Resilience ELT Analysis

Notebook-first capstone project for analyzing the socioeconomic and health impact of COVID-19 across a fixed 16-country MENA scope.

The project builds a reproducible ELT flow from Google Data Commons into a local PostgreSQL warehouse, then produces curated analysis tables, QA artifacts, clustering outputs, and short-term forecasts.

## What’s in this repo

- `data_pipeline_stage_1.ipynb`: extraction, normalization, and warehouse loading
- `data_pipeline_stage_2.ipynb`: transformation, QA, clustering, and analysis-ready views
- `stage_3_forecasting.R`: forecasting pipeline that reads from Postgres or transformed files
- `main.tex`: dissertation write-up
- `references.bib`: bibliography for the dissertation
- `transformed/`: generated outputs, plots, tables, and forecast artifacts
- `*.joblib`: serialized analysis views used by later stages

## Study scope

The analysis is restricted to 16 MENA countries:

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

Cyprus is intentionally excluded from the study scope.

## Pipeline overview

### Stage 1: Extract and load

The first notebook fetches indicator series from Data Commons, standardizes them to a long observation contract, and loads them into PostgreSQL using a star-schema warehouse.

Core warehouse tables:

- `dw.dim_country`
- `dw.dim_indicator`
- `dw.dim_source`
- `dw.fact_observation`

### Stage 2: Transform and analyze

The second notebook builds the curated views used for reporting and modeling, including:

- `mart_panel_long`
- `mart_panel_yearly`
- `mart_health_outcomes`
- `mart_vaccination`
- `mart_context`
- QA tables for missingness, completeness, coverage, and invalid values

It also supports clustering analysis and the sensitivity views used in the dissertation.

### Stage 3: Forecast

`stage_3_forecasting.R` generates country-level forecasts for COVID-related metrics.
By default it reads from PostgreSQL, but it can also consume transformed CSV files when available.

## Technology stack

### Python environment

- Python 3.11.9
- `pandas` 3.0.1
- `numpy` 2.4.3
- `matplotlib` 3.10.8
- `seaborn` 0.13.2
- `scikit-learn` 1.8.0
- `SQLAlchemy` 2.0.48
- `psycopg2-binary` 2.9.11
- `joblib` 1.5.3
- `datacommons-client` 2.1.6
- `ipykernel` / `jupyter` for notebook execution

### R environment

The forecasting script uses:

- `dplyr`
- `tidyr`
- `stringr`
- `readr`
- `lubridate`
- `purrr`
- `forecast`
- `ggplot2`

## Prerequisites

- Python 3.11 with a virtual environment
- Jupyter Notebook or VS Code notebook support
- PostgreSQL running locally or remotely with access to the `dw` schema
- R with the packages listed above for forecasting

## How to run

### 1. Set up Python

Activate the project virtual environment if it exists:

```bash
source .venv/bin/activate
```

### 2. Run Stage 1

Open `data_pipeline_stage_1.ipynb` and execute the cells in order.
This stage extracts source series, normalizes them, and loads the warehouse.

### 3. Run Stage 2

Open `data_pipeline_stage_2.ipynb` and run the bootstrap cell first.
This rebuilds the expected Stage 1 frames from the warehouse so the notebook can continue with transformations, QA, and clustering.

### 4. Run Stage 3 forecasting

Execute the R script from the repository root:

```bash
Rscript stage_3_forecasting.R
```

Optional arguments are supported, for example:

```bash
Rscript stage_3_forecasting.R --horizon 6 --out-dir transformed
Rscript stage_3_forecasting.R --source postgres
Rscript stage_3_forecasting.R --source file --input transformed/ds_unbalanced_panel.csv
```

## Main outputs

Generated artifacts are written to `transformed/` and include:

- clustered-country summaries
- feature matrices and PCA outputs
- silhouette diagnostics
- cluster profile heatmaps
- robustness comparison plots
- Stage 3 forecast tables and plots

## Notes

- The repository is notebook-first; `main.py` is template code and not part of the active pipeline.
- The dissertation source in `main.tex` is tied to the same analysis flow described in the notebooks.
- The pipeline enforces a fixed 16-country allowlist and uses tiered missingness rules before downstream modeling.

## Suggested citation context

If you describe the project in reports or presentations, a concise summary is:

> A notebook-first ELT pipeline for MENA COVID-19 analysis, combining Data Commons extraction, PostgreSQL warehousing, curated marts, QA checks, clustering, and ARIMA-based forecasting.
