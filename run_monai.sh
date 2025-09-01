#!/bin/bash

# Usage: ./run_monai.sh <resampled_file> [segmented_output_file]

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <resampled_file> [segmented_output_file]"
    exit 1
fi

RESAMPLED_FILE=$1

# If no output file is provided, create one by appending "_mask"
if [ $# -eq 2 ]; then
    SEGMENTED_FILE=$2
else
    filename=$(basename -- "$RESAMPLED_FILE")
    extension="${filename##*.}"
    name="${filename%.*}"

    # Handle .nii.gz properly
    if [[ "$filename" == *.nii.gz ]]; then
        name="${filename%.nii.gz}"
        SEGMENTED_FILE="${name}_mask.nii.gz"
    else
        SEGMENTED_FILE="${name}_mask.${extension}"
    fi
fi

# Save current directory
CURRENT_DIR=$(pwd)

# Change to NiftyMIC directory and activate environment
cd ~/NiftyMIC || exit 1
source nifty_env/bin/activate

# Run MONAI with the given file
echo "Running MONAI with input: $RESAMPLED_FILE"
echo "Output will be saved as: $SEGMENTED_FILE"

python3 -m monaifbs.fetal_brain_seg \
  --input_names "$RESAMPLED_FILE" \
  --segment_output_names "$SEGMENTED_FILE"

# Check MONAI exit status
if [ $? -eq 0 ]; then
    echo "=== MONAI Processing Complete ==="
    echo "Input file: $(basename "$RESAMPLED_FILE")"
    if [ -f "$SEGMENTED_FILE" ]; then
        echo "Output mask file: $(basename "$SEGMENTED_FILE")"
    else
        echo "Warning: Expected output file not found: $SEGMENTED_FILE"
    fi
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

