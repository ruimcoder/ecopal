"""
Fishial.ai dataset collection scaffold.

Fishial.ai has a curated dataset of ~175k fish images that are particularly
realistic for supermarket/dead-fish context — making them the highest-value
source for this model.

Manual steps required before running this script:
    1. Register at https://fishial.ai and request dataset access.
    2. Download the dataset archive to data/raw/fishial/
    3. Extract so that images are arranged as:
           data/raw/fishial/<CommonSpeciesName>/<image_file>
       (This is the typical structure Fishial.ai exports use.)
    4. Run this script to normalize into the standard manifest format:

Usage:
    python collect_fishial.py \\
        --fishial-dir data/raw/fishial \\
        --output-dir data/raw \\
        --species-file species_list.json

This script:
- Walks the Fishial directory structure
- Maps Fishial's common-name folder names to scientific names via species_list.json
- Copies/links images into the standard output structure:
      data/raw/<scientific_name_snake_case>/<fishial_image_name>
- Appends entries to data/raw/manifest.csv
- Logs any Fishial species folders that have no mapping (for manual review)
"""

import argparse
import csv
import json
import logging
import shutil
import signal
import sys
from pathlib import Path

from tqdm import tqdm

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
    log.warning("Interrupt received — finishing current file then exiting …")
    _shutdown = True


signal.signal(signal.SIGINT, _handle_sigint)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MANIFEST_HEADERS = [
    "file_path",
    "scientific_name",
    "species_id",
    "source",
    "observation_id",
    "quality_grade",
    "license",
]
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def scientific_to_snake(scientific_name: str) -> str:
    """Convert 'Salmo salar' → 'salmo_salar'."""
    return scientific_name.lower().replace(" ", "_")


def build_name_lookup(species_list: list[dict]) -> dict[str, dict]:
    """
    Build a case-insensitive lookup from common name → species entry.

    Fishial folders use common names (e.g. 'Atlantic Salmon') so we map
    those to our canonical species entries.
    """
    lookup: dict[str, dict] = {}
    for sp in species_list:
        key = sp["common_name_en"].lower().strip()
        lookup[key] = sp
    return lookup


def open_manifest(output_dir: Path) -> tuple[csv.DictWriter, object]:
    """Open (or append to) the manifest CSV, returning (writer, file_handle)."""
    manifest_path = output_dir / "manifest.csv"
    write_header = not manifest_path.exists()
    fh = open(manifest_path, "a", newline="", encoding="utf-8")
    writer = csv.DictWriter(fh, fieldnames=MANIFEST_HEADERS)
    if write_header:
        writer.writeheader()
    return writer, fh


def already_copied(dest_path: Path) -> bool:
    """Return True if the destination image already exists (idempotent runs)."""
    return dest_path.exists()


# ---------------------------------------------------------------------------
# Core normalization logic
# ---------------------------------------------------------------------------

def normalize_fishial(
    fishial_dir: Path,
    output_dir: Path,
    name_lookup: dict[str, dict],
    manifest_writer: csv.DictWriter,
) -> tuple[int, list[str]]:
    """
    Walk fishial_dir, copy images into standard structure, write manifest rows.

    Returns:
        (total_copied, list_of_unmapped_folder_names)
    """
    total_copied = 0
    unmapped_folders: list[str] = []

    # Each sub-directory in fishial_dir is expected to be a species folder
    species_folders = [d for d in sorted(fishial_dir.iterdir()) if d.is_dir()]

    for folder in tqdm(species_folders, desc="Fishial species", unit="sp"):
        if _shutdown:
            break

        folder_key = folder.name.lower().strip()
        species = name_lookup.get(folder_key)

        if species is None:
            log.warning("No mapping for Fishial folder: '%s'", folder.name)
            unmapped_folders.append(folder.name)
            continue

        snake_name = scientific_to_snake(species["scientific_name"])
        dest_species_dir = output_dir / snake_name
        dest_species_dir.mkdir(parents=True, exist_ok=True)

        image_files = [
            f for f in sorted(folder.iterdir())
            if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS
        ]

        for img_path in tqdm(image_files, desc=folder.name, unit="img", leave=False):
            if _shutdown:
                break

            # Preserve original filename; prefix with 'fishial_' to avoid
            # collisions with iNaturalist images
            dest_name = f"fishial_{img_path.name}"
            if img_path.suffix.lower() not in {".jpg", ".jpeg"}:
                # Normalise to .jpg extension for consistency
                dest_name = Path(dest_name).stem + ".jpg"
            dest_path = dest_species_dir / dest_name

            if already_copied(dest_path):
                continue  # idempotent

            try:
                shutil.copy2(img_path, dest_path)
            except Exception as exc:
                log.warning("Failed to copy %s: %s", img_path, exc)
                continue

            # Use stem of original filename as a pseudo observation ID
            obs_id = f"fishial_{img_path.stem}"
            manifest_writer.writerow(
                {
                    "file_path": str(dest_path),
                    "scientific_name": species["scientific_name"],
                    "species_id": species["id"],
                    "source": "fishial",
                    "observation_id": obs_id,
                    # Fishial images are curated/labelled — treat as 'research' equivalent
                    "quality_grade": "curated",
                    # Fishial.ai dataset is licensed for ML research; check current ToS
                    "license": "fishial-research",
                }
            )
            total_copied += 1

    return total_copied, unmapped_folders


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize the Fishial.ai dataset into the standard training format."
    )
    parser.add_argument(
        "--fishial-dir",
        type=Path,
        default=Path("data/raw/fishial"),
        help="Path to extracted Fishial.ai dataset directory (default: data/raw/fishial)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/raw"),
        help="Root output directory for normalized images (default: data/raw)",
    )
    parser.add_argument(
        "--species-file",
        type=Path,
        default=Path("species_list.json"),
        help="Path to species_list.json (default: species_list.json)",
    )
    args = parser.parse_args()

    if not args.fishial_dir.exists():
        log.error(
            "Fishial directory not found: %s\n"
            "Please download the Fishial.ai dataset first (see script docstring).",
            args.fishial_dir,
        )
        sys.exit(1)

    if not args.species_file.exists():
        log.error("Species file not found: %s", args.species_file)
        sys.exit(1)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    with open(args.species_file, encoding="utf-8") as f:
        species_data = json.load(f)

    name_lookup = build_name_lookup(species_data["species"])
    log.info(
        "Loaded %d species, normalizing Fishial dataset at %s",
        len(species_data["species"]),
        args.fishial_dir,
    )

    manifest_writer, manifest_fh = open_manifest(args.output_dir)
    total_copied = 0
    unmapped: list[str] = []

    try:
        total_copied, unmapped = normalize_fishial(
            args.fishial_dir, args.output_dir, name_lookup, manifest_writer
        )
    finally:
        manifest_fh.flush()
        manifest_fh.close()

    log.info("Done. %d images normalized from Fishial.ai dataset.", total_copied)

    if unmapped:
        log.warning(
            "%d Fishial folder(s) had no species mapping. Add them to species_list.json "
            "or create name aliases:\n  %s",
            len(unmapped),
            "\n  ".join(unmapped),
        )


if __name__ == "__main__":
    main()
