#!/bin/bash

# Get current directory (where the original files are)
CURRENT_DIR=$(pwd)

# Array of input files and their corresponding output files (sag first as requested)
declare -a input_files=("sag.nii.gz" "cor.nii.gz" "ax.nii.gz")
declare -a output_files=("resam_sag.nii.gz" "resam_cor.nii.gz" "resam_ax.nii.gz")

echo "=== Starting Slicer Resampling ==="

# Arrays to store successfully processed files for MONAI
declare -a processed_resam_files=()
declare -a processed_seg_files=()

# Loop through each file for resampling
for i in "${!input_files[@]}"; do
    input_file="${input_files[$i]}"
    output_file="${output_files[$i]}"
    
    # Check if input file exists
    if [ ! -f "$input_file" ]; then
        echo "WARNING: $input_file not found, skipping..."
        continue
    fi
    
    echo "Processing $input_file -> $output_file"
    
    # Run Slicer processing
    ~/Downloads/Slicer-5.8.1-linux-amd64/Slicer --launcher-no-splash --python-code "
import slicer
import os
currentDir = os.getcwd()
try:
    slicer.util.loadVolume(os.path.join(currentDir, '$input_file'))
    inputVolume = slicer.util.getNode('${input_file%.*.*}')
    if inputVolume is None:
        print('ERROR: Failed to load $input_file')
        slicer.util.quit()
    outputVolume = slicer.vtkMRMLScalarVolumeNode()
    outputVolume.SetName('${output_file%.*.*}')
    slicer.mrmlScene.AddNode(outputVolume)
    parameters = {
        'InputVolume': inputVolume,
        'OutputVolume': outputVolume,
        'outputPixelSpacing': '0.8,0.8,0',
        'interpolationType': 'lanczos'
    }
    resampleModule = slicer.modules.resamplescalarvolume
    slicer.cli.runSync(resampleModule, None, parameters)
    slicer.util.saveNode(outputVolume, os.path.join(currentDir, '$output_file'))
    print('SUCCESS: Processed $input_file')
except Exception as e:
    print('ERROR processing $input_file:', str(e))
slicer.util.quit()
"
    
    # Check if output file was created successfully
    if [ -f "$output_file" ]; then
        echo "✓ Successfully processed $input_file -> $output_file"
        processed_resam_files+=("${CURRENT_DIR}/$output_file")
        # Determine corresponding segmentation output name
        seg_file="seg_${input_file%.*.*}.nii.gz"
        processed_seg_files+=("${CURRENT_DIR}/$seg_file")
    else
        echo "✗ Failed to process $input_file"
    fi
done

echo "=== Slicer Resampling Complete ==="
echo "Successfully processed ${#processed_resam_files[@]} files"

# Only proceed with MONAI if we have at least one processed file
if [ ${#processed_resam_files[@]} -eq 0 ]; then
    echo "ERROR: No files were successfully processed. Exiting."
    exit 1
fi

echo ""
echo "=== Starting MONAI Processing ==="
echo "Processing ${#processed_resam_files[@]} resampled files..."

# Change to NiftyMIC directory and activate environment
cd ~/NiftyMIC
source nifty_env/bin/activate

# Build the MONAI command with only successfully processed files
input_names_arg=""
segment_output_names_arg=""

for i in "${!processed_resam_files[@]}"; do
    input_names_arg="$input_names_arg ${processed_resam_files[$i]}"
    segment_output_names_arg="$segment_output_names_arg ${processed_seg_files[$i]}"
done

# Run MONAI with the available resampled files
echo "Running MONAI with files: $input_names_arg"

python3 -m monaifbs.fetal_brain_seg \
  --input_names $input_names_arg \
  --segment_output_names $segment_output_names_arg

# Check MONAI exit status
if [ $? -eq 0 ]; then
    echo "=== MONAI Processing Complete ==="
    echo "Successfully processed ${#processed_resam_files[@]} files!"
    echo ""
    echo "Generated files:"
    echo "Resampled files:"
    for file in "${processed_resam_files[@]}"; do
        echo "  - $(basename "$file")"
    done
    echo "Segmented files:"
    for file in "${processed_seg_files[@]}"; do
        if [ -f "$(basename "$file")" ] || [ -f "$file" ]; then
            echo "  - $(basename "$file")"
        fi
    done
else
    echo "ERROR: MONAI processing failed"
    deactivate
    cd "$CURRENT_DIR"
    exit 1
fi

# Deactivate environment
deactivate

# Return to original directory
cd "$CURRENT_DIR"

echo ""
echo "=== Pipeline Complete ==="
echo "Processed ${#processed_resam_files[@]} out of ${#input_files[@]} input files"
