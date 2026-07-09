#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MMD_FILE="$PROJECT_DIR/docs/seqinspector.mmd"
OUTPUT_DIR="$PROJECT_DIR/docs/images"

# Render dark theme
nf-metro render "$MMD_FILE" --theme nfcore -o "$OUTPUT_DIR/seqinspector_tubemap_dark.svg"
inkscape --export-filename="$OUTPUT_DIR/seqinspector_tubemap_dark.png" "$OUTPUT_DIR/seqinspector_tubemap_dark.svg"

# Render light theme with light logo
nf-metro render "$MMD_FILE" --theme light --no-chrome-css \
    --logo "$OUTPUT_DIR/nf-core-seqinspector_logo_light.png" \
    -o /tmp/seqinspector_light.svg

# Fix legend background color for light theme
sed -s 's|fill="rgba(255, 255, 255, 0.8)"|fill="#ededed"|g; s|fill-opacity:0.8|fill-opacity:1|g' \
    /tmp/seqinspector_light.svg > "$OUTPUT_DIR/seqinspector_tubemap_light.svg"

# Convert light SVG to PNG
inkscape --export-filename="$OUTPUT_DIR/seqinspector_tubemap_light.png" "$OUTPUT_DIR/seqinspector_tubemap_light.svg"

echo "Done. Generated:"
ls -lh "$OUTPUT_DIR"/seqinspector_tubemap_*
