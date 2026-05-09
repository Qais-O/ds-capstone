#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readr)
  library(lubridate)
  library(purrr)
  library(forecast)
  library(ggplot2)
})

# ------------------------------
# Stage 3 forecasting (country x COVID metric)
# ------------------------------
# Usage examples:
#   Rscript stage_3_forecasting.R
#   Rscript stage_3_forecasting.R --horizon 6 --out-dir transformed
#   Rscript stage_3_forecasting.R --input transformed/ds_unbalanced_panel.csv
#   Rscript stage_3_forecasting.R --source postgres
#   Rscript stage_3_forecasting.R --aggregate month --max-series 120
#
# Data source behavior:
# - --source postgres (default): always pull from dw.* in Postgres.
# - --source file: use --input or known transformed CSV candidates only.
# - --source auto: prefer file if available, otherwise Postgres.

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  out <- list(
    input = NA_character_,
    source = "postgres",
    horizon = 6L,
    out_dir = "transformed",
    min_points = 12L,
    max_plots = 40L,
    aggregate = "month",
    max_series = 200L,
    arima_approximation = TRUE,
    arima_stepwise = TRUE
  )

  i <- 1
  while (i <= length(args)) {
    key <- args[[i]]
    val <- if (i < length(args)) args[[i + 1]] else NA_character_

    if (key == "--input") out$input <- val
    if (key == "--source") out$source <- tolower(val)
    if (key == "--horizon") out$horizon <- as.integer(val)
    if (key == "--out-dir") out$out_dir <- val
    if (key == "--min-points") out$min_points <- as.integer(val)
    if (key == "--max-plots") out$max_plots <- as.integer(val)
    if (key == "--aggregate") out$aggregate <- tolower(val)
    if (key == "--max-series") out$max_series <- as.integer(val)
    if (key == "--arima-approximation") out$arima_approximation <- tolower(val) == "true"
    if (key == "--arima-stepwise") out$arima_stepwise <- tolower(val) == "true"

    i <- i + 2
  }

  if (!out$source %in% c("postgres", "file", "auto")) {
    stop("Invalid --source value. Use one of: postgres, file, auto")
  }

  if (!out$aggregate %in% c("none", "month", "quarter")) {
    stop("Invalid --aggregate value. Use one of: none, month, quarter")
  }

  out
}

ensure_out_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

find_input_file <- function(cli_input) {
  if (!is.na(cli_input) && file.exists(cli_input)) return(cli_input)

  candidates <- c(
    "transformed/ds_unbalanced_panel.csv",
    "transformed/ds_balanced_core.csv",
    "transformed/mart_panel_yearly.csv",
    "transformed/mart_health_outcomes.csv",
    "transformed/mart_panel_long.csv"
  )

  for (p in candidates) {
    if (file.exists(p)) return(p)
  }

  NA_character_
}

safe_as_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  out <- suppressWarnings(as.Date(x))
  if (all(is.na(out))) {
    out <- suppressWarnings(as.Date(parse_date_time(x, orders = c("ymd", "Y-m-d", "Y/m/d", "ym", "Y"))))
  }
  out
}

resolve_country_col <- function(df) {
  cands <- c("country", "entity", "country_id", "iso_code", "country_code")
  hit <- cands[cands %in% names(df)]
  if (length(hit) == 0) stop("Could not resolve country column in input dataset.")
  hit[[1]]
}

resolve_date_col <- function(df) {
  cands <- c("date", "observation_date", "month", "year_date", "year")
  hit <- cands[cands %in% names(df)]
  if (length(hit) == 0) stop("Could not resolve date column in input dataset.")
  hit[[1]]
}

