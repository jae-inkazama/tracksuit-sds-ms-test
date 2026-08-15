#!/usr/bin/env python3
"""
Google Trends pull for Tracksuit Share-of-Search study.

For every category in sample-category-data.csv, pulls monthly Google Trends
interest (AU) for all brands in the category, using anchor-stitching so that
all brands within a category share a common scale.

Key features
------------
- Auto topic-entity resolution: each brand name is resolved to a Google Trends
  "topic" (knowledge-graph entity) where a plausible one exists; otherwise the
  raw search term is used. Every decision is written to a resolution log.
- Hand-curated overrides: pull/terms_overrides.yaml pins terms/topics for the
  pilot categories (homonym control).
- Anchor stitching: Trends only compares 5 terms per request on a relative
  0-100 scale. We include the category's anchor brand in every batch and
  rescale batches by the anchor's mean, giving a within-category common scale.
- Checkpoint/resume: every batch response is saved as it lands
  (data/raw/trends/<category>/batch_XX.csv). Re-running skips completed work.
- Polite throttling + exponential backoff on 429/403.

Usage
-----
    pip install -r requirements.txt
    python pull_trends.py --all                 # all 50 categories (~45-90 min)
    python pull_trends.py --categories "Fast Food,Car Insurance"
    python pull_trends.py --all --naive         # ignore overrides (naive-terms tier)

Outputs (per run tier)
----------------------
    data/raw/trends[.naive]/<category_slug>/batch_XX.csv   raw responses
    data/raw/trends[.naive]/<category_slug>/stitched.csv   common-scale long format
    data/raw/trends[.naive]/resolution_log.csv             how each brand was resolved
"""

import argparse
import json
import random
import re
import sys
import time
import unicodedata
from pathlib import Path

import pandas as pd
import yaml
from trendspy import Trends

ROOT = Path(__file__).resolve().parent.parent
SURVEY_CSV = ROOT / "sample-category-data.csv"
OVERRIDES_YAML = Path(__file__).resolve().parent / "terms_overrides.yaml"

TIMEFRAME = "2021-09-01 2025-03-31"  # spans all survey waves; >36m => monthly granularity
GEO = "AU"
BATCH_SIZE = 5  # Trends hard limit per request (anchor + 4 brands)

# Topic types we accept in auto-resolution, in rough order of preference.
ACCEPTED_TYPE_HINTS = [
    "company", "brand", "restaurant", "retail", "insurance", "store",
    "website", "chain", "manufacturer", "supermarket", "business", "topic",
]


def slugify(name: str) -> str:
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
    return s or "unnamed"


def build_slug_map(categories) -> dict:
    """Stable category->folder mapping that disambiguates slug collisions
    ('Chocolate & Confectionery' vs 'Chocolate confectionery' both slug to
    chocolate-confectionery; the second alphabetically gets a -2 suffix)."""
    m, seen = {}, {}
    for c in sorted(categories):
        s = slugify(c)
        if s in seen:
            seen[s] += 1
            m[c] = f"{s}-{seen[s]}"
        else:
            seen[s] = 1
            m[c] = s
    return m


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]", "", s.lower())


class Throttle:
    """Polite pacing with exponential backoff on rate limits."""

    def __init__(self, base_sleep: float):
        self.base_sleep = base_sleep
        self.penalty = 0.0

    def wait(self):
        time.sleep(self.base_sleep + self.penalty + random.uniform(0, 2))

    def ok(self):
        self.penalty = max(0.0, self.penalty * 0.5 - 1)

    def backoff(self):
        self.penalty = min(300.0, (self.penalty or 15.0) * 2)


def call_with_retry(fn, throttle: Throttle, what: str, max_tries: int = 5):
    for attempt in range(1, max_tries + 1):
        throttle.wait()
        try:
            out = fn()
            throttle.ok()
            return out
        except Exception as e:  # noqa: BLE001 - trendspy raises plain HTTPError etc.
            msg = str(e)
            transient = any(code in msg for code in ("429", "403", "500", "502", "timed out", "Connection"))
            print(f"    [retry {attempt}/{max_tries}] {what}: {msg[:120]}")
            if not transient or attempt == max_tries:
                raise
            throttle.backoff()
            time.sleep(30 * attempt)
    raise RuntimeError("unreachable")


