#!/bin/bash

# Combined script to:
# 1. Reset NIfTI image origin to 0,0,0 using c3d
# 2. Apply ANTs transforms using Docker
# Uses pwd to work in current directory

# Get current directory
CURRENT_DIR=$(pwd)

# Default file names
INPUT_FILE="srr.nii.gz"
ORIGIN_FILE="srr_origin.nii.gz"
REORIENTED_FILE="srr_reoriented.nii.gz"
DENOISE_FILE="srr_denoise.nii.gz"
DECONV_FILE="srr_deconvoluted.nii.gz"
TRANSFORM_FILE="Untitled.txt"

# Default session (not required as input)
SESSION="s1"

# Initialize required variables (will be prompted)
SUBJECT_ID=""
GESTATIONAL_AGE=""

# ===== Check for sudo access upfront =====
echo "This script requires sudo access for the dHCP pipeline."
echo "Please enter your password now to avoid interruption during processing:"
sudo -v

# Keep sudo session alive by updating the timestamp every 5 minutes
while true; do
    sudo -n true
    sleep 300
    kill -0 "$$" || exit
done 2>/dev/null &

# ===== Parse command line options =====
while getopts "s:f:t:h" opt; do
  case ${opt} in
    s ) SESSION="$OPTARG" ;;
    f ) INPUT_FILE="$OPTARG" ;;
    t ) TRANSFORM_FILE="$OPTARG" ;;
    h ) echo "Usage: $0 [-s session] [-f input_file] [-t transform_file]"
        echo "  -s: Session ID (default: s1)"
        echo "  -f: Input NIfTI file (default: srr.nii.gz)"
        echo "  -t: Transform file (default: Untitled.txt)"
        echo "  -h: Show this help message"
        echo ""
        echo "Note: Subject ID and Gestational Age will be prompted during execution"
        exit 0 ;;
    \? ) echo "Usage: $0 [-s session] [-f input_file] [-t transform_file] [-h]"
         echo "Use -h for detailed help"
         exit 1 ;;
  esac
done

# ===== Prompt for required parameters =====
echo "=== Required Parameters ==="
echo

# Prompt for Subject ID
while [[ -z "$SUBJECT_ID" ]]; do
    read -p "Enter Subject ID: " SUBJECT_ID
    if [[ -z "$SUBJECT_ID" ]]; then
        echo "Error: Subject ID cannot be empty. Please try again."
    fi
done

# Prompt for Gestational Age with validation
while [[ -z "$GESTATIONAL_AGE" ]] || ! [[ "$GESTATIONAL_AGE" =~ ^[0-9]+$ ]] || [[ "$GESTATIONAL_AGE" -lt 20 ]] || [[ "$GESTATIONAL_AGE" -gt 45 ]]; do
    read -p "Enter Gestational Age (weeks, typically 20-45): " GESTATIONAL_AGE
    if [[ -z "$GESTATIONAL_AGE" ]]; then
        echo "Error: Gestational age cannot be empty. Please try again."
    elif ! [[ "$GESTATIONAL_AGE" =~ ^[0-9]+$ ]]; then
        echo "Error: Gestational age must be a number. Please try again."
    elif [[ "$GESTATIONAL_AGE" -lt 20 ]] || [[ "$GESTATIONAL_AGE" -gt 45 ]]; then
        echo "Error: Gestational age should be between 20-45 weeks. Please try again."
    fi
done

echo
echo "=== Combined C3D + ANTs + NSOL + dHCP Processing ==="
echo "Current directory: $CURRENT_DIR"
echo "Session: $SESSION"
echo "Gestational age: $GESTATIONAL_AGE weeks"
echo "Input file: $INPUT_FILE"
echo "Transform file: $TRANSFORM_FILE"
echo "Subject ID: $SUBJECT_ID"
echo "Final deconvolution output: $DECONV_FILE"
echo

# ===== STEP 1: C3D ORIGIN RESET =====
echo "Step 1: Resetting origin with c3d..."

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

if ! command -v c3d &> /dev/null; then
    echo "Error: c3d command not found! Please install Convert3D."
    exit 1
fi

echo "Processing: $INPUT_FILE -> $ORIGIN_FILE"
c3d "$INPUT_FILE" -origin 0x0x0mm -o "$ORIGIN_FILE"

if [ $? -eq 0 ]; then
    echo "✓ Success: Origin reset completed!"
    echo "  Created: $ORIGIN_FILE"
else
    echo "✗ Error: c3d command failed!"
    exit 1
fi

echo

# ===== STEP 2: ANTS TRANSFORM =====
echo "Step 2: Applying ANTs transform with Docker..."

if [ ! -f "$TRANSFORM_FILE" ]; then
    echo "Error: Transform file '$TRANSFORM_FILE' not found!"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Error: Docker command not found! Please install Docker."
    exit 1
fi

