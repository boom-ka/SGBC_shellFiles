#!/bin/bash
# Script to merge all segmentations except one label
# Usage: ./make_brainmask.sh input_file.nii.gz label_number

# Check arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_file.nii.gz> <label_to_remove>"
    exit 1
fi

INPUT=$1
REMOVE_LABEL=$2

# Step 1: Make all labels = 1
fslmaths "$INPUT" -thr 1 -bin temp_all       

# Step 2: Extract label to remove
fslmaths "$INPUT" -thr "$REMOVE_LABEL" -uthr "$REMOVE_LABEL" -bin temp_remove 

# Step 3: Subtract unwanted label from all labels
fslmaths temp_all -sub temp_remove brain_mask.nii.gz 

# Step 4: Clean up temporary files
rm temp_all.nii.gz temp_remove.nii.gz 

echo "✅ Brain mask created: brain_mask.nii.gz (removed label $REMOVE_LABEL)"
