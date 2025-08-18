#!/bin/bash

# Path to your transform file
TRANSFORM_FILE="Untitled.txt"

# Step 1: Convert all NIfTI files to ASL orientation
for file in *.nii.gz; do
    # Skip already converted files
    if [[ "$file" == *_ASL.nii.gz ]]; then
        continue
    fi
    
    base="${file%.nii.gz}"
    asl_file="${base}_ASL.nii.gz"
    
    echo "Converting $file to ASL orientation..."
    c3d "$file" -orient ASL -o "$asl_file"
done

# Step 2: Apply rotation to each _ASL.nii.gz file
for asl_file in *_ASL.nii.gz; do
    base="${asl_file%.nii.gz}"
    output_file="${base}_reoriented.nii.gz"
    
    # Detect if this is a segmentation/mask file
    if [[ "$asl_file" == *_CP* ]] || \
       [[ "$asl_file" == *_mask* ]] || \
       [[ "$asl_file" == *_labels* ]] || \
       [[ "$asl_file" == *_pial* ]] || \
       [[ "$asl_file" == *_white* ]] || \
       [[ "$asl_file" == *_all_labels* ]] || \
       [[ "$asl_file" == *_tissue_labels* ]]; then
        interp="NearestNeighbor"
    else
        interp="Linear"
    fi
    
    echo "Applying rotation to $asl_file with interpolation: $interp"
    docker run --rm \
      -v "$(pwd)":/data \
      antsx/ants:master \
      bash -c "
        antsApplyTransforms \
          -d 3 \
          -i /data/$asl_file \
          -o /data/$output_file \
          -t /data/$TRANSFORM_FILE \
          -r /data/$asl_file \
          -n $interp
      "
done

