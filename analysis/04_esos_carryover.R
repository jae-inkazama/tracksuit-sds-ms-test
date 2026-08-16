# Excess Share of Search + carryover ("mini-MMM").
#
# Two marketing-science questions, deliberately simple:
#   1. ESoS: does a brand searched for MORE than its consideration share would
#      imply go on to gain consideration? (Binet & Field's excess-share-of-voice
#      logic, applied to search.)
#   2. Carryover: search today doesn't move claimed consideration today. How
#      fast does it feed through? Estimated with a standard geometric adstock.
args_file <- grep("--file=", commandArgs(FALSE), value = TRUE)[1]
setwd(dirname(sub("--file=", "", args_file)))
source(file.path("R", "functions.R"))

survey <- load_survey()
trends <- load_trends("trends")
stopifnot(!is.null(trends))

VOL_MIN <- 0.5

# ---- Build the panel: share of search and share of consideration ------------
vol <- trends |>
  group_by(category_name, brand_name) |>
  summarise(mean_idx = mean(trends_index, na.rm = TRUE), .groups = "drop")

panel <- trends |>
  semi_join(filter(vol, mean_idx >= VOL_MIN), by = c("category_name", "brand_name")) |>
  group_by(category_name, month) |>
  mutate(sos = trends_index / sum(trends_index, na.rm = TRUE)) |>
  ungroup() |>
  inner_join(survey, by = c("category_name", "brand_name", "month" = "wave_date")) |>
  group_by(category_name, month) |>
  mutate(soc = consideration / sum(consideration, na.rm = TRUE)) |>
  ungroup() |>
  arrange(category_name, brand_name, month)

# Quarterly averages: monthly survey readings are too noisy to difference.
qtr <- panel |>
  mutate(q = as.Date(cut(month, "quarter"))) |>
  group_by(category_name, brand_name, q) |>
  summarise(sos = mean(sos), soc = mean(soc),
            consideration = mean(consideration), awareness = mean(awareness),
            n_months = n(), .groups = "drop") |>
  filter(n_months >= 2) |>
  arrange(category_name, brand_name, q)

# ---- 1. Excess Share of Search ---------------------------------------------
# ESoS = share of search - share of consideration. Positive = brand is searched
# for more than its consideration share implies.
esos <- qtr |>
  group_by(category_name, brand_name) |>
  mutate(esos = sos - soc,
         soc_next = lead(soc, 2),          # two quarters ahead
         d_soc = soc_next - soc) |>
  ungroup() |>
  filter(!is.na(d_soc))

# Naive view: do positive-ESoS brands gain consideration share?
naive_split <- esos |>
  mutate(grp = if_else(esos > 0, "Searched more than considered",
                       "Considered more than searched")) |>
  group_by(grp) |>
  summarise(n = n(), mean_d_soc = mean(d_soc), .groups = "drop")

# Honest control: share-of-consideration mean-reverts, and ESoS is mechanically
# negative when SoC is high — so a raw ESoS effect is partly regression to the
# mean. Control for the starting level (and category).
m_naive <- lm(d_soc ~ esos, data = esos)
m_ctrl  <- lm(d_soc ~ esos + soc, data = esos)
m_full  <- lm(d_soc ~ esos + soc + factor(category_name), data = esos)

esos_coefs <- tibble(
  model = c("ESoS only", "+ starting level", "+ starting level & category"),
  beta = c(coef(m_naive)[["esos"]], coef(m_ctrl)[["esos"]], coef(m_full)[["esos"]]),
  se = c(summary(m_naive)$coefficients["esos", 2],
         summary(m_ctrl)$coefficients["esos", 2],
         summary(m_full)$coefficients["esos", 2])
) |> mutate(t = beta / se)

# ---- 2. Carryover / adstock -------------------------------------------------
# Geometric adstock: A_t = S_t + lambda * A_{t-1}. Grid-search lambda on the
# pooled within-brand fit; report the implied half-life.
# Normalised geometric adstock: A_t = (1-lambda)*S_t + lambda*A_{t-1}.
# Normalising matters — the textbook unnormalised form (S_t + lambda*A_{t-1})
# inflates the series as lambda rises, so a grid search on it just picks the
# lambda that manufactures the strongest trend, not the true carryover.
adstock <- function(x, lambda) {
  out <- numeric(length(x))
  out[1] <- x[1]
  for (i in seq_along(x)[-1]) out[i] <- (1 - lambda) * x[i] + lambda * out[i - 1]
  out
}

grid <- seq(0, 0.9, by = 0.1)
fit_lambda <- function(lambda) {
  d <- qtr |>
    group_by(category_name, brand_name) |>
    filter(n() >= 6) |>
    mutate(a = adstock(sos, lambda),
           a_z = as.numeric(scale(a)), soc_z = as.numeric(scale(soc))) |>
    ungroup() |>
    filter(is.finite(a_z), is.finite(soc_z))
  m <- lm(soc_z ~ a_z, data = d)
  tibble(lambda = lambda, r2 = summary(m)$r.squared,
         beta = coef(m)[["a_z"]], n = nrow(d))
}
carry <- purrr::map_dfr(grid, fit_lambda)
best <- carry |> slice_max(r2, n = 1)
half_life_q <- if (best$lambda > 0) log(0.5) / log(best$lambda) else 0

dir.create("out", showWarnings = FALSE)
readr::write_csv(esos, "out/esos_panel.csv")
readr::write_csv(esos_coefs, "out/esos_models.csv")
readr::write_csv(carry, "out/carryover_grid.csv")

cat("== Excess Share of Search ==\n")
print(naive_split)
cat("\nEffect of ESoS on change in share of consideration (2 quarters ahead):\n")
print(esos_coefs |> mutate(across(where(is.numeric), ~ round(.x, 3))))
cat("\n== Carryover (quarterly adstock) ==\n")
print(carry |> mutate(across(where(is.numeric), ~ round(.x, 4))))
cat("\nBest decay lambda:", best$lambda,
    "| implied half-life:", round(half_life_q, 2), "quarters (",
    round(half_life_q * 3, 1), "months )\n")