build_panel_from_dw <- function() {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RPostgres", quietly = TRUE)) {
    stop("No input CSV found and DBI/RPostgres are unavailable. Install DBI and RPostgres or provide --input.")
  }

  host <- Sys.getenv("PGHOST", unset = "localhost")
  port <- as.integer(Sys.getenv("PGPORT", unset = "5432"))
  dbname <- Sys.getenv("PGDATABASE", unset = "postgres")
  user <- Sys.getenv("PGUSER", unset = "postgres")
  password <- Sys.getenv("PGPASSWORD", unset = "postgres")

  message("Pulling panel directly from Postgres dw.* ...")

  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = host,
    port = port,
    dbname = dbname,
    user = user,
    password = password
  )
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  sql <- "
    SELECT
      c.country_name AS country,
      c.iso_code AS iso_code,
      f.observation_date::date AS date,
      i.indicator_dcid,
      f.value::double precision AS value
    FROM dw.fact_observation f
    JOIN dw.dim_country c ON c.country_key = f.country_key
    JOIN dw.dim_indicator i ON i.indicator_key = f.indicator_key
    WHERE i.indicator_dcid IN (
      'CumulativeCount_MedicalConditionIncident_COVID_19_ConfirmedCase',
      'CumulativeCount_MedicalConditionIncident_COVID_19_PatientDeceased',
      'Count_Person',
      'Count_MedicalConditionIncident_COVID19_AtLeastOneVaccineDose_AsAFractionOf_Count_MedicalConditionIncident_COVID19',
      'Count_MedicalConditionIncident_COVID19_CompletedPrimaryVaccineDose_AsAFractionOf_Count_MedicalConditionIncident_COVID19',
      'Count_MedicalConditionIncident_COVID19_BoosterVaccineDose_AsAFractionOf_Count_MedicalConditionIncident_COVID19'
    )
  "

  raw <- DBI::dbGetQuery(con, sql)
  if (nrow(raw) == 0) {
    stop("dw query returned no rows. Run Stage 1/2 load first or provide --input CSV.")
  }

  wide <- raw %>%
    mutate(date = as.Date(date)) %>%
    group_by(country, iso_code, date, indicator_dcid) %>%
    summarise(value = median(value, na.rm = TRUE), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = indicator_dcid, values_from = value)

  out <- wide %>%
    mutate(
      cases_per_million = if_else(
        !is.na(`CumulativeCount_MedicalConditionIncident_COVID_19_ConfirmedCase`) & !is.na(Count_Person) & Count_Person > 0,
        `CumulativeCount_MedicalConditionIncident_COVID_19_ConfirmedCase` / Count_Person * 1e6,
        NA_real_
      ),
      deaths_per_million = if_else(
        !is.na(`CumulativeCount_MedicalConditionIncident_COVID_19_PatientDeceased`) & !is.na(Count_Person) & Count_Person > 0,
        `CumulativeCount_MedicalConditionIncident_COVID_19_PatientDeceased` / Count_Person * 1e6,
        NA_real_
      ),
      case_fatality_rate_pct = if_else(
        !is.na(`CumulativeCount_MedicalConditionIncident_COVID_19_PatientDeceased`) &
          !is.na(`CumulativeCount_MedicalConditionIncident_COVID_19_ConfirmedCase`) &
          `CumulativeCount_MedicalConditionIncident_COVID_19_ConfirmedCase` > 0,
        `CumulativeCount_MedicalConditionIncident_COVID_19_PatientDeceased` /
          `CumulativeCount_MedicalConditionIncident_COVID_19_ConfirmedCase` * 100,
        NA_real_
      ),
      vax_at_least_one_pct = `Count_MedicalConditionIncident_COVID19_AtLeastOneVaccineDose_AsAFractionOf_Count_MedicalConditionIncident_COVID19` * 100,
      vax_primary_pct = `Count_MedicalConditionIncident_COVID19_CompletedPrimaryVaccineDose_AsAFractionOf_Count_MedicalConditionIncident_COVID19` * 100,
      vax_booster_pct = `Count_MedicalConditionIncident_COVID19_BoosterVaccineDose_AsAFractionOf_Count_MedicalConditionIncident_COVID19` * 100
    ) %>%
    select(
      country,
      iso_code,
      date,
      cases_per_million,
      deaths_per_million,
      case_fatality_rate_pct,
      vax_at_least_one_pct,
      vax_primary_pct,
      vax_booster_pct
    )

  out
}

