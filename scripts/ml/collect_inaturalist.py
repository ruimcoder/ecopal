"""
Downloads fish observation images from iNaturalist API for ML training.

Usage:
    python collect_inaturalist.py \\
        --output-dir data/raw \\
        --species-file species_list.json \\
        --max-per-species 200

The iNaturalist API returns research-grade observations with photos.
Only images licensed CC0, CC-BY, or CC-BY-NC are downloaded (suitable for
ML training under open-data terms).

Output structure:
    data/raw/<scientific_name_snake_case>/<observation_id>.jpg
    data/raw/manifest.csv  (appended on each run)
"""

import argparse
import csv
import json
import logging
import signal
import sys
import time
from pathlib import Path

import requests
from PIL import Image as _PILImage
from tqdm import tqdm

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

INAT_API_BASE = "https://api.inaturalist.org/v1"
# EcoPal is a non-commercial open-source conservation project.
# CC-BY-NC images are permitted for model training under these terms.
# If commercial deployment is ever pursued, remove "cc-by-nc" from this list.
ALLOWED_LICENSES = {"cc0", "cc-by", "cc-by-nc"}
REQUEST_DELAY_S = 1.0  # polite delay between API calls
MANIFEST_HEADERS = [
    "file_path",
    "scientific_name",
    "species_id",
    "source",
    "observation_id",
    "quality_grade",
    "license",
]

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
# Graceful shutdown — save progress before exit on Ctrl-C
# ---------------------------------------------------------------------------

_shutdown = False


def _handle_sigint(sig, frame):  # noqa: D401
    global _shutdown
    log.warning("Interrupt received — finishing current species then exiting …")
    _shutdown = True


signal.signal(signal.SIGINT, _handle_sigint)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def scientific_to_snake(scientific_name: str) -> str:
    """Convert 'Salmo salar' → 'salmo_salar'."""
    return scientific_name.lower().replace(" ", "_")


def load_existing_observation_ids(output_dir: Path, snake_name: str) -> set[str]:
    """Return the set of observation IDs already saved for this species."""
    species_dir = output_dir / snake_name
    if not species_dir.exists():
        return set()
    return {p.stem for p in species_dir.glob("*.jpg")}


def load_licenses(species_dir: Path) -> dict:
    """Load licenses.json for a species directory, returning {obs_id: license_code}."""
    licenses_path = species_dir / "licenses.json"
    if not licenses_path.exists():
        return {}
    with open(licenses_path, encoding="utf-8") as f:
        return json.load(f)


def save_licenses(species_dir: Path, licenses: dict) -> None:
    """Persist {obs_id: license_code} entries to licenses.json."""
    species_dir.mkdir(parents=True, exist_ok=True)
    licenses_path = species_dir / "licenses.json"
    with open(licenses_path, "w", encoding="utf-8") as f:
        json.dump(licenses, f, indent=2)


def revalidate_licenses(species_dir: Path, licenses: dict) -> dict:
    """Delete images whose license is no longer in ALLOWED_LICENSES and remove from dict."""
    to_remove = [obs_id for obs_id, lic in licenses.items() if lic not in ALLOWED_LICENSES]
    for obs_id in to_remove:
        img_path = species_dir / f"{obs_id}.jpg"
        if img_path.exists():
            img_path.unlink()
            log.warning(
                "Deleted non-compliant image %s (license: %s)",
                img_path,
                licenses[obs_id],
            )
        del licenses[obs_id]
    return licenses


