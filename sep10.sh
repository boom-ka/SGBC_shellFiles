#!/bin/bash

# Automatically detect subject ID from existing files
SUBJECT_ID=$(ls *-s1_all_labels.nii.gz 2>/dev/null | head -1 | sed 's/-s1_all_labels.nii.gz//')

if [ -z "$SUBJECT_ID" ]; then
    echo "Error: Could not detect subject ID. Make sure *-s1_all_labels.nii.gz file exists."
    exit 1
fi

echo "Detected subject ID: $SUBJECT_ID"

# Remove registration directory if it exists
if [ -d "registration" ]; then
    echo "Removing existing registration directory..."
    rm -rf registration
fi

# Create new registration directory
echo "Creating registration directory..."
mkdir registration

# Find the t2w tissue file (with any age)
T2W_FILE=$(ls t2w_GA*_tissue.nii.gz 2>/dev/null | head -1)

if [ -z "$T2W_FILE" ]; then
    echo "Warning: Could not find t2w_GA*_tissue.nii.gz file"
else
    echo "Found t2w tissue file: $T2W_FILE"
fi

# Copy the specified files to registration directory
echo "Copying files to registration directory..."
cp ${SUBJECT_ID}-s1_all_labels.nii.gz registration/
cp ${SUBJECT_ID}-s1_combined_white.nii.gz registration/
cp ${SUBJECT_ID}-s1_extracted.nii.gz registration/
cp ${SUBJECT_ID}-s1_L_pial.nii.gz registration/
cp ${SUBJECT_ID}-s1_pial_minus_white.nii.gz registration/
cp ${SUBJECT_ID}-s1_R_pial.nii.gz registration/

# Copy the t2w tissue file if found
if [ -n "$T2W_FILE" ]; then
    cp "$T2W_FILE" registration/
fi

echo "Done! Registration directory created with files for subject: $SUBJECT_ID"

# List the contents of the registration directory
echo "Contents of registration directory:"
ls -la registration/

# Navigate to registration directory for processing
cd registration

echo ""
echo "Starting image processing pipeline..."

# Step 1: Normalization
echo "Step 1: Normalizing ${SUBJECT_ID}-s1_extracted.nii.gz..."
docker run --rm \
  -v $(pwd):/data \
  antsx/ants:master \
  ImageMath 3 /data/${SUBJECT_ID}-s1_normalized.nii.gz RescaleImage /data/${SUBJECT_ID}-s1_extracted.nii.gz 0 100

if [ $? -eq 0 ]; then
    echo "✅ Normalization completed: ${SUBJECT_ID}-s1_normalized.nii.gz"
else
    echo "❌ Error during normalization"
    exit 1
fi

# Step 2: Denoising
echo "Step 2: Denoising ${SUBJECT_ID}-s1_normalized.nii.gz..."
nsol_run_denoising \
--observation ${SUBJECT_ID}-s1_normalized.nii.gz \
--result ${SUBJECT_ID}-s1_denoised.nii.gz \
--reconstruction-type TVL1 \
--alpha 0.05 \
--iterations 50

if [ $? -eq 0 ]; then
    echo "✅ Denoising completed: ${SUBJECT_ID}-s1_denoised.nii.gz"
else
    echo "❌ Error during denoising"
    exit 1
fi

# Step 3: Deconvolution
echo "Step 3: Deconvolving ${SUBJECT_ID}-s1_denoised.nii.gz..."
nsol_run_deconvolution \
--observation ${SUBJECT_ID}-s1_denoised.nii.gz \
--result ${SUBJECT_ID}-s1_deconvolved.nii.gz \
--reconstruction-type TK1L2 \
--blur 0.1 \
--alpha 0.05 \
--iterations 50 \
--verbose 1

if [ $? -eq 0 ]; then
    echo "✅ Deconvolution completed: ${SUBJECT_ID}-s1_deconvolved.nii.gz"
else
    echo "❌ Error during deconvolution"
    exit 1
fi

echo ""
echo "Image processing pipeline completed!"
echo "Processed files:"
ls -la ${SUBJECT_ID}-s1_*.nii.gz

echo ""
echo "Running Python registration script..."

# Create and run the Python registration script
cat << EOF > run_registration.py
import ants
import os
import glob

# Set registration directory
reg_dir = "."

# ---- Step 1: Identify files ----
atlas = glob.glob(os.path.join(reg_dir, "t2w_GA*_tissue.nii.gz"))
moving_vol = os.path.join(reg_dir, "${SUBJECT_ID}-s1_deconvolved.nii.gz")
mask_files = glob.glob(os.path.join(reg_dir, "*.nii.gz"))
# Remove atlas, moving volume, and processed files from mask list
mask_files = [f for f in mask_files if "t2w_GA" not in f and "s1_normalized" not in f and "s1_denoised" not in f and "s1_deconvolved" not in f and "s1_extracted" not in f]

if len(atlas) == 0:
    raise FileNotFoundError("No atlas file found (t2w_GA##_tissue.nii.gz)")
if not os.path.exists(moving_vol):
    raise FileNotFoundError("${SUBJECT_ID}-s1_deconvolved.nii.gz not found")

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
EOF

# Run the Python script
python run_registration.py

echo ""
echo "Registration process completed!"
echo "Final contents of registration directory:"
ls -la

echo ""
echo "Starting KSI processing..."

# Navigate to KSI-India directory
cd /home/htic/VedantSingh/ksi3/KSI-India-main

# Extract the base dataset ID (remove -s1 suffix if present) to get the folder name
BASE_DATASET_ID=$(echo ${SUBJECT_ID} | sed 's/-s1$//')

# Define variables for seal processing (use absolute path to registration folder)
data_folder="/media/htic/e033a0c2-67d8-4513-980a-6510b2739f87/vedantSinghduplicate/${SUBJECT_ID}RAI/ksi/registration"

results_folder="/home/htic/VedantSingh/ksi3/KSI-India-main/output"
subj="${SUBJECT_ID}"
brain="srr_registered.nii.gz"
extract_brain="${SUBJECT_ID}-s1_extracted_rai.nii.gz"
full_label_mask="${SUBJECT_ID}-s1_all_labels_rai.nii.gz"
rh_mask="${SUBJECT_ID}-s1_R_pial_rai.nii.gz"
lh_mask="${SUBJECT_ID}-s1_L_pial_rai.nii.gz"
pial_file="${SUBJECT_ID}-s1_pial_minus_white_rai.nii.gz"
wm_file="${SUBJECT_ID}-s1_combined_white_rai.nii.gz"

# Run the freesurfer_surface command
echo "Running KSI surface analysis..."
echo "Data folder: ${data_folder}"
echo "Subject: ${subj}"
echo "Brain file: ${brain}"

./bin/freesurfer_surface.sh -s "${subj}" \
                        -i "${data_folder}/${extract_brain}" \
                        -m "${data_folder}/${full_label_mask}" \
                        -R "${data_folder}/${rh_mask}" \
                        -L "${data_folder}/${lh_mask}" \
                        -P "${data_folder}/${pial_file}" \
                        -W "${data_folder}/${wm_file}" \
                        -o "${results_folder}"

echo "✅ KSI processing complete!"
echo "Results saved to: ${results_folder}"
