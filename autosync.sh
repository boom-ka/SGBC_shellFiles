#!/bin/bash
cd /home/htic/VedantSingh/cmdF  # ⬅ replace with your actual path
git add .
git commit -m "Auto-sync $(date +"%Y-%m-%d %H:%M:%S")"
git push origin main
