#!/bin/bash
# Model Download Script for AtlasApp
# Downloads Phi-3.5-mini CoreML model and prepares it for the app

set -e  # Exit on error

echo "🤖 AtlasApp Model Download Script"
echo "=================================="
echo ""

# Configuration
MODEL_DIR="$(pwd)/Models"
DOWNLOAD_DIR="$(pwd)/ModelDownloads"

# Create directories
echo "📁 Creating directories..."
mkdir -p "$MODEL_DIR"
mkdir -p "$DOWNLOAD_DIR"

cd "$DOWNLOAD_DIR"

echo ""
echo "📥 Downloading Phi-3.5-mini CoreML model..."
echo ""
echo "⚠️  MANUAL STEP REQUIRED:"
echo ""
echo "1. Open this URL in your browser:"
echo "   https://huggingface.co/apple/phi-3.5-mini-instruct-coreml"
echo ""
echo "2. Click 'Files and versions' tab"
echo ""
echo "3. Download: phi-3.5-mini-instruct-4bit.mlpackage.zip"
echo "   (About 2GB - will take a few minutes)"
echo ""
echo "4. Save to: $DOWNLOAD_DIR"
echo ""
echo "5. Press ENTER when download is complete..."
read -r

# Check if file exists
if [ ! -f "phi-3.5-mini-instruct-4bit.mlpackage.zip" ]; then
    echo "❌ Error: Model file not found!"
    echo "   Expected: $DOWNLOAD_DIR/phi-3.5-mini-instruct-4bit.mlpackage.zip"
    echo ""
    echo "Please download the file and try again."
    exit 1
fi

echo ""
echo "📦 Extracting model..."
unzip -q phi-3.5-mini-instruct-4bit.mlpackage.zip

# Check if extraction succeeded
if [ ! -d "phi-3.5-mini-instruct-4bit.mlpackage" ]; then
    echo "❌ Error: Extraction failed!"
    exit 1
fi

echo "✅ Model extracted successfully"
echo ""
echo "🔧 Preparing models for AtlasApp..."

# Copy to Models directory with correct names
cp -r phi-3.5-mini-instruct-4bit.mlpackage "$MODEL_DIR/ThinkModel_4bit.mlpackage"
cp -r phi-3.5-mini-instruct-4bit.mlpackage "$MODEL_DIR/ActModel_4bit.mlpackage"

echo "✅ Models prepared:"
echo "   - ThinkModel_4bit.mlpackage"
echo "   - ActModel_4bit.mlpackage"
echo ""
echo "📊 Model size:"
du -sh "$MODEL_DIR"/*.mlpackage
echo ""
echo "✅ DOWNLOAD COMPLETE!"
echo ""
echo "📱 NEXT STEPS:"
echo ""
echo "1. Open Xcode:"
echo "   open Package.swift"
echo ""
echo "2. In Xcode, add the models:"
echo "   - Right-click on 'Sources/Atlas' folder"
echo "   - Select 'Add Files to Atlas'"
echo "   - Navigate to: $MODEL_DIR"
echo "   - Select both .mlpackage files"
echo "   - ✅ Check 'Copy items if needed'"
echo "   - ✅ Select 'Atlas' target"
echo "   - Click 'Add'"
echo ""
echo "3. Clean and build:"
echo "   - Product → Clean Build Folder (⌘+Shift+K)"
echo "   - Product → Build (⌘+B)"
echo ""
echo "4. Run the app:"
echo "   - Product → Run (⌘+R)"
echo ""
echo "🎉 Your app will now use real AI!"
echo ""

