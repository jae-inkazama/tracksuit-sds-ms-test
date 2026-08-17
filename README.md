# Search + brand tracking — Tracksuit DS take-home 17-08-2026

**[▶ Read the report](https://jae-inkazama.github.io/tracksuit-sds-ms-test/)**
· [source (](analysis/report.Rmd)`analysis/report.Rmd`[)](analysis/report.Rmd)

A study on whether Google search behaviour can complement or substitute survey-based brand tracking, using the Australian Brasnd categories in `sample-category-data.csv` and Google Trends data collected for all 507
brand-category pairs (Sep 2021 – Mar 2025).

## My Main Insights/PArtial Insights

1. **Search reproduces the competitive ranking in some categories, and not in
  others.** It works well in roughly a third of the 50 categories and poorly in
   another third. Which is which is predictable in advance, so what this
   produces is a qualification test rather than a blanket yes or no.
2. **Month-to-month comparisons are too noisy to test on.** At around 200
  respondents a wave, about a quarter of the monthly movement in consideration
   is real brand movement. So I compare quarters. That is the resolution any
   monthly sample this size gives you, and it applies to anything you test
   against it, search included.
3. **There is a useful signal in the gap between the two.** Brands with a search surplus tend to have stronger subsequent consideration and preference
    over the next six months. primarily as a between-brand positioning signal rather than a within-brand forecast.
   And that can decide what you could actually build.
   

Search may run ahead of consideration, but this data cannot prove it. It is
also arguable that searching a brand *is* consideration, expressed as behaviour
rather than a survey answer. Either way, search sees the movement sooner.

**Recommendation:** complement, not substitute. Details and caveats in §9.

## What I haven't tested

Listing these because they are the places a reviewer should push, and because
knowing what is untested is part of the result.

- **No holdout.** The gap relationship is fitted and evaluated on the same
  data. Testing it on later waves it has not seen is the single next step, and
  the one that decides whether this is shippable.
- **Nothing here is causal.** Campaigns move search and consideration together;
  causation could run either way; and searching a brand may simply *be*
  consideration observed earlier. §8 sets out what would settle it — geo
  experiments, brand lift studies, or difference-in-differences around known
  campaign launches. An MMM would put a dollar value on the effect but would
  not prove it.
- **Share of search here is share of *tracked* brands**, not share of all
  category search. A six-brand category and a twenty-eight-brand category are
  not producing comparable denominators.
- **The 2–3 month lead is exploratory.** The carryover rate was chosen by
  fitting the same data, and the placebo puts the lead inside what shuffling
  can produce about one time in seven.
- **Search terms were hand-checked for 8 of 50 categories.** The weakest
  categories in §4 are measuring that, not consumer behaviour.
- **Search was collected monthly** because that is what Google returns for a
  43-month window. Weekly collection would let the lag be estimated properly.
- **Survey weights are treated as respondent counts**, which ignores design
  effect. True reliability is therefore lower than I report, which makes the
  noise argument stronger rather than weaker.
- **Not sized commercially.** A third of categories passing the gate is a rate,
  not a business case. How many current clients sit in eligible categories is
  the obvious next question.

## Next steps, in order

1. Holdout test on later waves.
2. Fix entity matching across the remaining 42 categories and re-run §4.
3. Re-collect search weekly so the lag can be estimated in weeks.
4. Size the eligible portion of the client base.
5. Design a geo or matched-market test with a willing client.

## Repository layout


| Path                                  | What it is                                                                                |
| ------------------------------------- | ----------------------------------------------------------------------------------------- |
| `analysis/report.Rmd` → `report.html` | The study. Non-technical summary first, then method, results, validation, recommendation. |
| `analysis/R/functions.R`              | Shared loaders, noise decomposition, SoS and smoothing helpers.                           |
| `analysis/01_survey_noise.R`          | Survey-side noise/reliability decomposition (runs without search data).                   |
| `analysis/02_search_analysis.R`       | Between-brand, within-brand, lead-lag, eligibility. Writes `analysis/out/*.csv`.          |
| `analysis/03_leadlag_placebo.R`       | 100-permutation brand-shuffle placebo for the lead-lag claim.                             |
| `pull/pull_trends.py`                 | Google Trends collection: entity resolution, anchor stitching, checkpointing.             |
| `pull/terms_overrides.yaml`           | Hand-curated search terms and rationale, per brand.                                       |
| `data/raw/trends/`                    | Curated-tier pull: raw batch responses, per-category stitched series, resolution log.     |
| `data/raw/trends.naive/`              | Uncurated ablation (raw brand names) used in §7.1.                                        |




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
`[analysis/session-info.txt](analysis/session-info.txt)`. The scripts are
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
