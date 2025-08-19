# Automatically detect the dataset ID (assumes only one folder in workdir)
DATASET_ID=$(ls workdir/)
# Create the ksi folder (or clear it if it exists)
rm -rf ksi
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

# Run Python ANTs reorientation on the 5 files
echo "Processing ${DATASET_ID}_pial_minus_white.nii.gz..."
python3.10 -c "
import ants
img = ants.image_read('${DATASET_ID}_pial_minus_white.nii.gz')
img_asl = img.reorient_image2('ASL')
img_asl.image_write('${DATASET_ID}_pial_minus_white_ASL.nii.gz')
"

echo "Processing ${DATASET_ID}_combined_white.nii.gz..."
python3.10 -c "
import ants
img = ants.image_read('${DATASET_ID}_combined_white.nii.gz')
img_asl = img.reorient_image2('ASL')
img_asl.image_write('${DATASET_ID}_combined_white_ASL.nii.gz')
"

echo "Processing ${DATASET_ID}_L_pial.nii.gz..."
python3.10 -c "
import ants
img = ants.image_read('${DATASET_ID}_L_pial.nii.gz')
img_asl = img.reorient_image2('ASL')
img_asl.image_write('${DATASET_ID}_L_pial_ASL.nii.gz')
"

echo "Processing ${DATASET_ID}_R_pial.nii.gz..."
python3.10 -c "
import ants
img = ants.image_read('${DATASET_ID}_R_pial.nii.gz')
img_asl = img.reorient_image2('ASL')
img_asl.image_write('${DATASET_ID}_R_pial_ASL.nii.gz')
"

echo "Processing ${DATASET_ID}.nii.gz..."
python3.10 -c "
import ants
img = ants.image_read('${DATASET_ID}.nii.gz')
img_asl = img.reorient_image2('ASL')
img_asl.image_write('${DATASET_ID}_ASL.nii.gz')
"

echo "All processing complete!"

# Navigate to KSI-India directory and run seal commands
cd /home/htic/VedantSingh/ksi3/KSI-India/KSI-India-main

# Extract the base dataset ID (remove -s1 suffix if present) to get the folder name
BASE_DATASET_ID=$(echo ${DATASET_ID} | sed 's/-s1$//')

# Define variables for seal processing (use absolute path to ksi folder)
data_folder="/home/htic/VedantSingh/${BASE_DATASET_ID}/ksi"
results_folder="/home/htic/VedantSingh/ksi3/KSI-India/KSI-India-main/output"
subj="${DATASET_ID}"
brain="srr_deconvoluted.nii.gz"
extract_brain="${DATASET_ID}_ASL.nii.gz"
rh_mask="${DATASET_ID}_R_pial_ASL.nii.gz"
lh_mask="${DATASET_ID}_L_pial_ASL.nii.gz"
pial_file="${DATASET_ID}_pial_minus_white_ASL.nii.gz"
wm_file="${DATASET_ID}_combined_white_ASL.nii.gz"

# Run the freesurfer_surface command
echo "Running KSI surface analysis..."
echo "Data folder: ${data_folder}"
echo "Subject: ${subj}"
./bin/freesurfer_surface.sh -s "${subj}" \
                        -i "${data_folder}/${extract_brain}" \
                        -R "${data_folder}/${rh_mask}" \
                        -L "${data_folder}/${lh_mask}" \
                        -P "${data_folder}/${pial_file}" \
                        -W "${data_folder}/${wm_file}" \
                        -o "${results_folder}"

echo "KSI processing complete!"
