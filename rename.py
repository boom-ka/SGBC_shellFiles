import os
from pathlib import Path

def remove_quality_prefix_from_folders(master_folder_path, dry_run=True):
    master_path = Path(master_folder_path)

    if not master_path.exists():
        print(f"❌ Error: Folder not found: {master_folder_path}")
        return

    renamed = []

    for folder in master_path.iterdir():
        if folder.is_dir() and not folder.name.startswith("."):
            parts = folder.name.split("_", 2)

            # Check for the 3-part pattern: score_quality_original
            if len(parts) == 3 and parts[0].isdigit():
                original_name = parts[2]
                new_path = folder.parent / original_name

                print(f"🔄 Renaming: {folder.name} → {original_name}")

                if not dry_run:
                    try:
                        folder.rename(new_path)
                        print(" ✅ Renamed")
                        renamed.append((folder.name, original_name))
                    except Exception as e:
                        print(f" ❌ Rename failed: {e}")
                else:
                    print(" 🔍 Dry run - no changes made")

    if dry_run:
        print("\nℹ️ Dry run completed. Rerun with `dry_run=False` to apply changes.")
    else:
        print(f"\n✅ Renamed {len(renamed)} folders.")

# Example usage:
if __name__ == "__main__":
    MASTER_FOLDER = "/home/htic/VedantSingh/CASE0030_0003016796 (copy)"
    remove_quality_prefix_from_folders(MASTER_FOLDER, dry_run=False)

    # To actually rename:
    # remove_quality_prefix_from_folders(MASTER_FOLDER, dry_run=False)

