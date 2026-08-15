# Survey-side pre-analysis: how much monthly movement is real vs sampling noise?
# Runs before any search data exists; results feed the report's methodology and
# set expectations for attainable search<->survey correlations.
source(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE)[1])), "R", "functions.R"))

survey <- load_survey()

# 1. Typical sampling SE by category (monthly, consideration)
se_summary <- survey |>
  mutate(se = se_prop(consideration, base_n)) |>
  group_by(category_name) |>
  summarise(median_base_n = median(base_n), median_se_pp = median(se) * 100,
            .groups = "drop") |>
  arrange(desc(median_se_pp))

# 2. Noise decomposition: what share of observed within-brand variance is signal?
nd <- noise_decomposition(survey, "consideration")

# 3. Category-level summary: mean reliability & attainable r, weighted by waves
nd_cat <- nd |>
  filter(waves >= 12) |>
  group_by(category_name) |>
  summarise(
    brands = n(),
    mean_reliability = mean(reliability, na.rm = TRUE),
    mean_max_r = mean(max_attainable_r, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(mean_reliability))

dir.create(file.path(ROOT, "analysis", "out"), showWarnings = FALSE, recursive = TRUE)
write_csv(se_summary, file.path(ROOT, "analysis", "out", "survey_se_by_category.csv"))
write_csv(nd, file.path(ROOT, "analysis", "out", "noise_decomposition_brand.csv"))
write_csv(nd_cat, file.path(ROOT, "analysis", "out", "noise_decomposition_category.csv"))

cat("Median monthly SE (consideration), pp:",
    round(median(se_summary$median_se_pp), 1), "\n")
cat("Share of brands where <50% of monthly variance is signal:",
    round(mean(nd$reliability < .5, na.rm = TRUE) * 100), "%\n")
cat("Pilot categories, mean attainable |r| vs a perfect covariate:\n")
pilots <- c("Fast Food", "Car Insurance", "Health & Beauty Retailers",
            "Furniture & Homeware", "Mattresses, beds, and pillows",
            "Chocolate", "Liquor Retailer", "Yoghurt")
print(nd_cat |> filter(category_name %in% pilots), n = 20)
