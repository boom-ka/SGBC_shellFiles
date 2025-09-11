#!/bin/bash
set -e

# ============================
# Ask for sudo password at start
# ============================
sudo -v

# Step 1: Denoising
nsol_run_denoising \
  --observation "$(pwd)/srr.nii.gz" \
  --result "$(pwd)/srr_denoise.nii.gz" \
  --reconstruction-type TVL1 \
  --alpha 0.05 \
  --iterations 50

# Step 2: Deconvolution
nsol_run_deconvolution \
  --observation "$(pwd)/srr_denoise.nii.gz" \
  --result "$(pwd)/srr_deconvoluted.nii.gz" \
  --reconstruction-type TK1L2 \
  --blur 0.1 \
  --alpha 0.05 \
  --iterations 50 \
  --verbose 1

# Step 3: Run docker pipeline
sudo docker run --rm -t \
  -u $(id -u):$(id -g) \
  -v $PWD:/data \
  biomedia/dhcp-structural-pipeline:latest FX51 s1 27 \
  -T2 /data/srr_deconvoluted.nii.gz -t 8
