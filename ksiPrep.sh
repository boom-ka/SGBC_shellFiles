# Automatically detect the dataset ID (assumes only one folder in workdir)
DATASET_ID=$(ls workdir/)

# Create the ksi folder
mkdir ksi



cp srr_deconvoluted.nii.gz ksi/


# Copy the file from N4 folder
cp workdir/${DATASET_ID}/N4/${DATASET_ID}.nii.gz ksi/

# Copy the segmentation files to ksi folder
cp workdir/${DATASET_ID}/segmentations/${DATASET_ID}_R_pial.nii.gz ksi/
cp workdir/${DATASET_ID}/segmentations/${DATASET_ID}_L_pial.nii.gz ksi/
cp workdir/${DATASET_ID}/segmentations/${DATASET_ID}_L_white.nii.gz ksi/
cp workdir/${DATASET_ID}/segmentations/${DATASET_ID}_R_white.nii.gz ksi/

# Go to ksi folder and perform operations
cd ksi

# Combine left and right white matter files
fslmaths ${DATASET_ID}_L_white.nii.gz -add ${DATASET_ID}_R_white.nii.gz ${DATASET_ID}_combined_white.nii.gz

# Combine left and right pial files
fslmaths ${DATASET_ID}_L_pial.nii.gz -add ${DATASET_ID}_R_pial.nii.gz ${DATASET_ID}_combined_pial.nii.gz

# Subtract white from pial (pial - white)
fslmaths ${DATASET_ID}_combined_pial.nii.gz -sub ${DATASET_ID}_combined_white.nii.gz ${DATASET_ID}_pial_minus_white.nii.gz

# Run fslswapdim and fslorient commands on the 5 files
echo "Processing ${DATASET_ID}_pial_minus_white.nii.gz..."
fslswapdim ${DATASET_ID}_pial_minus_white.nii.gz AP SI LR ${DATASET_ID}_pial_minus_white_ASL.nii.gz
fslorient -copysform2qform ${DATASET_ID}_pial_minus_white_ASL.nii.gz

echo "Processing ${DATASET_ID}_combined_white.nii.gz..."
fslswapdim ${DATASET_ID}_combined_white.nii.gz AP SI LR ${DATASET_ID}_combined_white_ASL.nii.gz
fslorient -copysform2qform ${DATASET_ID}_combined_white_ASL.nii.gz

echo "Processing ${DATASET_ID}_L_pial.nii.gz..."
fslswapdim ${DATASET_ID}_L_pial.nii.gz AP SI LR ${DATASET_ID}_L_pial_ASL.nii.gz
fslorient -copysform2qform ${DATASET_ID}_L_pial_ASL.nii.gz

echo "Processing ${DATASET_ID}_R_pial.nii.gz..."
fslswapdim ${DATASET_ID}_R_pial.nii.gz AP SI LR ${DATASET_ID}_R_pial_ASL.nii.gz
fslorient -copysform2qform ${DATASET_ID}_R_pial_ASL.nii.gz

echo "Processing ${DATASET_ID}.nii.gz..."
fslswapdim ${DATASET_ID}.nii.gz AP SI LR ${DATASET_ID}_ASL.nii.gz
fslorient -copysform2qform ${DATASET_ID}_ASL.nii.gz

echo "All processing complete!"
