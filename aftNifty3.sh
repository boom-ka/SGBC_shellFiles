#!/bin/bash
set -e

# -------------------------------
# Step 1: Find the fixed STA* file
# -------------------------------
FIXED_IMAGE=$(ls STA*.nii.gz 2>/dev/null | head -n 1)

if [ -z "$FIXED_IMAGE" ]; then
  echo "Error: No STA*.nii.gz file found in current directory."
  exit 1
fi

echo "Using fixed image: $FIXED_IMAGE"

# -------------------------------
# Step 2: Run ANTs registration
# -------------------------------
sudo docker run --rm -it \
  -v "$PWD":/data \
  antsx/ants:latest \
  antsRegistrationSyNQuick.sh \
  -d 3 \
  -f /data/"$FIXED_IMAGE" \
  -m /data/srr.nii.gz \
  -o /data/srr_

# -------------------------------
# Step 3: Mask with STA*
# -------------------------------
if [ ! -f "srr_Warped.nii.gz" ]; then
  echo "Error: srr_Warped.nii.gz not generated!"
  exit 1
fi

echo "Running fslmaths with mask: $FIXED_IMAGE"
fslmaths srr_Warped.nii.gz -mas "$FIXED_IMAGE" srr_sta_sub.nii.gz

# -------------------------------
# Step 4: Invert Untitled.nii.gz
# -------------------------------
if [ ! -f "Untitled.nii.gz" ]; then
  echo "Error: Untitled.nii.gz not found!"
  exit 1
fi

echo "Running fslmaths inversion on Untitled.nii.gz"
fslmaths Untitled.nii.gz -binv extracted_correction_mask_inv.nii.gz

# -------------------------------
# Step 5: Apply inverse mask
# -------------------------------
if [ ! -f "extracted_correction_mask_inv.nii.gz" ]; then
  echo "Error: extracted_correction_mask_inv.nii.gz not created!"
  exit 1
fi

echo "Applying inverse correction mask..."
fslmaths srr_sta_sub.nii.gz -mas extracted_correction_mask_inv.nii.gz srr_final.nii.gz

echo "✅ Pipeline complete!"
echo "Generated files:"
echo " - srr_Warped.nii.gz"
echo " - srr_sta_sub.nii.gz"
echo " - extracted_correction_mask_inv.nii.gz"
echo " - srr_final.nii.gz"

