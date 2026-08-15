# Core search<->survey analysis. Produces CSV outputs consumed by report.Rmd.
args_file <- grep("--file=", commandArgs(FALSE), value = TRUE)[1]
setwd(dirname(sub("--file=", "", args_file)))
source(file.path("R", "functions.R"))

survey <- load_survey() |> add_survey_shares()
trends <- load_trends("trends")
stopifnot(!is.null(trends))

# QA exclusions: near-zero-volume brands can't carry SoS information; keep them
# in SoS denominators only if they have volume. Also drop the collided category
# until the re-pull lands.
vol <- trends |>
  group_by(category_name, brand_name) |>
  summarise(mean_idx = mean(trends_index, na.rm = TRUE), .groups = "drop")
usable <- vol |> filter(mean_idx >= 0.5)
cat("Brands with measurable search volume:", nrow(usable), "of", nrow(vol), "\n")

sos <- trends |>
  semi_join(usable, by = c("category_name", "brand_name")) |>
  group_by(category_name, month) |>
  mutate(sos = trends_index / sum(trends_index, na.rm = TRUE)) |>
  ungroup()

joined <- survey |>
  inner_join(sos |> select(category_name, brand_name, month, trends_index, sos),
             by = c("category_name", "brand_name", "wave_date" = "month"))

# Recompute survey shares within the joined (searchable) brand set so both
# shares live on the same denominator.
joined <- joined |>
  group_by(category_name, wave_date) |>
  mutate(soc = consideration / sum(consideration, na.rm = TRUE),
         soa = awareness / sum(awareness, na.rm = TRUE),
         sop = preference / sum(preference, na.rm = TRUE)) |>
  ungroup() |>
  mutate(conversion = if_else(awareness > 0, consideration / awareness, NA_real_))

# ---- 1. Between-brand -------------------------------------------------------
between_brand <- joined |>
  group_by(category_name, brand_name) |>
  summarise(across(c(sos, soc, soa, sop, consideration, awareness, conversion),
                   ~ mean(.x, na.rm = TRUE)), waves = n(), .groups = "drop")

between_cat <- between_brand |>
  group_by(category_name) |>
  filter(n() >= 4) |>
  summarise(n_brands = n(),
            rho_soc = cor(sos, soc, method = "spearman"),
            r_soc = cor(sos, soc),
            rho_aware = cor(sos, soa, method = "spearman"),
            rho_conv = cor(sos, conversion, method = "spearman",
                           use = "complete.obs"),
            .groups = "drop") |>
  arrange(desc(rho_soc))

# ---- 2. Within-brand (quarterly smoothed) -----------------------------------
q <- joined |>
  smooth_quarterly(c("sos", "soc", "consideration")) |>
  filter(!is.na(sos_q), !is.na(soc_q))

within_brand <- q |>
  group_by(category_name, brand_name) |>
  filter(n() >= 10, sd(sos_q) > 0, sd(soc_q) > 0) |>
  summarise(r_within = cor(sos_q, soc_q), n_q = n(), .groups = "drop")

# noise ceiling comparison
nd <- noise_decomposition(survey, "consideration")
within_brand <- within_brand |>
  left_join(nd |> select(category_name, brand_name, reliability, max_attainable_r),
            by = c("category_name", "brand_name"))

# panel regression with brand fixed effects, per category (standardized betas)
fe_beta <- q |>
  group_by(category_name) |>
  group_modify(~{
    d <- .x |> group_by(brand_name) |>
      mutate(sos_c = as.numeric(scale(sos_q)), soc_c = as.numeric(scale(soc_q))) |>
      ungroup() |> filter(is.finite(sos_c), is.finite(soc_c))
    if (nrow(d) < 30 || n_distinct(d$brand_name) < 3) return(tibble())
    m <- lm(soc_c ~ sos_c, data = d)
    tibble(beta = coef(m)[["sos_c"]],
           se = summary(m)$coefficients["sos_c", "Std. Error"],
           n = nrow(d))
  }) |> ungroup()

# ---- 3. Lead-lag ------------------------------------------------------------
leadlag <- map_dfr(-3:3, function(k) {
  q |>
    group_by(category_name, brand_name) |>
    arrange(wave_date, .by_group = TRUE) |>
    mutate(sos_l = if (k >= 0) lag(sos_q, k) else lead(sos_q, -k)) |>
    filter(!is.na(sos_l), !is.na(soc_q)) |>
    group_by(brand_name, category_name) |>
    filter(n() >= 10, sd(sos_l) > 0, sd(soc_q) > 0) |>
    summarise(r = cor(sos_l, soc_q), .groups = "drop") |>
    summarise(lag_months = k, mean_r = mean(r), median_r = median(r),
              n_brands = n())
})

# ---- 4. Category eligibility ------------------------------------------------
eligibility <- between_cat |>
  left_join(vol |> group_by(category_name) |>
              summarise(pct_searchable = mean(mean_idx >= 0.5)), by = "category_name") |>
  left_join(within_brand |> group_by(category_name) |>
              summarise(median_r_within = median(r_within)), by = "category_name") |>
  left_join(nd |> filter(waves >= 12) |> group_by(category_name) |>
              summarise(survey_reliability = mean(reliability, na.rm = TRUE)),
            by = "category_name")

dir.create("out", showWarnings = FALSE)
write_csv(between_brand, "out/between_brand.csv")
write_csv(between_cat, "out/between_category.csv")
write_csv(within_brand, "out/within_brand.csv")
write_csv(fe_beta, "out/fe_beta.csv")
write_csv(leadlag, "out/leadlag.csv")
write_csv(eligibility, "out/eligibility.csv")

cat("\n== Between-brand: spearman(SoS, share of consideration) ==\n")
cat("median rho:", round(median(between_cat$rho_soc, na.rm = TRUE), 2),
    "| categories with rho >= 0.7:", sum(between_cat$rho_soc >= .7, na.rm = TRUE),
    "of", nrow(between_cat), "\n")
cat("\n== Within-brand: quarterly r, all brands ==\n")
print(summary(within_brand$r_within))
cat("mean attainable ceiling:", round(mean(within_brand$max_attainable_r, na.rm = TRUE), 2), "\n")
cat("\n== FE betas (per category, standardized) ==\n")
print(summary(fe_beta$beta))
cat("\n== Lead-lag (mean within-brand r by SoS lag) ==\n")
print(leadlag)
