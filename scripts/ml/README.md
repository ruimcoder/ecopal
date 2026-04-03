# EcoPal ML — Fish Species Training Data Pipeline

This directory contains the scripts to assemble the training dataset for
EcoPal's on-device fish species identification model (Issue #13).

---

## Prerequisites

- Python 3.11+
- Internet access (for iNaturalist downloads)
- ~20 GB free disk space (for raw + prepared data)

```powershell
cd scripts/ml
pip install -r requirements.txt
```

---

## Workflow (run in order)

### Step 1 — Download iNaturalist images

```bash
python collect_inaturalist.py \
    --output-dir data/raw \
    --species-file species_list.json \
    --max-per-species 200
```

- Downloads up to 200 research-grade observations per species
- Only CC0, CC-BY, CC-BY-NC licensed images are saved
- Idempotent: already-downloaded images are skipped on re-run
- Runtime: ~2–4 hours on a standard connection (80 species × ~1 s/request)

### Step 2 — Normalize Fishial.ai images (manual dataset download required)

1. Register at <https://fishial.ai> and request dataset access
2. Download and extract the archive to `data/raw/fishial/`
3. Expected layout: `data/raw/fishial/<CommonSpeciesName>/<image_file>`

```bash
python collect_fishial.py \
    --fishial-dir data/raw/fishial \
    --output-dir data/raw \
    --species-file species_list.json
```

- Maps Fishial folder names to scientific names via `species_list.json`
- Copies images into `data/raw/<scientific_name_snake_case>/`
- Unmapped folders are logged for manual review

### Step 3 — Prepare the unified dataset

```bash
python prepare_dataset.py \
    --raw-dir data/raw \
    --output-dir data/prepared \
    --split 0.8,0.1,0.1 \
    --min-images 50
```

- Merges all `manifest.csv` files from `data/raw/`
- Drops species with fewer than 50 images (logs which ones)
- Stratified train/val/test split (80 / 10 / 10 by default)
- Copies images into split + species folders

---

## Expected output structure

```
scripts/ml/
├── data/
│   ├── raw/
│   │   ├── salmo_salar/          # one folder per species (snake_case)
│   │   │   ├── 12345678.jpg
│   │   │   └── ...
│   │   ├── gadus_morhua/
│   │   ├── fishial/              # extracted Fishial.ai archive
│   │   └── manifest.csv          # cumulative source manifest
│   └── prepared/
│       ├── train/
│       │   └── salmo_salar/
│       ├── val/
│       │   └── salmo_salar/
│       ├── test/
│       │   └── salmo_salar/
│       ├── dataset_manifest.csv  # full manifest with split column
│       ├── class_labels.json     # {class_index: scientific_name}
│       └── stats.json            # per-species/split image counts
```

> **Note:** `data/` is excluded from version control (`.gitignore`).
> Training data must be re-generated locally or retrieved from the team's
> shared storage.

---

## Adding a new species

1. Open `species_list.json` and append a new entry:
   ```json
   {
     "id": 80,
     "scientific_name": "Thunnus tonggol",
     "common_name_en": "Longtail Tuna",
     "fishbase_code": 147,
     "inat_taxon_id": 119218
   }
   ```
   - Find `fishbase_code` at <https://www.fishbase.se>
   - Find `inat_taxon_id` at <https://www.inaturalist.org>

2. Re-run `collect_inaturalist.py` (existing images are skipped).
3. Re-run `prepare_dataset.py` to regenerate splits and `class_labels.json`.
4. Copy `data/prepared/class_labels.json` to `assets/models/labels.json`
   in the Flutter app and retrain the model.

---

## Data licensing

| Source | License | Training use |
|--------|---------|--------------|
| iNaturalist (CC0) | Public domain | ✅ Unrestricted |
| iNaturalist (CC-BY) | Attribution required | ✅ OK for training; cite iNaturalist in model card |
| iNaturalist (CC-BY-NC) | Non-commercial | ✅ OK for EcoPal (non-commercial training) — **remove `cc-by-nc` from `ALLOWED_LICENSES` if commercial deployment is pursued** |
| Fishial.ai | Research license | ✅ Permitted for ML research; review current ToS before commercial deployment |
| Self-collected supermarket photos | Internal / all rights | ✅ |

> **Important note on image domain:**
> iNaturalist images are predominantly of **live fish in their natural habitat**.
> This creates a domain mismatch for a supermarket scanner that sees dead fish
> on ice under artificial lighting.
>
> **Mitigation strategy:**
> - Weight Fishial.ai images more heavily in training (they show dead fish)
> - Supplement with self-collected supermarket photos (place them in
>   `data/raw/<scientific_name_snake_case>/` and re-run `prepare_dataset.py`)
> - Apply aggressive data augmentation (brightness, colour jitter, rotation)
>   during training to improve cross-domain robustness
>
> The team should aim for **≥ 50 supermarket-domain images per species**.

---

## Model training (out of scope for this pipeline)

The training pipeline (Issue #13 — model fine-tuning phase) will:
1. Load images from `data/prepared/train/` and `data/prepared/val/`
2. Fine-tune EfficientNet-V2-S or MobileNetV3 via transfer learning
3. Export to `assets/models/fish_classifier_v1.tflite`
4. Copy `data/prepared/class_labels.json` → `assets/models/labels.json`

Refer to `docs/adr/002-ml-inference-strategy.md` for architecture decisions.
