#!/usr/bin/env Rscript
# Rebuild the whole analysis and report from the committed raw data.
#   Rscript run_all.R
# (Search collection is separate and optional — see pull/README.md.)

root <- normalizePath(dirname(sub("--file=", "",
  grep("--file=", commandArgs(FALSE), value = TRUE)[1])), mustWork = TRUE)

for (s in c("01_survey_noise.R", "02_search_analysis.R", "03_leadlag_placebo.R")) {
  message("\n=== ", s, " ===")
  system2("Rscript", file.path(root, "analysis", s))
}

message("\n=== rendering report ===")
rmarkdown::render(file.path(root, "analysis", "report.Rmd"), quiet = TRUE)

# GitHub Pages serves docs/index.html — keep it in sync with the report.
dir.create(file.path(root, "docs"), showWarnings = FALSE)
file.copy(file.path(root, "analysis", "report.html"),
          file.path(root, "docs", "index.html"), overwrite = TRUE)
message("Done: analysis/report.html (and docs/index.html for GitHub Pages)")
