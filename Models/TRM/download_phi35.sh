#!/bin/bash
# Download Phi-3.5-mini CoreML model for AtlasApp

set -e

echo "📦 Downloading Phi-3.5-mini CoreML model..."
echo "This will take a few minutes (model is ~2GB)"

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "🌐 Fetching from Hugging Face..."

# Download using git-lfs (faster for large files)
if command -v git-lfs &> /dev/null; then
    echo "✓ git-lfs found, using for download"
    git lfs install
    git clone https://huggingface.co/apple/phi-3.5-mini-coreml
    cd phi-3.5-mini-coreml
else
    echo "⚠️  git-lfs not found, using wget (slower)"
    echo "Install git-lfs with: brew install git-lfs"
    
    # Download directly
    wget https://huggingface.co/apple/phi-3.5-mini-coreml/resolve/main/phi-3.5-mini-4bit.mlpackage.zip
    unzip phi-3.5-mini-4bit.mlpackage.zip
fi

# Find the model file
MODEL_FILE=$(find . -name "*.mlpackage" -type d | head -1)

if [ -z "$MODEL_FILE" ]; then
    echo "❌ Model file not found!"
    exit 1
fi

echo "✓ Model downloaded: $MODEL_FILE"

# Copy to AtlasApp
DEST_DIR="/Users/aniksahai/Desktop/claude-flow/AtlasApp/Models/TRM"
mkdir -p "$DEST_DIR"

echo "📋 Creating model files for TRM architecture..."

# Copy as ThinkModel
cp -r "$MODEL_FILE" "$DEST_DIR/ThinkModel_4bit.mlpackage"
echo "✓ Created ThinkModel_4bit.mlpackage"

# Copy as ActModel (same model, different purpose in TRM)
cp -r "$MODEL_FILE" "$DEST_DIR/ActModel_4bit.mlpackage"
echo "✓ Created ActModel_4bit.mlpackage"

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Phi-3.5-mini models ready!"
echo ""
echo "📝 Next steps:"
echo "1. Open AtlasApp in Xcode"
echo "2. Drag Models/TRM/*.mlpackage into the project"
echo "3. Check 'Copy items if needed'"
echo "4. Add to Atlas target"
echo "5. Build and run!"
echo ""
echo "Model location: $DEST_DIR"

