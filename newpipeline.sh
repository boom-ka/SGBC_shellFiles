#!/bin/bash

# =========================
# Pre-authenticate sudo
# =========================
echo "🔑 Please enter your sudo password (for Docker)..."
sudo -v

# =========================
# Step 1: Locate session folder and extract IDs
# =========================
SESSION_DIR=$(find ./workdir -maxdepth 1 -type d -name "*-*" | head -n 1)

if [ -z "$SESSION_DIR" ]; then
    echo "No session folder found in ./workdir"
    exit 1
fi

SESSION_NAME=$(basename "$SESSION_DIR")
DATA_ID=$(echo "$SESSION_NAME" | cut -d'-' -f1)

echo "Found data ID: $DATA_ID"
echo "Found session: $SESSION_NAME"

# =========================
# Step 2: Define source and destination paths
# =========================
SRC_DIR_N4="${SESSION_DIR}/N4"
SRC_DIR_SEG="${SESSION_DIR}/segmentations"
DEST_DIR="./ksi"

# Validate source dirs
if [ ! -d "$SRC_DIR_N4" ]; then
    echo "Source directory $SRC_DIR_N4 does not exist!"
    exit 1
fi

if [ ! -d "$SRC_DIR_SEG" ]; then
    echo "Source directory $SRC_DIR_SEG does not exist!"
    exit 1
fi

# =========================
# Step 3: Create / clear destination
# =========================
if [ ! -d "$DEST_DIR" ]; then
    mkdir -p "$DEST_DIR"
