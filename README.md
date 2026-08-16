# Share of Search vs brand tracking — Tracksuit DS take-home

**[▶ Read the report](https://jae-inkazama.github.io/tracksuit-sds-ms-test/)**
· [source (`analysis/report.Rmd`)](analysis/report.Rmd)

A pilot study on whether Google search behaviour can complement or substitute
survey-based brand tracking, using the 50 Australian categories in
`sample-category-data.csv` and Google Trends data collected for all 507
brand-category pairs (Sep 2021 – Mar 2025).

## Headline

- **Ranking (between brands):** Share of Search reproduces the survey's
  competitive ranking well in roughly a third of categories and poorly in
  another third. Which is which is predictable, so the deliverable is a
  category *eligibility framework*, not a blanket yes/no.
- **Tracking (within brands over time):** inconclusive at monthly grain — and
  the binding constraint is the survey, not search. With ~200 respondents per
  category-wave, most monthly movement in consideration is sampling noise,
  capping the attainable correlation against *any* covariate at ≈0.48.
- **Leading indicator:** search leads consideration by 2–3 months. A
  100-permutation placebo test confirms the brand-level link is real but
  leaves the lead asymmetry suggestive (p ≈ 0.14), not established.
- **Recommendation:** complement, not substitute. Details and caveats in §8.

## Repository layout

| Path | What it is |
|---|---|
| `analysis/report.Rmd` → `report.html` | The study. Non-technical summary first, then method, results, validation, recommendation. |
| `analysis/R/functions.R` | Shared loaders, noise decomposition, SoS and smoothing helpers. |
| `analysis/01_survey_noise.R` | Survey-side noise/reliability decomposition (runs without search data). |
| `analysis/02_search_analysis.R` | Between-brand, within-brand, lead-lag, eligibility. Writes `analysis/out/*.csv`. |
| `analysis/03_leadlag_placebo.R` | 100-permutation brand-shuffle placebo for the lead-lag claim. |
| `pull/pull_trends.py` | Google Trends collection: entity resolution, anchor stitching, checkpointing. |
| `pull/terms_overrides.yaml` | Hand-curated search terms and rationale, per brand. |
| `data/raw/trends/` | Curated-tier pull: raw batch responses, per-category stitched series, resolution log. |
| `data/raw/trends.naive/` | Uncurated ablation (raw brand names) used in §7.1. |

## Reproducing

Search collection (Python; must run from a residential IP — Google blocks
datacenter ranges). Raw outputs are committed, so this step is optional:

```bash
cd pull
pip install -r requirements.txt
python pull_trends.py --all            # curated tier, ~60 min, checkpointed
python pull_trends.py --all --naive    # uncurated ablation
```

Analysis and report (R ≥ 4.3) — one command rebuilds everything from the
committed raw data:

```bash
Rscript -e 'install.packages(c("tidyverse","zoo","rmarkdown","knitr"))'
Rscript run_all.R
```

That runs the three analysis scripts in order and renders the report. To run a
step on its own:

```bash
Rscript analysis/01_survey_noise.R      # survey noise decomposition
Rscript analysis/02_search_analysis.R   # between/within/lead-lag/eligibility
Rscript analysis/03_leadlag_placebo.R   # 100-permutation placebo (~2 min)
Rscript -e 'rmarkdown::render("analysis/report.Rmd")'
```

Exact package versions used are recorded in
[`analysis/session-info.txt`](analysis/session-info.txt). The scripts are
order-dependent (02 and 03 write the CSVs the report reads) and locate the
repo root themselves, so they can be run from any working directory.

## Method notes

**Anchor stitching.** Google Trends returns a relative 0–100 index for at most
five terms per request, scaled within that request. To place every brand in a
category on one scale, the category's highest-awareness brand is included in
every batch as an anchor, and each batch is rescaled by the anchor's mean.
Batches where the anchor has no volume are flagged (`anchor-zero`); the final
dataset has none.

**Entity resolution.** Brand names are matched to Google knowledge-graph
entities where a credible one exists — the defence against homonyms (Koala the
mattress company vs the animal). Candidates are scored on title match and
entity type, with place-qualified and never-a-brand types (animal, city, film)
rejected. Any entity that returns an empty series is automatically re-pulled as
a raw term, so "no volume" means no demand rather than a bad identifier. Every
decision is written to `resolution_log.csv`.

**Caveats.** Single search source; relative not absolute indices; Australia
only; the SoS denominator covers only tracked brands; search intent within a
brand term is unresolvable without query-level data (Suncorp's banking searches
are counted alongside its insurance ones).