get_candidate_metrics <- function(df) {
  covid_regex <- "covid|case|death|fatality|cfr|vax|vaccin|booster|per_million"
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  metrics <- num_cols[str_detect(num_cols, regex(covid_regex, ignore_case = TRUE))]
  unique(metrics)
}

infer_frequency <- function(dates) {
  d <- sort(unique(as.Date(dates)))
  if (length(d) < 3) return(list(freq = 12L, label = "monthly"))

  median_gap <- median(as.numeric(diff(d)), na.rm = TRUE)
  if (is.na(median_gap)) return(list(freq = 12L, label = "monthly"))
  if (median_gap <= 45) return(list(freq = 12L, label = "monthly"))
  if (median_gap <= 120) return(list(freq = 4L, label = "quarterly"))
  list(freq = 1L, label = "yearly")
}

rmse <- function(actual, pred) sqrt(mean((actual - pred) ^ 2, na.rm = TRUE))
mae <- function(actual, pred) mean(abs(actual - pred), na.rm = TRUE)

pre_aggregate <- function(df, date_col, metric_cols, aggregate = "month") {
  out <- df
  out[[date_col]] <- safe_as_date(out[[date_col]])
  out <- out %>% filter(!is.na(.data[[date_col]]))

  if (aggregate == "none") return(out)

  out <- out %>%
    mutate(
      .agg_date = if (aggregate == "quarter") {
        floor_date(.data[[date_col]], unit = "quarter")
      } else {
        floor_date(.data[[date_col]], unit = "month")
      }
    )

  group_cols <- setdiff(names(out), metric_cols)
  group_cols <- setdiff(group_cols, date_col)
  group_cols <- setdiff(group_cols, ".agg_date")
  group_syms <- lapply(c(group_cols, ".agg_date"), rlang::sym)

  out <- out %>%
    group_by(!!!group_syms) %>%
    summarise(across(all_of(metric_cols), ~ median(as.numeric(.x), na.rm = TRUE)), .groups = "drop") %>%
    rename(!!date_col := .agg_date)

  out
}

