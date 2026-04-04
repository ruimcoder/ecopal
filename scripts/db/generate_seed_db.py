"""
generate_seed_db.py
Reads scripts/ml/species_list.json and produces assets/data/ecopal_seed.db,
a pre-seeded SQLite file bundled in the APK for offline use from first launch.

Schema matches Issue #15 (species_cache, common_names, regional_flags tables).
"""

import json
import os
import sqlite3
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

SPECIES_JSON = os.path.join(REPO_ROOT, "scripts", "ml", "species_list.json")
OUTPUT_PATH = os.path.join(REPO_ROOT, "assets", "data", "ecopal_seed.db")


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS species_cache (
            scientific_name   TEXT PRIMARY KEY,
            seafood_watch_rating TEXT,
            seafood_watch_notes  TEXT,
            cites_appendix    TEXT,
            fishbase_code     INTEGER,
            fetched_at        INTEGER NOT NULL,
            expires_at        INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS common_names (
            scientific_name TEXT NOT NULL,
            language_code   TEXT NOT NULL,
            common_name     TEXT NOT NULL,
            PRIMARY KEY (scientific_name, language_code)
        );

        CREATE TABLE IF NOT EXISTS regional_flags (
            scientific_name TEXT NOT NULL,
            list_name       TEXT NOT NULL,
            status          TEXT NOT NULL,
            PRIMARY KEY (scientific_name, list_name)
        );
    """)


def seed_species(conn: sqlite3.Connection, species: list) -> None:
    for sp in species:
        scientific_name = sp["scientific_name"]
        fishbase_code = sp.get("fishbase_code")
        common_name_en = sp.get("common_name_en")

        conn.execute(
            """
            INSERT OR REPLACE INTO species_cache
                (scientific_name, seafood_watch_rating, seafood_watch_notes,
                 cites_appendix, fishbase_code, fetched_at, expires_at)
            VALUES (?, 'notRated', NULL, NULL, ?, 0, 0)
            """,
            (scientific_name, fishbase_code),
        )

        if common_name_en:
            conn.execute(
                """
                INSERT OR REPLACE INTO common_names
                    (scientific_name, language_code, common_name)
                VALUES (?, 'en', ?)
                """,
                (scientific_name, common_name_en),
            )


def validate_db(path: str, expected_count: int) -> None:
    """LP-003: verify the generated SQLite file can be opened."""
    conn = sqlite3.connect(path)
    try:
        (count,) = conn.execute("SELECT COUNT(*) FROM species_cache").fetchone()
        if count != expected_count:
            raise RuntimeError(
                f"Validation failed: expected {expected_count} rows, got {count}"
            )
        conn.execute("SELECT COUNT(*) FROM common_names").fetchone()
        conn.execute("SELECT COUNT(*) FROM regional_flags").fetchone()
    finally:
        conn.close()


def main() -> None:
    with open(SPECIES_JSON, encoding="utf-8") as fh:
        data = json.load(fh)

    species = data["species"]
    print(f"Loaded {len(species)} species from {SPECIES_JSON}")

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    # Write to a temp file first, then move atomically (LP-003 validate before
    # overwriting the asset).
    tmp_fd, tmp_path = tempfile.mkstemp(
        suffix=".db", dir=os.path.dirname(OUTPUT_PATH)
    )
    os.close(tmp_fd)

    try:
        conn = sqlite3.connect(tmp_path)
        try:
            create_schema(conn)
            seed_species(conn, species)
            conn.commit()
        finally:
            conn.close()

        validate_db(tmp_path, len(species))
        print(f"Validation passed — {len(species)} species_cache rows.")

        # Atomically replace the output file.
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        os.replace(tmp_path, OUTPUT_PATH)
        tmp_path = None

        size_kb = os.path.getsize(OUTPUT_PATH) / 1024
        print(f"Written to {OUTPUT_PATH}  ({size_kb:.1f} KB)")

    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


if __name__ == "__main__":
    main()
    sys.exit(0)
