# Placebo check for the lead-lag finding: if the 2-3 month lead of SoS over
# consideration is real brand-level signal, it must vanish when SoS series are
# reassigned to the *wrong* brand within the same category (which preserves
# category-level seasonality and common shocks, but breaks the brand link).
args_file <- grep("--file=", commandArgs(FALSE), value = TRUE)[1]
setwd(dirname(sub("--file=", "", args_file)))
source(file.path("R", "functions.R"))
set.seed(2026)

survey <- load_survey() |> add_survey_shares()
trends <- load_trends("trends")
stopifnot(!is.null(trends))

vol <- trends |>
  group_by(category_name, brand_name) |>
  summarise(mean_idx = mean(trends_index, na.rm = TRUE), .groups = "drop")
sos <- trends |>
  semi_join(vol |> filter(mean_idx >= 0.5), by = c("category_name", "brand_name")) |>
  group_by(category_name, month) |>
  mutate(sos = trends_index / sum(trends_index, na.rm = TRUE)) |>
  ungroup()
joined <- survey |>
  inner_join(sos |> select(category_name, brand_name, month, sos),
             by = c("category_name", "brand_name", "wave_date" = "month")) |>
  group_by(category_name, wave_date) |>
  mutate(soc = consideration / sum(consideration, na.rm = TRUE)) |>
  ungroup()

leadlag_curve <- function(df) {
  q <- df |> smooth_quarterly(c("sos", "soc")) |> filter(!is.na(sos_q), !is.na(soc_q))
  purrr::map_dfr(-3:3, function(k) {
    q |>
      group_by(category_name, brand_name) |>
      arrange(wave_date, .by_group = TRUE) |>
      mutate(sos_l = if (k >= 0) lag(sos_q, k) else lead(sos_q, -k)) |>
      filter(!is.na(sos_l), !is.na(soc_q)) |>
      group_by(category_name, brand_name) |>
      filter(n() >= 10, sd(sos_l) > 0, sd(soc_q) > 0) |>
      summarise(r = cor(sos_l, soc_q), .groups = "drop") |>
      summarise(lag_months = k, mean_r = mean(r), n_brands = n())
  })
}

real <- leadlag_curve(joined) |> mutate(run = "real")

# Placebo: within each category, permute which brand each SoS series belongs to.
N_PERM <- 100
placebos <- purrr::map_dfr(seq_len(N_PERM), function(i) {
  perm <- joined |> distinct(category_name, brand_name) |>
    group_by(category_name) |>
    mutate(brand_shuffled = sample(brand_name)) |>
    ungroup()
  ph <- joined |>
    select(category_name, brand_name, wave_date, sos) |>
    left_join(perm, by = c("category_name", "brand_name")) |>
    select(category_name, brand_name = brand_shuffled, wave_date, sos_placebo = sos)
  joined |>
    select(-sos) |>
    inner_join(ph, by = c("category_name", "brand_name", "wave_date")) |>
    rename(sos = sos_placebo) |>
    leadlag_curve() |>
    mutate(run = paste0("placebo_", i))
})

out <- bind_rows(real, placebos)
readr::write_csv(out, "out/leadlag_placebo.csv")

ps <- placebos |> group_by(lag_months) |>
  summarise(placebo_mean = mean(mean_r), placebo_hi = quantile(mean_r, .975),
            placebo_lo = quantile(mean_r, .025), .groups = "drop") |>
  left_join(real |> select(lag_months, real_r = mean_r), by = "lag_months")
print(ps)
lead_gain_real <- with(real, mean_r[lag_months == 2] - mean_r[lag_months == -2])
lead_gain_plac <- placebos |> group_by(run) |>
  summarise(g = mean_r[lag_months == 2] - mean_r[lag_months == -2]) |> pull(g)
cat("\nLead asymmetry (r at +2 minus r at -2): real =", round(lead_gain_real, 3),
    "| placebo mean =", round(mean(lead_gain_plac), 3),
    "| placebo 97.5th pct =", round(quantile(lead_gain_plac, .975), 3), "\n")
cat("Placebo runs exceeding real asymmetry:", sum(lead_gain_plac >= lead_gain_real),
    "of", length(lead_gain_plac), "\n")