echo "Running ANTs transform..."
echo "Input: $ORIGIN_FILE"
echo "Output: $REORIENTED_FILE"
echo "Transform: $TRANSFORM_FILE"
echo "Reference: $ORIGIN_FILE"

docker run --rm \
  -v "$CURRENT_DIR":/data \
  antsx/ants:master \
  antsApplyTransforms \
    -d 3 \
    -i /data/"$ORIGIN_FILE" \
    -o /data/"$REORIENTED_FILE" \
    -t /data/"$TRANSFORM_FILE" \
    -r /data/"$ORIGIN_FILE" \
    -n Linear

if [ $? -eq 0 ]; then
    echo "✓ Success: ANTs transform applied successfully!"
    echo "  Created: $REORIENTED_FILE"
else
    echo "✗ Error: ANTs transform failed!"
    exit 1
fi

echo

# ===== STEP 3: NSOL DENOISING =====
echo "Step 3: NSOL denoising..."

if ! command -v nsol_run_denoising &> /dev/null; then
    echo "Error: nsol_run_denoising command not found! Please install NSOL."
    exit 1
fi

echo "Running denoising..."
echo "Input: $REORIENTED_FILE"
echo "Output: $DENOISE_FILE"

nsol_run_denoising \
  --observation "$CURRENT_DIR/$REORIENTED_FILE" \
  --result "$CURRENT_DIR/$DENOISE_FILE" \
  --reconstruction-type TVL1 \
  --alpha 0.05 \
  --iterations 50

if [ $? -eq 0 ]; then
    echo "✓ Success: Denoising completed!"
    echo "  Created: $DENOISE_FILE"
else
    echo "✗ Error: NSOL denoising failed!"
    exit 1
fi

echo

# ===== STEP 4: NSOL DECONVOLUTION =====
echo "Step 4: NSOL deconvolution..."

if ! command -v nsol_run_deconvolution &> /dev/null; then
    echo "Error: nsol_run_deconvolution command not found! Please install NSOL."
    exit 1
fi

echo "Running deconvolution..."
echo "Input: $DENOISE_FILE"
echo "Output: $DECONV_FILE"

nsol_run_deconvolution \
  --observation "$CURRENT_DIR/$DENOISE_FILE" \
  --result "$CURRENT_DIR/$DECONV_FILE" \
  --reconstruction-type TK1L2 \
  --blur 0.1 \
  --alpha 0.05 \
  --iterations 50 \
  --verbose 1

if [ $? -eq 0 ]; then
    echo "✓ Success: Deconvolution completed!"
    echo "  Created: $DECONV_FILE"
else
    echo "✗ Error: NSOL deconvolution failed!"
    exit 1
fi

echo

# ===== STEP 5: dHCP STRUCTURAL PIPELINE =====
echo "Step 5: dHCP structural pipeline..."

echo "Running dHCP structural pipeline..."
echo "Subject ID: $SUBJECT_ID"
echo "Session: $SESSION"
echo "Gestational age: $GESTATIONAL_AGE weeks"
echo "T2 input: $DECONV_FILE"
echo "Threads: 8"

sudo docker run --rm -t \
  -u $(id -u):$(id -g) \
  -v "$CURRENT_DIR":/data \
  biomedia/dhcp-structural-pipeline:latest \
  "$SUBJECT_ID" "$SESSION" "$GESTATIONAL_AGE" \
  -T2 /data/"$DECONV_FILE" \
  -t 8

if [ $? -eq 0 ]; then
    echo "✓ Success: dHCP structural pipeline completed!"
    echo "  Results should be in subdirectories created by dHCP pipeline"
else
    echo "✗ Error: dHCP structural pipeline failed!"
    exit 1
fi

echo
echo "=== Processing Complete ==="
echo "Complete 5-Step Pipeline:"
echo "  1. $INPUT_FILE -> $ORIGIN_FILE (origin reset)"
echo "  2. $ORIGIN_FILE -> $REORIENTED_FILE (ANTs transform)"
echo "  3. $REORIENTED_FILE -> $DENOISE_FILE (NSOL denoising)"
echo "  4. $DENOISE_FILE -> $DECONV_FILE (NSOL deconvolution)"
echo "  5. $DECONV_FILE -> dHCP pipeline (structural processing)"
echo
echo "Intermediate files preserved:"
echo "  - $ORIGIN_FILE"
echo "  - $REORIENTED_FILE" 
echo "  - $DENOISE_FILE"
echo "  - $DECONV_FILE"
echo
echo "dHCP Pipeline Parameters:"
echo "  - Subject ID: $SUBJECT_ID"
echo "  - Session: $SESSION"
echo "  - Gestational Age: $GESTATIONAL_AGE weeks"
echo "  - T2 Input: $DECONV_FILE"
echo "  - Threads: 8"
echo
echo "Final results: Check dHCP output directories for processed structural data"
