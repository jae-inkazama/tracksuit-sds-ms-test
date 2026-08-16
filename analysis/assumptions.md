# Assumptions, theory and known weaknesses

Everything this study leans on that isn't in the data. Written so a reader can
attack the work efficiently.

## The marketing theory I'm borrowing

**Binet & Field — excess share of voice (ESOV).** In *The Long and the Short of
It* (IPA, 2013), Les Binet and Peter Field analysed the IPA's databank of
advertising case studies and found a consistent pattern: a brand's share of
market tends to move towards its share of advertising voice. If you spend a
bigger share of the category's advertising than your share of the market, you
tend to grow; if you under-spend relative to your size, you tend to shrink. The
gap between the two — excess share of voice — predicts the direction. Their
rule of thumb is roughly 0.5 points of annual market share growth per 10 points
of ESOV, though the multiplier varies a lot by category.

Two related planks of the same body of work matter here:

- **Brand building works slowly; activation works fast.** Long-term brand
  effects accumulate over years; sales activation spikes and decays within
  weeks. This is why a lagged relationship between search and consideration is
  plausible rather than suspicious.
- **Mental availability** (Byron Sharp / Ehrenberg-Bass): brands grow by being
  easy to think of at the moment of need. A search is a direct observation of a
  brand being thought of, which is why share of search is treated here as a
  behavioural proxy for salience rather than as a purchase signal.

**Why I applied ESOV logic to search.** Share of voice needs media spend data,
which is expensive and partial. Share of search is free, current, and measures
what people did rather than what brands paid for. The analogy is not perfect —
share of voice is an *input* a brand controls, share of search is an *output*
of prior brand activity — so the causal story is different even though the
arithmetic is the same. I treat the gap as a symptom, not a lever.

**Tracksuit and Google's Return on Awareness (2025).** Their study (31 brands,
15 AU/NZ categories) links awareness to share of search — around +5 points of
awareness for +5 points of share of search near the 30% awareness mark — and
positions share of search as running ahead of market share by 6–12 months. My
work sits one step earlier in the funnel and is consistent with it: search
moves ahead of *consideration*, which moves ahead of share.

**Adstock / carryover** (standard in marketing mix modelling): the effect of
marketing activity decays geometrically rather than switching off. I use the
simplest form to ask *when* search shows up in consideration, not how big the
effect is.

## Assumptions in the analysis

| # | Assumption | Why it might be wrong |
|---|---|---|
| 1 | Google Trends volume is a reasonable proxy for total category search interest | Ignores Bing, in-app search (Amazon, TikTok), and increasingly AI assistants. If younger consumers shift to AI answers, brand search under-counts them. |
| 2 | A brand's search index measures interest in *that brand in that category* | Multi-category brands break this: Suncorp's banking searches, Ikea appearing in both furniture and mattresses. |
| 3 | Share of search is comparable to share of consideration | The search denominator only includes brands Tracksuit tracks. A competitor outside the panel is invisible to both, but they may be missing in different proportions. |
| 4 | Survey weights approximate respondent counts for margin-of-error purposes | Weighting introduces design effects, so the true margin of error is wider than I calculate. My noise estimates flatter the survey. |
| 5 | Monthly survey readings are independent draws | Panel overlap between waves would make consecutive readings correlated and my noise decomposition optimistic. |
| 6 | Quarterly averaging is enough to make the survey usable for change analysis | Three waves of ~200 is still only ~600 respondents; residual noise remains. |
| 7 | Two quarters is the right horizon for the excess-share-of-search test | Chosen because it is long enough to see movement and short enough to keep sample size. Not optimised — a different horizon might show more or less. |
| 8 | Category is the right competitive frame | Tracksuit's category definitions are survey constructs; consumers' consideration sets may not match them (Krispy Kreme sitting in "Cafes"). |
| 9 | Brand name → search term mapping is correct | Verified by hand for 8 categories only. Section 4's weakest categories are contaminated by this (see below). |
| 10 | The relationship is stable over the study window | Covers COVID recovery, a cost-of-living squeeze, and the arrival of AI search. Any of these could shift search behaviour independent of brands. |

## Known weaknesses

- **Curation is partial.** Search terms were hand-checked for 8 categories.
  Elsewhere they were resolved automatically, and the failures are visible:
  "Fruits" holds 65% of Haircare's search share, "Shine" and "Remedy" hold 92%
  of Healthy Beverages. Categories at the bottom of the ranking chart are
  partly measuring my data quality, not consumer behaviour.
- **Some survey options are not brands.** "Doctors (e.g. GP)" can never have a
  search share, but it holds 37% of consideration in its category. Any category
  containing a generic option is unfairly penalised.
- **No holdout test.** The excess-share-of-search relationship is fitted and
  evaluated on the same data. It should be validated on later waves before
  anyone acts on it.
- **Correlation, not causation.** A campaign lifts search and consideration
  together with different lags. The placebo test rules out category-wide
  seasonality as the explanation, not brand-level advertising.
- **Australia only, one search engine, one time window.**

## Things I chose not to do, and why

- **A full marketing mix model.** The right tool for sizing the effect, but it
  needs media spend, priors and holdout validation. Out of scope for a weekend,
  and the data has 14 quarters per brand — not enough to identify a rich model.
- **Modelling every funnel stage jointly.** A structural model of awareness →
  consideration → preference would be the elegant version. I tested the stages
  separately instead, which is cruder but easier to check.
- **Optimising thresholds.** The qualification cut-offs in the recommendation
  are illustrative round numbers, not calibrated against a business outcome.
