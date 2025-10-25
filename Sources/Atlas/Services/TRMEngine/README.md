# TRM Inference Engine

Samsung's Tiny Recursive Models (TRM) implementation for iOS.

## Overview
- **Model size**: 7M parameters → ~2MB quantized
- **Performance**: 30+ tokens/sec on iPhone Neural Engine
- **Architecture**: 2-layer recursive transformer with think-act cycles
- **Iterations**: 16 fixed steps (for Core ML compatibility)

## Components
- `TRMInferenceEngine.swift` - Main inference engine
- Core ML models: TRMThink, TRMAct, TRMHalt

## Usage
```swift
let engine = TRMInferenceEngine()
try await engine.loadModels()

let result = try await engine.generate(
    prompt: "What is 2+2?",
    maxTokens: 100,
    streaming: true
) { token in
    print(token, terminator: "")
}
```
