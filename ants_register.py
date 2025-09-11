"""
Usage Instructions:
-------------------
1. Place all required files in a single folder, e.g. `registration/`
   - Atlas tissue reference: t2w_GA##_tissue.nii.gz  (example: t2w_GA37_tissue.nii.gz)
   - Subject SRR volume:     srr_deconv.nii.gz
   - Subject segmentations:  *_L_pial.nii.gz, *_R_pial.nii.gz, *_L_white.nii.gz, *_R_white.nii.gz

2. Edit the variable `reg_dir` below to point to your registration folder.

3. Run this script with Python:
       python register_subject.py

4. Output:
   - Registered SRR volume:    srr_registered.nii.gz
   - Registered masks:         *_registered.nii.gz
   All results are saved in the same folder.
"""

import ants
import glob
import os

# ---- CONFIG ----
reg_dir = "/media/htic/e033a0c2-67d8-4513-980a-6510b2739f87/vedantSinghduplicate/FX27RAI/ksi/registeration"  # Change this to your folder

# ---- Step 1: Identify files ----
atlas = glob.glob(os.path.join(reg_dir, "t2w_GA*_tissue.nii.gz"))
moving_vol = os.path.join(reg_dir, "FX27-s1_extracted.nii.gz")
mask_files = glob.glob(os.path.join(reg_dir, "*.nii.gz"))

# Remove atlas and moving volume from mask list
mask_files = [f for f in mask_files if "t2w_GA" not in f and "srr_deconv" not in f]

if len(atlas) == 0:
    raise FileNotFoundError("No atlas file found (t2w_GA##_tissue.nii.gz)")
if not os.path.exists(moving_vol):
    raise FileNotFoundError("srr_deconv.nii.gz not found")

atlas = atlas[0]  # Use the first match
print(f"Using atlas: {atlas}")
print(f"Using moving volume: {moving_vol}")
print(f"Found {len(mask_files)} masks")

# ---- Step 2: Load images ----
fixed = ants.image_read(atlas)
moving = ants.image_read(moving_vol)

# ---- Step 3: Perform registration ----
print("Running rigid registration...")
reg = ants.registration(
    fixed=fixed,
    moving=moving,
    type_of_transform="Rigid",
    initial_transform="Identity"
)

# Save registered moving volume
out_moving = os.path.join(reg_dir, "srr_registered.nii.gz")
ants.image_write(reg["warpedmovout"], out_moving)
print(f"Saved registered SRR volume: {out_moving}")

# ---- Step 4: Apply transform to masks ----
for mask_file in mask_files:
    mask = ants.image_read(mask_file)
    mask_reg = ants.apply_transforms(
        fixed=fixed,
        moving=mask,
        transformlist=reg["fwdtransforms"],
        interpolator="nearestNeighbor"
    )

    out_mask = mask_file.replace(".nii.gz", "_rai.nii.gz")
    ants.image_write(mask_reg, out_mask)
    print(f"Saved registered mask: {out_mask}")

print("✅ Registration completed for all files.")