STRONG_TYPE_HINTS = [
    "company", "brand", "insurance", "retail", "restaurant", "manufacturer",
    "supermarket", "chain", "corporation", "store", "website",
]


def score_candidate(want_title: str, title: str, ttype: str) -> float:
    """Rank a Trends autocomplete candidate. Higher is better; <=0 means reject.

    Guards against the failure modes seen in real logs: product SKUs and
    podcast episodes (very long titles), foreign subsidiaries ('Nestle
    Nigeria' vs exact 'Nestlé'), and unrelated entities sharing a word.
    """
    tl_full = ttype.lower()
    # Place-qualified entities ("Furniture store in Australia", "Deli in
    # Albuquerque") are Maps-style local businesses with no search volume.
    if re.search(r"\b(in|near)\b", tl_full):
        return -1
    # Never-a-brand entity classes (the Koala-the-animal / Sakata-the-city bug).
    if any(w in tl_full for w in ("animal", "city", "river", "magazine", "film",
                                  "movie", "song", "book", "album", "fictional")):
        return -1
    nb, nt = norm(want_title), norm(title)
    if not nb or not nt:
        return -1
    if nt == nb:
        title_score = 30.0
    elif nt.startswith(nb) or nb.startswith(nt):
        title_score = 18.0
    elif nb in nt:
        title_score = 8.0
    else:
        return -1  # title unrelated to the brand
    # SKU/episode garbage guard: hugely longer titles are almost never the brand
    excess = len(nt) - len(nb)
    title_score -= min(20.0, max(0, excess - 4) * 0.8)
    tl = ttype.lower()
    if any(h in tl for h in STRONG_TYPE_HINTS):
        type_score = 6.0
    elif tl.strip() == "topic":
        type_score = 2.0  # generic Topic entities are often right, but weak evidence
    else:
        type_score = 0.5
    return title_score + type_score


def resolve_brand(tr: Trends, throttle: Throttle, category: str, brand: str, override: dict | None):
    """Return (query_token, kind, detail) where kind is 'topic'|'term'."""
    override = override or {}
    if override.get("term"):
        return override["term"], "term", "override:term"
    hint = override.get("topic_hint", brand)
    want_title = override.get("topic_title", hint)
    want_types = [t.lower() for t in override.get("topic_types", [])]
    try:
        sugg = call_with_retry(lambda: tr.suggestions(hint), throttle, f"suggestions({hint!r})")
    except Exception:
        return brand, "term", "suggestions-failed"
    if sugg is None or len(sugg) == 0:
        return override.get("fallback_term", brand), "term", "no-suggestions"

    best, best_score = None, 0.0
    for _, row in sugg.iterrows():
        title, ttype, mid = str(row.get("title", "")), str(row.get("type", "")), row.get("mid")
        if not mid:
            continue
        if want_types and not any(w in ttype.lower() for w in want_types):
            continue
        s = score_candidate(want_title, title, ttype)
        if s > best_score:
            best, best_score = (mid, title, ttype), s
    if best and best_score >= 8.0:
        mid, title, ttype = best
        return mid, "topic", f"{title} ({ttype}) score={best_score:.0f}"
    return override.get("fallback_term", brand), "term", "no-matching-topic"


def month_agg(df: pd.DataFrame) -> pd.DataFrame:
    """Defensive: collapse index to month starts (Trends should already be monthly)."""
    df = df.copy()
    df.index = pd.to_datetime(df.index).to_period("M").to_timestamp()
    return df.groupby(df.index).mean()


def load_meta(meta_path: Path):
    """Read batch metadata robustly: tolerate legacy cp1252 files and
    empty/corrupt JSON left by interrupted runs. None means 'not cached'."""
    try:
        raw = meta_path.read_bytes()
    except OSError:
        return None
    if not raw.strip():
        return None
    for enc in ("utf-8", "cp1252"):
        try:
            return json.loads(raw.decode(enc))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    return None


ZERO_MEAN = 0.5  # mean raw index below this counts as "no volume"