forecast_one_series <- function(
  df,
  country_col,
  date_col,
  metric_col,
  horizon,
  min_points,
  arima_approximation = TRUE,
  arima_stepwise = TRUE
) {
  x <- df %>%
    select(all_of(c(country_col, date_col, metric_col))) %>%
    rename(country = all_of(country_col), date = all_of(date_col), value = all_of(metric_col)) %>%
    mutate(date = safe_as_date(date), value = as.numeric(value)) %>%
    filter(!is.na(country), !is.na(date), !is.na(value)) %>%
    arrange(country, date)

  if (nrow(x) == 0) return(list(fc = tibble(), metrics = tibble()))

  split_by_country <- split(x, x$country)

  fc_rows <- list()
  metric_rows <- list()
  total_countries <- length(split_by_country)
  processed <- 0L

  for (cn in names(split_by_country)) {
    processed <- processed + 1L
    if (processed %% 10L == 0L || processed == total_countries) {
      message("  [", metric_col, "] country ", processed, "/", total_countries, ": ", cn)
    }

    g <- split_by_country[[cn]] %>% arrange(date)
    g <- g %>% group_by(date) %>% summarise(value = median(value, na.rm = TRUE), .groups = "drop")

    if (nrow(g) < min_points) next

    freq_info <- infer_frequency(g$date)
    n <- nrow(g)
    h_eval <- min(horizon, max(1L, floor(n * 0.2)))

    train_vals <- g$value[1:(n - h_eval)]
    test_vals <- g$value[(n - h_eval + 1):n]
    ts_train <- ts(train_vals, frequency = freq_info$freq)

    fit <- tryCatch({
      auto.arima(ts_train, stepwise = arima_stepwise, approximation = arima_approximation)
    }, error = function(e) {
      Arima(ts_train, order = c(0, 1, 1))
    })

    eval_fc <- forecast(fit, h = h_eval)
    pred_eval <- as.numeric(eval_fc$mean)

    metric_rows[[length(metric_rows) + 1L]] <- tibble(
      country = cn,
      metric = metric_col,
      frequency = freq_info$label,
      train_points = length(train_vals),
      test_points = length(test_vals),
      rmse = rmse(test_vals, pred_eval),
      mae = mae(test_vals, pred_eval),
      mape = mean(abs((test_vals - pred_eval) / ifelse(test_vals == 0, NA_real_, test_vals)), na.rm = TRUE) * 100
    )

    full_ts <- ts(g$value, frequency = freq_info$freq)
    full_fit <- tryCatch({
      auto.arima(full_ts, stepwise = arima_stepwise, approximation = arima_approximation)
    }, error = function(e) {
      Arima(full_ts, order = c(0, 1, 1))
    })

    future <- forecast(full_fit, h = horizon)
    start_date <- max(g$date)
    by_unit <- if (freq_info$freq == 12L) "month" else if (freq_info$freq == 4L) "quarter" else "year"
    future_dates <- seq.Date(from = start_date, by = by_unit, length.out = horizon + 1)[-1]

    fc_rows[[length(fc_rows) + 1L]] <- tibble(
      country = cn,
      metric = metric_col,
      frequency = freq_info$label,
      date = future_dates,
      forecast = as.numeric(future$mean),
      lo_80 = as.numeric(future$lower[, 1]),
      hi_80 = as.numeric(future$upper[, 1]),
      lo_95 = as.numeric(future$lower[, 2]),
      hi_95 = as.numeric(future$upper[, 2])
    )

    fc_rows[[length(fc_rows) + 1L]] <- tibble(
      country = cn,
      metric = metric_col,
      frequency = freq_info$label,
      date = g$date,
      forecast = g$value,
      lo_80 = NA_real_,
      hi_80 = NA_real_,
      lo_95 = NA_real_,
      hi_95 = NA_real_
    ) %>% mutate(series_type = "history")

    fc_rows[[length(fc_rows)]]$series_type <- "history"
    fc_rows[[length(fc_rows) - 1L]]$series_type <- "forecast"
  }

  fc_tbl <- bind_rows(fc_rows)
  metric_tbl <- bind_rows(metric_rows)

  list(fc = fc_tbl, metrics = metric_tbl)
}

plot_forecasts <- function(fc_tbl, out_dir, max_plots = 40L) {
  if (nrow(fc_tbl) == 0) return(invisible(NULL))

  combos <- fc_tbl %>% distinct(country, metric)
  if (nrow(combos) > max_plots) combos <- combos[1:max_plots, , drop = FALSE]

  plot_rows <- list()
  for (i in seq_len(nrow(combos))) {
    cc <- combos$country[[i]]
    mm <- combos$metric[[i]]
    sub <- fc_tbl %>% filter(country == cc, metric == mm)
    if (nrow(sub) == 0) next
    plot_rows[[length(plot_rows) + 1L]] <- sub
  }

  plot_df <- bind_rows(plot_rows)
  if (nrow(plot_df) == 0) return(invisible(NULL))

  p <- ggplot(plot_df, aes(x = date, y = forecast, color = series_type)) +
    geom_line(linewidth = 0.6) +
    geom_ribbon(
      data = subset(plot_df, series_type == "forecast"),
      aes(x = date, ymin = lo_95, ymax = hi_95, group = interaction(country, metric)),
      inherit.aes = FALSE,
      fill = "steelblue",
      alpha = 0.15
    ) +
    facet_wrap(~ country + metric, scales = "free_y") +
    scale_color_manual(values = c(history = "black", forecast = "#1f77b4")) +
    labs(
      title = "Stage 3 Forecasts by Country and COVID Metric",
      x = "Date",
      y = "Value",
      color = "Series"
    ) +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom")

  # Show plot in RStudio/interactive sessions.
  if (interactive()) {
    print(p)
  }

  ggsave(file.path(out_dir, "stage3_forecast_panels.png"), p, width = 16, height = 10, dpi = 220)
}

