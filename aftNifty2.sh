#!/bin/bash

# Brain image processing script - Interactive Form
# Usage: ./process_brain.sh

echo "=========================================="
echo "    Brain Image Processing Tool"
echo "=========================================="
echo ""

# Get sudo password at the beginning to avoid interruption later
echo "This script requires sudo privileges for Docker operations."
echo -n "Please enter your sudo password: "
read -s SUDO_PASS
echo ""
echo ""

# Test sudo password
echo "$SUDO_PASS" | sudo -S echo "Password verified successfully" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Error: Invalid password or sudo access denied"
    exit 1
fi

# Get user inputs
echo "Please provide the following information:"
echo ""
echo -n "Enter Subject ID (e.g., FX41): "
read SUBJECT_ID

if [ -z "$SUBJECT_ID" ]; then
    echo "Error: Subject ID cannot be empty"
    exit 1
fi

echo -n "Enter Gestational Age (e.g., 28): "
read GESTATIONAL_AGE

if [ -z "$GESTATIONAL_AGE" ]; then
    echo "Error: Gestational Age cannot be empty"
    exit 1
fi

# Validate gestational age is a number
if ! [[ "$GESTATIONAL_AGE" =~ ^[0-9]+$ ]]; then
    echo "Error: Gestational Age must be a number"
    exit 1
fi

echo ""
echo "Subject ID: $SUBJECT_ID"
echo "Gestational Age: $GESTATIONAL_AGE"
echo ""
echo "=========================================="
echo "Starting brain image processing..."
echo "=========================================="

# Check if required files exist
if [ ! -f "srr.nii.gz" ]; then
    echo "Error: srr.nii.gz not found"
    exit 1
fi

# Universal brain extraction step - happens for both processing types
if [ -f "srr_mask.nii.gz" ]; then
    echo "Brain mask found - extracting brain..."
    fslmaths srr.nii.gz -mas srr_mask.nii.gz srr_extracted.nii.gz
    
    if [ $? -ne 0 ]; then
        echo "Error: Brain extraction failed"
        exit 1
    fi
    
    echo "Brain extraction completed successfully"
    BRAIN_FILE="srr_extracted.nii.gz"
else
    echo "Warning: srr_mask.nii.gz not found - proceeding without brain extraction"
    BRAIN_FILE="srr.nii.gz"
fi

# Find STA template file
STA_FILE=$(ls STA*.nii.gz 2>/dev/null | head -n 1)

if [ -z "$STA_FILE" ]; then
    echo "Error: No STA*.nii.gz template file found"
    exit 1
fi

echo "Using template: $STA_FILE"

# Registration step - uses extracted brain if available, otherwise original
echo "Registering brain to template using Docker..."
docker run --rm \
    -v "$(pwd)":/data \
    antsx/ants:master \
    antsRegistrationSyNQuick.sh \
    -d 3 \
    -f /data/"$STA_FILE" \
    -m /data/"$BRAIN_FILE" \
    -o /data/srr_

if [ $? -ne 0 ]; then
    echo "Error: Registration failed"
    exit 1
fi

echo "Registration completed successfully"

# Denoising step
echo ""
echo "Starting denoising process..."
nsol_run_denoising \
    --observation srr_Warped.nii.gz \
    --result srr_denoise.nii.gz \
    --reconstruction-type TVL1 \
    --alpha 0.05 \
    --iterations 50

if [ $? -ne 0 ]; then
    echo "Error: Denoising failed"
    exit 1
fi

echo "Denoising completed successfully"

# Deconvolution step
echo ""
echo "Starting deconvolution process..."
nsol_run_deconvolution \
    --observation srr_denoise.nii.gz \
    --result srr_deconvoluted.nii.gz \
    --reconstruction-type TK1L2 \
    --blur 0.1 \
    --alpha 0.05 \
    --iterations 50 \
    --verbose 1

if [ $? -ne 0 ]; then
    echo "Error: Deconvolution failed"
    exit 1
fi

echo "Deconvolution completed successfully"

# DHCP structural pipeline
echo ""
echo "=========================================="
echo "Starting DHCP Structural Pipeline..."
echo "Subject ID: $SUBJECT_ID"
echo "Gestational Age: $GESTATIONAL_AGE"
echo "=========================================="

echo "$SUDO_PASS" | sudo -S docker run --rm -t \
    -u $(id -u):$(id -g) \
    -v "$PWD":/data \
    biomedia/dhcp-structural-pipeline:latest \
    "$SUBJECT_ID" s3 "$GESTATIONAL_AGE" \
    -T2 /data/srr_deconvoluted.nii.gz \
    -t 8

if [ $? -ne 0 ]; then
    echo "Error: DHCP pipeline failed"
    exit 1
fi

echo ""
echo "DHCP Structural Pipeline completed successfully"

# Final output summary
echo ""
echo "=========================================="
echo "Processing completed successfully!"
echo "=========================================="
echo ""
echo "Final output files:"
if [ -f "srr_extracted.nii.gz" ]; then
    echo "  - srr_extracted.nii.gz (extracted brain)"
fi
echo "  - srr_Warped.nii.gz (registered brain)"
echo "  - srr_denoise.nii.gz (denoised brain)"
echo "  - srr_deconvoluted.nii.gz (final processed brain)"
echo ""