def pull_category(tr, throttle, category, brands, anchor, tokens, out_dir: Path):
    """Pull all batches for a category. Returns (long_df, fallbacks) where
    fallbacks lists brands whose topic entity returned ~zero volume and were
    automatically re-pulled as raw terms."""
    out_dir.mkdir(parents=True, exist_ok=True)

    state = {"anchor_ref_mean": None}

    def fetch_batch(i, names, kws, n_total):
        bpath = out_dir / f"batch_{i:02d}.csv"
        meta_path = out_dir / f"batch_{i:02d}.meta.json"
        cached = False
        if bpath.exists() and meta_path.exists():
            meta = load_meta(meta_path)
            if meta is None:
                print(f"    batch {i + 1}/{n_total}: corrupt metadata, re-pulling")
            elif meta.get("tokens") == kws and meta.get("brands") == names:
                cached = True
            else:
                print(f"    batch {i + 1}/{n_total}: tokens changed, re-pulling")
        if cached:
            print(f"    batch {i + 1}/{n_total}: cached")
            df = pd.read_csv(bpath, index_col=0, parse_dates=True)
        else:
            print(f"    batch {i + 1}/{n_total}: {names}")
            df = call_with_retry(
                lambda kws=kws: tr.interest_over_time(kws, timeframe=TIMEFRAME, geo=GEO),
                throttle, f"IOT {category} batch {i}")
            df = pd.DataFrame(df)
            df.columns = names  # trendspy aligns values to request order
            df = month_agg(df)
            meta = {"category": category, "batch": i, "brands": names,
                    "tokens": kws, "timeframe": TIMEFRAME, "geo": GEO}
            df.to_csv(bpath, encoding="utf-8")
            meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1),
                                 encoding="utf-8")
        return df

    def stitch(df, i, batch_index):
        a_mean = df[anchor].mean()
        if batch_index == 0:
            state["anchor_ref_mean"] = a_mean if a_mean > 0 else None
        if a_mean <= 0 or state["anchor_ref_mean"] is None:
            scale, flag = float("nan"), "anchor-zero"
            print(f"    WARNING: anchor {anchor!r} ~0 in batch {i}; stitching unreliable")
        else:
            scale, flag = state["anchor_ref_mean"] / a_mean, ""
        rows = []
        for b in df.columns:
            if batch_index > 0 and b == anchor:
                continue  # keep anchor from reference batch only
            s = df[b] * (scale if scale == scale else 1.0)
            rows.append(pd.DataFrame({
                "category_name": category, "brand_name": b, "month": df.index,
                "trends_index": s.values, "raw_index": df[b].values,
                "batch": i, "scale_factor": scale, "stitch_flag": flag,
            }))
        return rows

    others = [b for b in brands if b != anchor]
    batches = [others[i:i + BATCH_SIZE - 1] for i in range(0, len(others), BATCH_SIZE - 1)]
    stitched = []
    for i, batch_brands in enumerate(batches):
        names = [anchor] + batch_brands
        kws = [tokens[anchor]] + [tokens[b] for b in batch_brands]
        df = fetch_batch(i, names, kws, len(batches))
        stitched.extend(stitch(df, i, i))

    long_df = pd.concat(stitched, ignore_index=True)

    # Zero-volume fallback: a topic entity that returns an ~empty series is a
    # dud knowledge-graph duplicate (observed for TikTok, Myer, Big W, ...).
    # The pulled series is the only reliable validator, so re-pull those brands
    # as raw terms and take whichever the API gives volume for.
    means = long_df.groupby("brand_name")["raw_index"].mean()
    duds = [b for b in others
            if str(tokens[b]).startswith("/") and means.get(b, 0) < ZERO_MEAN]
    fallbacks = []
    if duds:
        print(f"    zero-volume topics -> raw-term fallback: {duds}")
        fb_batches = [duds[j:j + BATCH_SIZE - 1] for j in range(0, len(duds), BATCH_SIZE - 1)]
        for j, fb in enumerate(fb_batches):
            i = 90 + j  # fallback batches numbered from 90
            names = [anchor] + fb
            kws = [tokens[anchor]] + fb  # raw brand names as terms
            df = fetch_batch(i, names, kws, 90 + len(fb_batches))
            long_df = long_df[~long_df.brand_name.isin(fb)]
            long_df = pd.concat([long_df, *stitch(df, i, 1)], ignore_index=True)
            fallbacks.extend(fb)

    long_df.to_csv(out_dir / "stitched.csv", index=False, encoding="utf-8")
    return long_df, fallbacks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--categories", default="", help="comma-separated category names")
    ap.add_argument("--naive", action="store_true",
                    help="ignore hand-curated overrides (naive tier, for the curation-effect comparison)")
    ap.add_argument("--sleep", type=float, default=8.0, help="base seconds between requests")
    args = ap.parse_args()

    survey = pd.read_csv(SURVEY_CSV)
    all_cats = sorted(survey["CATEGORY_NAME"].unique())
    if args.all:
        cats = all_cats
    elif args.categories:
        want = [c.strip() for c in args.categories.split(",")]
        bad = [c for c in want if c not in all_cats]
        if bad:
            sys.exit(f"Unknown categories: {bad}\nAvailable: {all_cats}")
        cats = want
    else:
        sys.exit("Pass --all or --categories \"A,B,C\"")

    overrides = {}
    if OVERRIDES_YAML.exists() and not args.naive:
        overrides = yaml.safe_load(OVERRIDES_YAML.read_text(encoding="utf-8")) or {}
        overrides = overrides.get("categories", {})

    tier = "trends.naive" if args.naive else "trends"
    base_out = ROOT / "data" / "raw" / tier
    base_out.mkdir(parents=True, exist_ok=True)
    res_log_path = base_out / "resolution_log.csv"
    res_rows = []
    if res_log_path.exists():
        res_rows = pd.read_csv(res_log_path).to_dict("records")
    resolved_cache = {(r["category_name"], r["brand_name"]): r for r in res_rows}

    tr = Trends()
    throttle = Throttle(args.sleep)

    # awareness-based anchor choice: most-recognised brand is the most stable scale reference
    slug_map = build_slug_map(all_cats)

    aware = (survey[survey["STD_QUESTION"] == "PROMPTED_AWARENESS"]
             .groupby(["CATEGORY_NAME", "BRAND_NAME"])["PERCENTAGE_1"].mean())

    for ci, cat in enumerate(cats, 1):
        slug = slug_map[cat]
        out_dir = base_out / slug
        print(f"[{ci}/{len(cats)}] {cat}")
        cat_over = overrides.get(cat, {})
        brand_over = cat_over.get("brands", {})
        brands = sorted(survey.loc[survey["CATEGORY_NAME"] == cat, "BRAND_NAME"].unique())

        tokens = {}
        for b in brands:
            key = (cat, b)
            if args.naive:
                # The uncurated ablation: raw brand names, no topic resolution,
                # no overrides — what a zero-effort implementation would pull.
                token, kind, detail = b, "term", "naive:raw-term"
            elif key in resolved_cache and b not in brand_over:
                tokens[b] = resolved_cache[key]["query_token"]
                continue
            else:
                token, kind, detail = resolve_brand(tr, throttle, cat, b, brand_over.get(b))
            tokens[b] = token
            row = {"category_name": cat, "brand_name": b, "query_token": token,
                   "kind": kind, "detail": detail, "tier": tier}
            if key in resolved_cache:
                if resolved_cache[key]["query_token"] != token:
                    print(f"    resolve {b!r} CHANGED -> {kind}: {token} ({detail})")
                resolved_cache[key].update(row)
            else:
                res_rows.append(row)
                resolved_cache[key] = row
                print(f"    resolve {b!r} -> {kind}: {token} ({detail})")
            pd.DataFrame(res_rows).to_csv(res_log_path, index=False, encoding="utf-8")

        anchor = cat_over.get("anchor")
        if anchor not in brands:
            anchor = aware.loc[cat].idxmax() if cat in aware.index.get_level_values(0) else brands[0]
        print(f"    anchor: {anchor}")

        _, fallbacks = pull_category(tr, throttle, cat, brands, anchor, tokens, out_dir)
        for b in fallbacks:
            resolved_cache[(cat, b)].update(
                {"query_token": b, "kind": "term", "detail": "zero-volume-fallback"})
        if fallbacks:
            pd.DataFrame(res_rows).to_csv(res_log_path, index=False, encoding="utf-8")
        print(f"    saved {out_dir / 'stitched.csv'}")

    # combined convenience file
    known = {base_out / s / "stitched.csv" for s in slug_map.values()}
    parts = [pd.read_csv(p) for p in sorted(known) if p.exists()]
    if parts:
        pd.concat(parts, ignore_index=True).to_csv(base_out / "all_stitched.csv",
                                                   index=False, encoding="utf-8")
        print(f"Combined -> {base_out / 'all_stitched.csv'}")


if __name__ == "__main__":
    main()