else
    rm -rf "$DEST_DIR"/*
fi

# =========================
# Step 4: Copy N4 nii.gz files
# =========================
cp "$SRC_DIR_N4"/*.nii.gz "$DEST_DIR"/

# =========================
# Step 5: Copy required segmentation files
# =========================
cp "$SRC_DIR_SEG/${SESSION_NAME}_all_labels.nii.gz" "$DEST_DIR"/
cp "$SRC_DIR_SEG/${SESSION_NAME}_L_pial.nii.gz" "$DEST_DIR"/
cp "$SRC_DIR_SEG/${SESSION_NAME}_R_pial.nii.gz" "$DEST_DIR"/
cp "$SRC_DIR_SEG/${SESSION_NAME}_L_white.nii.gz" "$DEST_DIR"/
cp "$SRC_DIR_SEG/${SESSION_NAME}_R_white.nii.gz" "$DEST_DIR"/
cp "$SRC_DIR_SEG/${SESSION_NAME}_tissue_labels.nii.gz" "$DEST_DIR"/

# =========================
# Step 6: Create brain mask (remove label 4)
# =========================
cd "$DEST_DIR" || exit 1
TISSUE_FILE=$(ls ${SESSION_NAME}_tissue_labels.nii.gz | head -n 1)

if [ -z "$TISSUE_FILE" ]; then
    echo "Tissue labels file not found in $DEST_DIR!"
    exit 1
fi

fslmaths "$TISSUE_FILE" -thr 1 -bin temp_all
fslmaths "$TISSUE_FILE" -thr 4 -uthr 4 -bin temp_remove
fslmaths temp_all -sub temp_remove brain_mask.nii.gz
rm temp_all.nii.gz temp_remove.nii.gz
echo "✅ Brain mask created: brain_mask.nii.gz"

# =========================
# Step 7: Apply mask to N4 file and create *_extracted
# =========================
N4_FILE=$(ls *.nii.gz | grep -v "labels" | grep -v "pial" | grep -v "white" | grep -v "tissue" | grep -v "brain_mask" | head -n 1)

if [ -z "$N4_FILE" ]; then
    echo "No N4 file found in $DEST_DIR!"
    exit 1
fi

BASE_NAME="${N4_FILE%.nii.gz}"
EXTRACTED_FILE="${BASE_NAME}_extracted.nii.gz"

echo "🛑 Please edit brain_mask.nii.gz as needed before continuing."
read -p "Press ENTER once you are done editing the mask..."

fslmaths "$N4_FILE" -mas brain_mask.nii.gz "$EXTRACTED_FILE"
echo "✅ Extracted file created: $EXTRACTED_FILE"


# =========================
# Step 8: Run denoising
# =========================
DENOISED_FILE="${BASE_NAME}_extracted_denoising.nii.gz"

nsol_run_denoising \
  --observation "$EXTRACTED_FILE" \
  --result "$DENOISED_FILE" \
  --reconstruction-type TVL1 \
  --alpha 0.05 \
  --iterations 50

if [ $? -eq 0 ]; then
    echo "✅ Denoised file created: $DENOISED_FILE"
else
    echo "❌ Denoising failed!"
    exit 1
fi

# =========================
# Step 9: Run deconvolution
# =========================
DECONV_FILE="${BASE_NAME}_extracted_denoising_deconv.nii.gz"

nsol_run_deconvolution \
  --observation "$DENOISED_FILE" \
  --result "$DECONV_FILE" \
  --reconstruction-type TK1L2 \
  --blur 0.1 \
  --alpha 0.05 \
  --iterations 50 \
  --verbose 1

if [ $? -eq 0 ]; then
    echo "✅ Deconvoluted file created: $DECONV_FILE"
else
    echo "❌ Deconvolution failed!"
    exit 1
fi

# =========================
# Step 10: Combine surfaces and reorient with ANTs
# =========================
echo "🔄 Running surface combinations and reorientation..."

# Combine left and right white matter
fslmaths ${SESSION_NAME}_L_white.nii.gz -add ${SESSION_NAME}_R_white.nii.gz ${SESSION_NAME}_combined_white.nii.gz

# Combine left and right pial surfaces
fslmaths ${SESSION_NAME}_L_pial.nii.gz -add ${SESSION_NAME}_R_pial.nii.gz ${SESSION_NAME}_combined_pial.nii.gz

# Subtract white from pial (pial - white)
fslmaths ${SESSION_NAME}_combined_pial.nii.gz -sub ${SESSION_NAME}_combined_white.nii.gz ${SESSION_NAME}_pial_minus_white.nii.gz

# Reorient selected files with ANTs (RAI)
for FILE in \
    "${SESSION_NAME}_pial_minus_white.nii.gz" \
    "${SESSION_NAME}_combined_white.nii.gz" \
    "${SESSION_NAME}_L_pial.nii.gz" \
    "${SESSION_NAME}_R_pial.nii.gz" \
    "${SESSION_NAME}_all_labels.nii.gz" \
    "${BASE_NAME}_extracted_denoising_deconv.nii.gz"
do
    echo "Processing ${FILE}..."
    python3.10 -c "
import ants
img = ants.image_read('${FILE}')
img_RAI = img.reorient_image2('RAI')
img_RAI.image_write('${FILE%.nii.gz}_RAI.nii.gz')
"
done

echo "✅ All processing complete!"




# =========================
# Step 11: Copy atlas file (t2w_GA*_atlas.nii.gz)
# =========================
ATLAS_FILE=$(ls ../t2w_GA*_atlas.nii.gz 2>/dev/null | head -n 1)
if [ -n "$ATLAS_FILE" ]; then
    cp "$ATLAS_FILE" .
    ATLAS_BASENAME=$(basename "$ATLAS_FILE")
    echo "✅ Atlas file copied: $ATLAS_BASENAME"
else
    echo "❌ Atlas file (t2w_GA*_atlas.nii.gz) not found in parent directory!"
    exit 1
fi

# =========================
# Step 12: Register extracted file to atlas with ANTs (Docker)
# =========================
MOVING_FILE="${BASE_NAME}_extracted_denoising_deconv_RAI.nii.gz"
OUTPUT_PREFIX="${BASE_NAME}_register_"

if [ ! -f "$MOVING_FILE" ]; then
    echo "❌ Moving file $MOVING_FILE not found!"
    exit 1
fi

echo "🔄 Running ANTs registration in Docker..."
sudo docker run --rm -it \
   -v "$PWD":/data \
   antsx/ants:latest \
   antsRegistrationSyNQuick.sh \
      -d 3 \
      -f /data/"$ATLAS_BASENAME" \
      -m /data/"$MOVING_FILE" \
      -o /data/"$OUTPUT_PREFIX"

if [ $? -eq 0 ]; then
    echo "✅ Registration complete! Output prefix: $OUTPUT_PREFIX"
else
    echo "❌ Registration failed!"
    exit 1
fi

echo "✅ All processing complete!"



# =========================
# Step 13: Run freesurfer_surface.sh in processing directory
# =========================
# =========================
# Step 13: Run freesurfer_surface.sh in processing directory
# =========================

# Remember the absolute path to where we created ./ksi earlier
WORKROOT="$(pwd)"
DEST_DIR_ABS="${WORKROOT}"

PROJECT_ROOT="/home/htic/VedantSingh/ksi3/KSI-India/KSI-India-main"
PROCESSING_DIR="${PROJECT_ROOT}/processing"
FREESURFER_SH="${PROJECT_ROOT}/bin/freesurfer_surface.sh"

# Sanity checks
if [ ! -d "$PROCESSING_DIR" ]; then
  echo "❌ Processing directory not found: $PROCESSING_DIR"
  exit 1
fi

if [ ! -f "$FREESURFER_SH" ]; then
  echo "❌ Script not found: $FREESURFER_SH"
  echo "   Run: ls -l \"${PROCESSING_DIR}/bin\" to verify"
  exit 1
fi

# Make sure it is executable
if [ ! -x "$FREESURFER_SH" ]; then
  echo "ℹ️  Making ${FREESURFER_SH} executable"
  chmod +x "$FREESURFER_SH" || { echo "❌ chmod failed"; exit 1; }
fi

cd "$PROCESSING_DIR" || { echo "❌ Failed to cd into $PROCESSING_DIR"; exit 1; }

# Use absolute paths for inputs/outputs
BASE_DATASET_ID="$(echo "${SESSION_NAME}" | sed 's/-s1$//')"
data_folder="${DEST_DIR_ABS}"   # <-- the ksi we built earlier
results_folder="/home/htic/VedantSingh/ksi3/output_RAI/${SESSION_NAME_}_RAI"
subj="${SESSION_NAME}"
extract_brain="${BASE_NAME}_register_Warped.nii.gz"
rh_mask="${SESSION_NAME}_R_pial_RAI.nii.gz"
lh_mask="${SESSION_NAME}_L_pial_RAI.nii.gz"
pial_file="${SESSION_NAME}_pial_minus_white_RAI.nii.gz"
wm_file="${SESSION_NAME}_combined_white_RAI.nii.gz"
full_label_mask="${SESSION_NAME}_all_labels_RAI.nii.gz"

# Verify the required inputs exist in data_folder
for f in \
  "${extract_brain}" \
  "${rh_mask}" "${lh_mask}" \
  "${pial_file}" "${wm_file}" \
  "${full_label_mask}"; do
  if [ ! -f "${data_folder}/${f}" ]; then
    echo "❌ Missing required input: ${data_folder}/${f}"
    exit 1
  fi
done

echo "🔄 Running freesurfer_surface.sh..."
"${FREESURFER_SH}" -s "${subj}" \
   -i "${data_folder}/${extract_brain}" \
   -m "${data_folder}/${full_label_mask}" \
   -R "${data_folder}/${rh_mask}" \
   -L "${data_folder}/${lh_mask}" \
   -P "${data_folder}/${pial_file}" \
   -W "${data_folder}/${wm_file}" \
   -o "${results_folder}"

if [ $? -eq 0 ]; then
  echo "✅ KSI processing complete!"
else
  echo "❌ freesurfer_surface.sh failed!"
  exit 1
fi


