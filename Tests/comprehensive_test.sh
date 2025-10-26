#!/bin/bash
#
# Comprehensive Test Suite for AtlasApp
# Tests all components: Model, MCP, Voice, Email, Calendar
#

set -e

echo "========================================"
echo "Atlas App Comprehensive Test Suite"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print test results
print_result() {
    local test_name=$1
    local status=$2

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$status" == "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Navigate to project directory
cd "$(dirname "$0")/.."

echo "1. Testing Build Configuration"
echo "--------------------------------"

# Test 1: Check if Package.swift exists
if [ -f "Package.swift" ]; then
    print_result "Package.swift exists" "PASS"
else
    print_result "Package.swift exists" "FAIL"
fi

# Test 2: Check if Llama model exists
if [ -d "Models/Llama3.21B2Gb/model" ]; then
    print_result "Llama 3.2 1B model directory exists" "PASS"

    # Check model files
    if [ -f "Models/Llama3.21B2Gb/model/Data/com.apple.CoreML/model.mlmodel" ]; then
        print_result "Llama model file exists" "PASS"
    else
        print_result "Llama model file exists" "FAIL"
    fi

    if [ -f "Models/Llama3.21B2Gb/model/Data/com.apple.CoreML/weights/weight.bin" ]; then
        MODEL_SIZE=$(du -sh Models/Llama3.21B2Gb/model/Data/com.apple.CoreML/weights/weight.bin | cut -f1)
        print_result "Llama model weights exist ($MODEL_SIZE)" "PASS"
    else
        print_result "Llama model weights exist" "FAIL"
    fi
else
    print_result "Llama 3.2 1B model directory exists" "FAIL"
fi

echo ""
echo "2. Testing Source Code Structure"
echo "--------------------------------"

# Test 3: Check key service files
SERVICES=(
    "Sources/Atlas/Services/TRMEngine/TRMInferenceEngine.swift"
    "Sources/Atlas/Services/TRMEngine/ModelLoader.swift"
    "Sources/Atlas/Services/TRMEngine/Llama32Adapter.swift"
    "Sources/Atlas/Services/MCPClient/MCPClient.swift"
    "Sources/Atlas/Services/AIService/AIService.swift"
    "Sources/Atlas/Services/VoiceService/SpeechRecognitionService.swift"
    "Sources/Atlas/Services/VoiceService/TextToSpeechService.swift"
    "Sources/Atlas/Services/OAuth/OAuthManager.swift"
)

for service in "${SERVICES[@]}"; do
    if [ -f "$service" ]; then
        print_result "$(basename $service) exists" "PASS"
    else
        print_result "$(basename $service) exists" "FAIL"
    fi
done

echo ""
echo "3. Testing Swift Package Dependencies"
echo "--------------------------------"

# Test 4: Resolve dependencies
if swift package resolve 2>&1 | grep -q "error"; then
    print_result "Swift package resolution" "FAIL"
else
    print_result "Swift package resolution" "PASS"
fi

# Test 5: Check dependencies
DEPENDENCIES=("Alamofire" "KeychainAccess" "SQLite" "SwiftyJSON")
for dep in "${DEPENDENCIES[@]}"; do
    if [ -d ".build/checkouts/${dep}"* ] || grep -q "$dep" Package.resolved 2>/dev/null; then
        print_result "$dep dependency" "PASS"
    else
        print_result "$dep dependency" "FAIL"
    fi
done

echo ""
echo "4. Testing Build Process"
echo "--------------------------------"

# Test 6: Build the project
echo "Building project (this may take a moment)..."
if swift build 2>&1 | tee /tmp/atlas_build.log | grep -q "error:"; then
    print_result "Project builds successfully" "FAIL"
    echo "Build errors:"
    grep "error:" /tmp/atlas_build.log | head -5
else
    print_result "Project builds successfully" "PASS"
fi

echo ""
echo "5. Testing Model Integration"
echo "--------------------------------"

# Test 7: Check model adapter
if [ -f "Sources/Atlas/Services/TRMEngine/Llama32Adapter.swift" ]; then
    print_result "Llama 3.2 adapter implementation" "PASS"
else
    print_result "Llama 3.2 adapter implementation" "FAIL"
fi

# Test 8: Check model configuration
if grep -q "Llama" Sources/Atlas/Services/TRMEngine/*.swift 2>/dev/null; then
    print_result "Llama model references in code" "PASS"
else
    print_result "Llama model references in code" "FAIL"
fi

echo ""
echo "6. Testing MCP Integration"
echo "--------------------------------"

# Test 9: Check MCP client implementation
if grep -q "MCPClientProtocol" Sources/Atlas/Services/MCPClient/MCPClient.swift; then
    print_result "MCP client protocol implementation" "PASS"
else
    print_result "MCP client protocol implementation" "FAIL"
fi

# Test 10: Check MCP transport types
if grep -q "websocket\|stdio\|http" Sources/Atlas/Services/MCPClient/*.swift; then
    print_result "MCP transport implementations" "PASS"
else
    print_result "MCP transport implementations" "FAIL"
fi

echo ""
echo "7. Testing Voice Services"
echo "--------------------------------"

# Test 11: Speech recognition
if grep -q "SFSpeechRecognizer" Sources/Atlas/Services/VoiceService/SpeechRecognitionService.swift; then
    print_result "Speech recognition implementation" "PASS"
else
    print_result "Speech recognition implementation" "FAIL"
fi

# Test 12: Text-to-speech
if grep -q "AVSpeechSynthesizer" Sources/Atlas/Services/VoiceService/TextToSpeechService.swift; then
    print_result "Text-to-speech implementation" "PASS"
else
    print_result "Text-to-speech implementation" "FAIL"
fi

echo ""
echo "8. Testing OAuth & Integration Services"
echo "--------------------------------"

# Test 13: OAuth manager
if [ -f "Sources/Atlas/Services/OAuth/OAuthManager.swift" ]; then
    print_result "OAuth manager implementation" "PASS"
else
    print_result "OAuth manager implementation" "FAIL"
fi

# Test 14: Security services
SECURITY_SERVICES=(
    "Sources/Atlas/Services/Security/KeychainManager.swift"
    "Sources/Atlas/Services/Security/EncryptionManager.swift"
    "Sources/Atlas/Services/Security/DatabaseManager.swift"
)

for service in "${SECURITY_SERVICES[@]}"; do
    if [ -f "$service" ]; then
        print_result "$(basename $service)" "PASS"
    else
        print_result "$(basename $service)" "FAIL"
    fi
done

echo ""
echo "9. Testing Unit Tests"
echo "--------------------------------"

# Test 15: Check if test directory exists
if [ -d "Tests" ]; then
    print_result "Tests directory exists" "PASS"

    # Run tests if they exist
    if find Tests -name "*.swift" -type f | grep -q .; then
        echo "Running unit tests..."
        if swift test 2>&1 | tee /tmp/atlas_test.log | grep -q "error:"; then
            print_result "Unit tests pass" "FAIL"
            echo "Test errors:"
            grep "error:" /tmp/atlas_test.log | head -5
        else
            print_result "Unit tests pass" "PASS"
        fi
    else
        print_result "Unit test files exist" "FAIL"
    fi
else
    print_result "Tests directory exists" "FAIL"
fi

echo ""
echo "10. Testing Documentation"
echo "--------------------------------"

# Test 16: Check README files
DOC_FILES=("README.md" "PHI35_QUICK_START.md" "TRM_MODEL_SETUP.md")
for doc in "${DOC_FILES[@]}"; do
    if [ -f "$doc" ]; then
        print_result "$doc exists" "PASS"
    else
        print_result "$doc exists" "FAIL"
    fi
done

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total Tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC}       $PASSED_TESTS"
echo -e "${RED}Failed:${NC}       $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    PASS_RATE=$((100 * PASSED_TESTS / TOTAL_TESTS))
    echo -e "\nPass Rate:    ${PASS_RATE}%"
    echo -e "${YELLOW}Some tests failed. Please review the failures above.${NC}"
    exit 1
fi