def fetch_observations(taxon_id: int, page: int, per_page: int) -> dict:
    """Call the iNaturalist observations endpoint and return parsed JSON."""
    url = f"{INAT_API_BASE}/observations"
    params = {
        "taxon_id": taxon_id,
        "quality_grade": "research",
        "photos": "true",
        "per_page": per_page,
        "page": page,
        "order": "desc",
        "order_by": "created_at",
    }
    resp = requests.get(url, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def download_image(url: str, dest_path: Path) -> bool:
    """Download a single image to dest_path. Returns True on success."""
    try:
        resp = requests.get(url, timeout=30, stream=True)
        resp.raise_for_status()
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(dest_path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=8192):
                f.write(chunk)
        try:
            with _PILImage.open(dest_path) as img:
                img.verify()
        except Exception as exc:
            dest_path.unlink(missing_ok=True)
            log.warning("Corrupt image deleted %s: %s", dest_path, exc)
            return False
        return True
    except Exception as exc:
        log.warning("Failed to download %s: %s", url, exc)
        return False


def get_photo_url(photo: dict) -> str:
    """Return the medium-resolution URL for an iNaturalist photo object."""
    # Replace 'square' with 'medium' for higher resolution
    return photo.get("url", "").replace("/square.", "/medium.")


def open_manifest(output_dir: Path) -> tuple[csv.DictWriter, object]:
    """Open (or append to) the manifest CSV, returning (writer, file_handle)."""
    manifest_path = output_dir / "manifest.csv"
    write_header = not manifest_path.exists()
    fh = open(manifest_path, "a", newline="", encoding="utf-8")
    writer = csv.DictWriter(fh, fieldnames=MANIFEST_HEADERS)
    if write_header:
        writer.writeheader()
    return writer, fh


# ---------------------------------------------------------------------------
# Core collection logic
# ---------------------------------------------------------------------------

def collect_species(
    species: dict,
    output_dir: Path,
    max_per_species: int,
    manifest_writer: csv.DictWriter,
) -> int:
    """Download up to max_per_species images for one species. Returns count saved."""
    taxon_id = species.get("inat_taxon_id")
    if not taxon_id:
        log.info("No iNaturalist taxon ID for %s — skipping", species["scientific_name"])
        return 0

    snake_name = scientific_to_snake(species["scientific_name"])
    species_dir = output_dir / snake_name
    licenses = load_licenses(species_dir)
    original_license_count = len(licenses)
    licenses = revalidate_licenses(species_dir, licenses)
    if len(licenses) != original_license_count:
        save_licenses(species_dir, licenses)

    # Only count obs_ids that have a file on disk AND a valid license entry
    existing_ids = {
        obs_id for obs_id in licenses
        if (species_dir / f"{obs_id}.jpg").exists()
    }
    saved = 0
    page = 1
    per_page = min(200, max_per_species)  # iNat max per_page is 200

    pbar = tqdm(
        total=max_per_species,
        desc=species["common_name_en"],
        unit="img",
        leave=False,
    )
    pbar.update(len(existing_ids))  # reflect already-downloaded images

    try:
        while saved + len(existing_ids) < max_per_species and not _shutdown:
            try:
                data = fetch_observations(taxon_id, page, per_page)
            except Exception as exc:
                log.error("API error for %s page %d: %s", species["scientific_name"], page, exc)
                break

            results = data.get("results", [])
            if not results:
                break  # no more pages

            for obs in results:
                if saved + len(existing_ids) >= max_per_species:
                    break

                obs_id = str(obs.get("id", ""))
                if obs_id in existing_ids:
                    continue  # already downloaded — idempotent

                photos = obs.get("photos", [])
                if not photos:
                    continue

                photo = photos[0]
                license_code = (photo.get("license_code") or "").lower()
                if license_code not in ALLOWED_LICENSES:
                    continue  # skip non-permissive licenses

                image_url = get_photo_url(photo)
                if not image_url:
                    continue

                dest_path = output_dir / snake_name / f"{obs_id}.jpg"
                if download_image(image_url, dest_path):
                    licenses[obs_id] = license_code
                    save_licenses(species_dir, licenses)
                    manifest_writer.writerow(
                        {
                            "file_path": str(dest_path),
                            "scientific_name": species["scientific_name"],
                            "species_id": species["id"],
                            "source": "inaturalist",
                            "observation_id": obs_id,
                            "quality_grade": obs.get("quality_grade", ""),
                            "license": license_code,
                        }
                    )
                    existing_ids.add(obs_id)
                    saved += 1
                    pbar.update(1)

            page += 1
            time.sleep(REQUEST_DELAY_S)

    finally:
        pbar.close()

    return saved


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download iNaturalist fish observation images for ML training."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/raw"),
        help="Root directory for downloaded images (default: data/raw)",
    )
    parser.add_argument(
        "--species-file",
        type=Path,
        default=Path("species_list.json"),
        help="Path to species_list.json (default: species_list.json)",
    )
    parser.add_argument(
        "--max-per-species",
        type=int,
        default=200,
        help="Maximum images to download per species (default: 200)",
    )
    args = parser.parse_args()

    if not args.species_file.exists():
        log.error("Species file not found: %s", args.species_file)
        sys.exit(1)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    with open(args.species_file, encoding="utf-8") as f:
        species_data = json.load(f)

    species_list = species_data["species"]
    log.info("Loaded %d species from %s", len(species_list), args.species_file)

    manifest_writer, manifest_fh = open_manifest(args.output_dir)
    total_saved = 0

    try:
        for species in tqdm(species_list, desc="Species", unit="sp"):
            if _shutdown:
                break
            count = collect_species(
                species, args.output_dir, args.max_per_species, manifest_writer
            )
            total_saved += count
            log.info(
                "%-40s → %d images collected",
                species["scientific_name"],
                count,
            )
            time.sleep(REQUEST_DELAY_S)
    finally:
        manifest_fh.flush()
        manifest_fh.close()

    log.info("Done. Total images saved: %d", total_saved)


if __name__ == "__main__":
    main()