main <- function() {
  cfg <- parse_args()
  ensure_out_dir(cfg$out_dir)

  input_path <- NA_character_
  if (cfg$source == "postgres") {
    df <- build_panel_from_dw()
    input_path <- "dw_query"
  } else if (cfg$source == "file") {
    input_path <- find_input_file(cfg$input)
    if (is.na(input_path)) {
      stop("--source file was requested, but no input file was found. Provide --input or create transformed panel CSVs.")
    }
    message("Using input file: ", input_path)
    df <- read_csv(input_path, show_col_types = FALSE)
  } else {
    input_path <- find_input_file(cfg$input)
    if (!is.na(input_path)) {
      message("Using input file: ", input_path)
      df <- read_csv(input_path, show_col_types = FALSE)
    } else {
      df <- build_panel_from_dw()
      input_path <- "dw_query"
    }
  }

  country_col <- resolve_country_col(df)
  date_col <- resolve_date_col(df)
  df[[date_col]] <- safe_as_date(df[[date_col]])

  metrics <- get_candidate_metrics(df)
  if (length(metrics) == 0) {
    stop("No COVID-related numeric columns detected for forecasting.")
  }

  df <- pre_aggregate(df, date_col = date_col, metric_cols = metrics, aggregate = cfg$aggregate)

  series_grid <- df %>%
    select(all_of(c(country_col, metrics))) %>%
    pivot_longer(cols = all_of(metrics), names_to = "metric", values_to = "value") %>%
    filter(!is.na(value)) %>%
    distinct(.data[[country_col]], metric)

  if (nrow(series_grid) > cfg$max_series) {
    keep <- series_grid %>% slice_head(n = cfg$max_series)
    df <- df %>%
      pivot_longer(cols = all_of(metrics), names_to = "metric", values_to = "value") %>%
      inner_join(keep, by = setNames(c(country_col, "metric"), c(country_col, "metric"))) %>%
      pivot_wider(names_from = metric, values_from = value)
    message("Capped workload to max series: ", cfg$max_series)
  }

  message("Country column: ", country_col)
  message("Date column: ", date_col)
  message("Aggregation: ", cfg$aggregate)
  message("ARIMA approximation: ", cfg$arima_approximation, " | stepwise: ", cfg$arima_stepwise)
  message("Metrics selected: ", paste(metrics, collapse = ", "))

  all_fc <- list()
  all_metrics <- list()

  for (m in metrics) {
    message("Running metric: ", m)
    res <- forecast_one_series(
      df = df,
      country_col = country_col,
      date_col = date_col,
      metric_col = m,
      horizon = cfg$horizon,
      min_points = cfg$min_points,
      arima_approximation = cfg$arima_approximation,
      arima_stepwise = cfg$arima_stepwise
    )

    if (nrow(res$fc) > 0) all_fc[[length(all_fc) + 1L]] <- res$fc
    if (nrow(res$metrics) > 0) all_metrics[[length(all_metrics) + 1L]] <- res$metrics
  }

  forecasts_tbl <- bind_rows(all_fc)
  metrics_tbl <- bind_rows(all_metrics)

  if (nrow(forecasts_tbl) == 0) {
    stop("No forecasts produced. Check data coverage and lower --min-points if needed.")
  }

  forecasts_tbl <- forecasts_tbl %>%
    mutate(source = input_path) %>%
    arrange(country, metric, date, series_type)

  metrics_tbl <- metrics_tbl %>%
    mutate(source = input_path) %>%
    arrange(metric, country)

  write_csv(forecasts_tbl, file.path(cfg$out_dir, "stage3_forecasts.csv"))
  write_csv(metrics_tbl, file.path(cfg$out_dir, "stage3_model_metrics.csv"))

  plot_forecasts(forecasts_tbl, cfg$out_dir, cfg$max_plots)

  message("Forecast rows: ", nrow(forecasts_tbl))
  message("Model-eval rows: ", nrow(metrics_tbl))
  message("Saved: ", file.path(cfg$out_dir, "stage3_forecasts.csv"))
  message("Saved: ", file.path(cfg$out_dir, "stage3_model_metrics.csv"))
  message("Saved: ", file.path(cfg$out_dir, "stage3_forecast_panels.png"))
}

main()
