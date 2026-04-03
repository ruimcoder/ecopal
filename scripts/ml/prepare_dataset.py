"""
Prepares the unified training dataset from all collected image sources.

Reads manifest.csv files produced by collect_inaturalist.py and
collect_fishial.py, then splits the data into train/val/test sets
(stratified by species) and organises images into the standard folder
structure expected by TensorFlow/Keras ImageDataGenerator.

Usage:
    python prepare_dataset.py \\
        --raw-dir data/raw \\
        --output-dir data/prepared \\
        --split 0.8,0.1,0.1 \\
        --min-images 50

Outputs:
    data/prepared/train/<scientific_name>/   — training images
    data/prepared/val/<scientific_name>/     — validation images
    data/prepared/test/<scientific_name>/    — test images
    data/prepared/dataset_manifest.csv      — full manifest with split column
    data/prepared/class_labels.json         — {class_index: scientific_name}
    data/prepared/stats.json               — per-species/split counts
"""

import argparse
import csv
import json
import logging
import shutil
import signal
import sys
from pathlib import Path

import pandas as pd
from sklearn.model_selection import train_test_split

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------

_shutdown = False


def _handle_sigint(sig, frame):  # noqa: D401
    global _shutdown
    log.warning("Interrupt received — saving progress before exit …")
    _shutdown = True


signal.signal(signal.SIGINT, _handle_sigint)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def parse_split(split_str: str) -> tuple[float, float, float]:
    """Parse '0.8,0.1,0.1' into (train, val, test) fractions that sum to 1.0."""
    parts = [float(x) for x in split_str.split(",")]
    if len(parts) != 3:
        raise ValueError("--split must have exactly three values: train,val,test")
    total = sum(parts)
    if abs(total - 1.0) > 1e-6:
        raise ValueError(f"Split fractions must sum to 1.0, got {total:.4f}")
    return parts[0], parts[1], parts[2]


def collect_manifests(raw_dir: Path) -> pd.DataFrame:
    """Find and concatenate all manifest.csv files under raw_dir."""
    manifest_paths = list(raw_dir.rglob("manifest.csv"))
    if not manifest_paths:
        log.error("No manifest.csv found under %s", raw_dir)
        sys.exit(1)

    frames = []
    for mp in manifest_paths:
        log.info("Reading manifest: %s", mp)
        try:
            df = pd.read_csv(mp, dtype=str)
            frames.append(df)
        except Exception as exc:
            log.warning("Could not read %s: %s", mp, exc)

    combined = pd.concat(frames, ignore_index=True)
    log.info("Total rows across all manifests: %d", len(combined))
    return combined


def filter_species(df: pd.DataFrame, min_images: int) -> pd.DataFrame:
    """Drop species with fewer than min_images, logging what was removed."""
    counts = df.groupby("scientific_name").size()
    insufficient = counts[counts < min_images].index.tolist()
    if insufficient:
        log.warning(
            "Dropping %d species with fewer than %d images: %s",
            len(insufficient),
            min_images,
            ", ".join(insufficient),
        )
    return df[~df["scientific_name"].isin(insufficient)].copy()


def stratified_split(
    df: pd.DataFrame, train_frac: float, val_frac: float
) -> pd.DataFrame:
    """
    Add a 'split' column ('train', 'val', 'test') to the DataFrame.

    Uses stratified sampling so every species has proportional representation
    in each split.  The val/test ratio is computed relative to the non-train
    portion.
    """
    df = df.copy()
    df["split"] = "train"

    # First pass: carve off the non-train portion
    non_train_frac = 1.0 - train_frac

    train_idx, rest_idx = train_test_split(
        df.index,
        test_size=non_train_frac,
        stratify=df["scientific_name"],
        random_state=42,
    )
    df.loc[train_idx, "split"] = "train"

    rest_df = df.loc[rest_idx]

    # Second pass: split the remainder 50/50 into val and test
    # (assumes val_frac ≈ test_frac; exact ratio respected via test_size)
    val_ratio = val_frac / non_train_frac
    val_idx, test_idx = train_test_split(
        rest_df.index,
        test_size=1.0 - val_ratio,
        stratify=rest_df["scientific_name"],
        random_state=42,
    )
    df.loc[val_idx, "split"] = "val"
    df.loc[test_idx, "split"] = "test"

    return df


def copy_images(df: pd.DataFrame, output_dir: Path) -> None:
    """Copy each image into output_dir/<split>/<scientific_name>/."""
    for _, row in df.iterrows():
        if _shutdown:
            log.warning("Shutdown requested — stopping copy early")
            break

        src = Path(row["file_path"])
        if not src.exists():
            log.warning("Source not found, skipping: %s", src)
            continue

        # Use snake_case folder names for compatibility with Keras flow_from_directory
        species_folder = row["scientific_name"].lower().replace(" ", "_")
        dest_dir = output_dir / row["split"] / species_folder
        dest_dir.mkdir(parents=True, exist_ok=True)

        dest = dest_dir / src.name
        if dest.exists():
            continue  # idempotent

        try:
            shutil.copy2(src, dest)
        except Exception as exc:
            log.warning("Copy failed %s → %s: %s", src, dest, exc)


