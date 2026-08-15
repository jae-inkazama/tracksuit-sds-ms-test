# Search data pull

Pulls monthly Google Trends interest (Australia, Sep 2021 – Mar 2025) for every
brand in `sample-category-data.csv`, anchor-stitched to a common scale within
each category. Must be run from a residential IP (Google blocks datacenter IPs).

## Run

```bash
cd pull
pip install -r requirements.txt
python pull_trends.py --all              # curated tier: all 50 categories
python pull_trends.py --all --naive      # naive tier: same, ignoring hand-curated terms
```

Expect ~45–90 minutes per tier with default throttling (`--sleep 8`). The run
checkpoints every request — if it dies or you Ctrl-C, just re-run the same
command and it resumes where it left off. If you see repeated 429 errors,
increase `--sleep` (e.g. `--sleep 15`) and re-run.

To test on a couple of categories first:

```bash
python pull_trends.py --categories "Chocolate,Car Insurance"
```

## Outputs

- `data/raw/trends/<category>/batch_XX.csv` + `.meta.json` — raw responses (committed for reproducibility)
- `data/raw/trends/<category>/stitched.csv` — common-scale long format per category
- `data/raw/trends/all_stitched.csv` — combined file used by the analysis
- `data/raw/trends/resolution_log.csv` — how every brand name was resolved (topic entity vs raw term); review this
- `data/raw/trends.naive/…` — same structure for the naive tier

## Design notes

- **Topic entities over raw terms.** Where Google's knowledge graph has an
  entity for a brand (e.g. *Koala (company)*), we use it — this is the main
  defense against homonyms (Koala the animal, Mecca the city, Subway the train).
  `pull/terms_overrides.yaml` pins terms for the pilot categories; everything
  else is auto-resolved and logged.
- **Anchor stitching.** Trends compares at most 5 terms per request on a
  relative 0–100 scale. Each category's highest-awareness brand rides along in
  every batch; batches are rescaled by the anchor's mean so all brands in a
  category share one scale. Share of Search is then brand / sum-of-brands.
- **The naive tier** re-pulls everything using raw brand names with no
  curation — this is what a no-thought implementation would do, and comparing
  the two tiers quantifies how much term curation matters.
