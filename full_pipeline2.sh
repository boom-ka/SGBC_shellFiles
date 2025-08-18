#!/bin/bash

# Get current directory (where the original files are)
CURRENT_DIR=$(pwd)

# Array of input files and their corresponding output files (sag first as requested)
declare -a input_files=("sag.nii.gz" "cor.nii.gz" "ax.nii.gz")
declare -a output_files=("resam_sag.nii.gz" "resam_cor.nii.gz" "resam_ax.nii.gz")

echo "=== Medical Image Processing Pipeline ==="
echo ""
echo "Select processing method:"
echo "1) MONAI (monaifbs.fetal_brain_seg)"
echo "2) FSL (bet with skull stripping)"
echo ""
read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        processing_method="MONAI"
        ;;
    2)
        processing_method="FSL"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Selected processing method: $processing_method"
echo ""
echo "=== Starting Slicer Resampling ==="

# Arrays to store successfully processed files
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
        
        # Determine corresponding output name based on processing method
        if [ "$processing_method" == "MONAI" ]; then
            seg_file="seg_${input_file%.*.*}.nii.gz"
        else
            # FSL outputs: brain extracted file and mask
            seg_file="bet_${input_file%.*.*}.nii.gz"
        fi
        processed_seg_files+=("${CURRENT_DIR}/$seg_file")
    else
        echo "✗ Failed to process $input_file"
    fi
done

echo "=== Slicer Resampling Complete ==="
echo "Successfully processed ${#processed_resam_files[@]} files"

# Only proceed with secondary processing if we have at least one processed file
if [ ${#processed_resam_files[@]} -eq 0 ]; then
    echo "ERROR: No files were successfully processed. Exiting."
    exit 1
fi

echo ""
echo "=== Starting $processing_method Processing ==="
echo "Processing ${#processed_resam_files[@]} resampled files..."

if [ "$processing_method" == "MONAI" ]; then
    # MONAI Processing
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
        processing_success=true
    else
        echo "ERROR: MONAI processing failed"
        processing_success=false
    fi

    # Deactivate environment
    deactivate
    cd "$CURRENT_DIR"

else
    # FSL Processing
    processing_success=true
    for i in "${!processed_resam_files[@]}"; do
        input_file="${processed_resam_files[$i]}"
        output_file="${processed_seg_files[$i]}"
        
        # Extract just the filename without path and extension for FSL
        input_basename=$(basename "$input_file" .nii.gz)
        output_basename=$(basename "$output_file" .nii.gz)
        
        echo "Running FSL bet on $(basename "$input_file")"
        
        # Run FSL bet command with just the basename (FSL adds .nii.gz automatically)
        bet "$input_basename" "$output_basename" -m -f 0.5 -g 0
        
        # Check if FSL processing was successful
        if [ $? -eq 0 ] && [ -f "${output_basename}.nii.gz" ]; then
            echo "✓ Successfully processed $(basename "$input_file") with FSL"
        else
            echo "✗ Failed to process $(basename "$input_file") with FSL"
            processing_success=false
        fi
    done
    
    if [ "$processing_success" == true ]; then
        echo "=== FSL Processing Complete ==="
    else
        echo "ERROR: Some FSL processing failed"
    fi
fi

echo ""
echo "=== Pipeline Complete ==="
echo "Processed ${#processed_resam_files[@]} out of ${#input_files[@]} input files using $processing_method"