def build_class_labels(df: pd.DataFrame) -> dict[int, str]:
    """
    Return {class_index: scientific_name} sorted alphabetically.

    Sorting ensures a deterministic class order regardless of collection order.
    This dict becomes assets/models/labels.json in the Flutter app.
    """
    species_sorted = sorted(df["scientific_name"].unique())
    return {i: name for i, name in enumerate(species_sorted)}


def compute_stats(df: pd.DataFrame) -> dict:
    """Return a nested dict: species → split → count, plus totals."""
    stats: dict = {"per_species": {}, "totals": {}}

    for split in ("train", "val", "test"):
        split_df = df[df["split"] == split]
        stats["totals"][split] = int(len(split_df))

    stats["totals"]["all"] = int(len(df))
    stats["totals"]["species_count"] = int(df["scientific_name"].nunique())

    for species in sorted(df["scientific_name"].unique()):
        sp_df = df[df["scientific_name"] == species]
        stats["per_species"][species] = {
            split: int(len(sp_df[sp_df["split"] == split]))
            for split in ("train", "val", "test")
        }

    return stats


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Assemble and split the unified fish-species training dataset."
    )
    parser.add_argument(
        "--raw-dir",
        type=Path,
        default=Path("data/raw"),
        help="Root directory containing source images and manifest CSVs (default: data/raw)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/prepared"),
        help="Output directory for prepared dataset (default: data/prepared)",
    )
    parser.add_argument(
        "--split",
        default="0.8,0.1,0.1",
        help="Train/val/test split fractions as comma-separated values (default: 0.8,0.1,0.1)",
    )
    parser.add_argument(
        "--min-images",
        type=int,
        default=50,
        help="Minimum images per species to include in dataset (default: 50)",
    )
    args = parser.parse_args()

    train_frac, val_frac, _test_frac = parse_split(args.split)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Load and merge all manifests
    # ------------------------------------------------------------------
    df = collect_manifests(args.raw_dir)

    # ------------------------------------------------------------------
    # 2. Filter species with insufficient data
    # ------------------------------------------------------------------
    df = filter_species(df, args.min_images)
    log.info(
        "After filtering: %d images across %d species",
        len(df),
        df["scientific_name"].nunique(),
    )

    if df.empty:
        log.error("No data remaining after filtering. Exiting.")
        sys.exit(1)

    # ------------------------------------------------------------------
    # 3. Stratified train/val/test split
    # ------------------------------------------------------------------
    df = stratified_split(df, train_frac, val_frac)
    split_counts = df["split"].value_counts().to_dict()
    log.info("Split counts: %s", split_counts)

    # ------------------------------------------------------------------
    # 4. Copy images into prepared directory structure
    # ------------------------------------------------------------------
    log.info("Copying images to %s …", args.output_dir)
    copy_images(df, args.output_dir)

    if _shutdown:
        log.warning("Interrupted — partial dataset written to %s", args.output_dir)
        sys.exit(1)

    # ------------------------------------------------------------------
    # 5. Write dataset_manifest.csv
    # ------------------------------------------------------------------
    manifest_out = args.output_dir / "dataset_manifest.csv"
    df.to_csv(manifest_out, index=False)
    log.info("Written: %s", manifest_out)

    # ------------------------------------------------------------------
    # 6. Write class_labels.json  (→ assets/models/labels.json in app)
    # ------------------------------------------------------------------
    class_labels = build_class_labels(df)
    labels_out = args.output_dir / "class_labels.json"
    with open(labels_out, "w", encoding="utf-8") as f:
        json.dump(class_labels, f, indent=2, ensure_ascii=False)
    log.info("Written: %s  (%d classes)", labels_out, len(class_labels))

    # ------------------------------------------------------------------
    # 7. Write stats.json
    # ------------------------------------------------------------------
    stats = compute_stats(df)
    stats_out = args.output_dir / "stats.json"
    with open(stats_out, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2, ensure_ascii=False)
    log.info("Written: %s", stats_out)

    # Human-readable summary
    log.info(
        "Dataset ready: %d total images | %d species | "
        "train=%d val=%d test=%d",
        stats["totals"]["all"],
        stats["totals"]["species_count"],
        stats["totals"]["train"],
        stats["totals"]["val"],
        stats["totals"]["test"],
    )
    log.info(
        "Next step: copy %s to assets/models/labels.json in the Flutter app",
        labels_out,
    )


if __name__ == "__main__":
    main()
