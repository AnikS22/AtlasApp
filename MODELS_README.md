# Models Directory

⚠️ **ML Model files are NOT included in this repository** (too large for GitHub).

## Download Required Model

### Option 1: Llama 3.2 1B (Recommended for Testing)

```bash
# Download from Hugging Face
https://huggingface.co/apple/Llama-3.2-1B-Instruct-coreml

# Download file:
Llama-3.2-1B-Instruct-4bit.mlpackage.zip (~650MB)

# Extract and place in:
Models/Llama3.21B2Gb/model/
```

### Option 2: Phi-3.5-mini (Better Quality)

```bash
# Download from Hugging Face
https://huggingface.co/apple/phi-3.5-mini-instruct-coreml

# Download file:
phi-3.5-mini-instruct-4bit.mlpackage.zip (~2GB)

# Extract and place in:
Models/
```

## After Downloading

1. Extract the model
2. Add to Xcode project
3. Check "Copy items if needed"
4. Select "Atlas" target
5. Build and run

See `TRM_MODEL_SETUP.md` for detailed instructions.

