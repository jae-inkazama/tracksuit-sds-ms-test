# Shared functions for the Share-of-Search study.
suppressMessages({
  library(tidyverse)
  library(zoo)
})

# Repo root: walk up from the working directory until we find the survey CSV.
find_root <- function(start = getwd()) {
  d <- normalizePath(start, mustWork = FALSE)
  for (i in 1:5) {
    if (file.exists(file.path(d, "sample-category-data.csv"))) return(d)
    d <- dirname(d)
  }
  stop("Could not locate repo root (sample-category-data.csv) above ", start)
}
ROOT <- find_root()

# ---- Survey side ------------------------------------------------------------

load_survey <- function(path = file.path(ROOT, "sample-category-data.csv")) {
  read_csv(path, show_col_types = FALSE,
           col_types = cols(WEIGHT_1 = col_double(),
                            BASE_WEIGHT_1 = col_double(),
                            PERCENTAGE_1 = col_double(),
                            WAVE_DATE = col_date())) |>
    rename_with(tolower) |>
    mutate(wave_date = as.Date(wave_date)) |>
    pivot_wider(
      id_cols = c(category_name, brand_name, wave_date, base_weight_1),
      names_from = std_question,
      values_from = percentage_1
    ) |>
    rename(
      awareness = PROMPTED_AWARENESS,
      consideration = CONSIDERATION,
      preference = PREFERENCE,
      base_n = base_weight_1
    )
}

# Sampling standard error of a proportion given the (weight-based) base.
# base_weight approximates the qualified sample size; this understates the true
# SE if weighting adds design effect, so treat as a lower bound on noise.
se_prop <- function(p, n) sqrt(pmax(p * (1 - p), 0) / pmax(n, 1))

# Per brand: decompose observed variance of a metric over time into sampling
# noise vs. plausible true signal. Returns reliability = signal / observed.
noise_decomposition <- function(df, metric = "consideration") {
  df |>
    group_by(category_name, brand_name) |>
    summarise(
      waves = n(),
      mean_p = mean(.data[[metric]], na.rm = TRUE),
      obs_var = var(.data[[metric]], na.rm = TRUE),
      noise_var = mean(se_prop(.data[[metric]], base_n)^2, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      signal_var = pmax(obs_var - noise_var, 0),
      reliability = if_else(obs_var > 0, signal_var / obs_var, NA_real_),
      # max correlation observable against a noiseless covariate
      max_attainable_r = sqrt(pmax(reliability, 0))
    )
}

# Survey-side share metrics within category-wave (for comparability with SoS).
add_survey_shares <- function(df) {
  df |>
    group_by(category_name, wave_date) |>
    mutate(
      share_of_consideration = consideration / sum(consideration, na.rm = TRUE),
      share_of_awareness = awareness / sum(awareness, na.rm = TRUE),
      share_of_preference = preference / sum(preference, na.rm = TRUE)
    ) |>
    ungroup()
}

# ---- Search side ------------------------------------------------------------

load_trends <- function(tier = "trends",
                        path = file.path(ROOT, "data", "raw", tier, "all_stitched.csv")) {
  if (!file.exists(path)) return(NULL)
  read_csv(path, show_col_types = FALSE) |>
    mutate(month = as.Date(month))
}

# Share of Search within category-month (excluding brands flagged unusable).
add_sos <- function(trends, exclude = character()) {
  trends |>
    filter(!paste(category_name, brand_name) %in% exclude) |>
    group_by(category_name, month) |>
    mutate(sos = trends_index / sum(trends_index, na.rm = TRUE)) |>
    ungroup()
}

# Join search to survey on category/brand/month.
join_search_survey <- function(survey, trends) {
  survey |>
    inner_join(trends, by = c("category_name", "brand_name",
                              "wave_date" = "month"))
}

# Quarterly smoothing: 3-month rolling means to tame ±3pp survey noise.
smooth_quarterly <- function(df, cols) {
  df |>
    arrange(category_name, brand_name, wave_date) |>
    group_by(category_name, brand_name) |>
    mutate(across(all_of(cols),
                  ~ zoo::rollmean(.x, 3, fill = NA, align = "right"),
                  .names = "{.col}_q")) |>
    ungroup()
}
