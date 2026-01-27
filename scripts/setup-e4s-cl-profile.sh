#!/bin/bash
# Auto-execute e4s-cl profile commands for Chapel/Arkouda dependencies
# This script runs the generate-e4s-cl-profile.sh and executes all valid commands

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR_SCRIPT="$SCRIPT_DIR/generate-e4s-cl-profile.sh"

if [ ! -x "$GENERATOR_SCRIPT" ]; then
    echo "Error: Generator script not found or not executable: $GENERATOR_SCRIPT"
    exit 1
fi

echo "=== Generating and executing e4s-cl profile commands for Chapel/Arkouda ==="
echo ""

# Check if e4s-cl is available
if ! command -v e4s-cl &> /dev/null; then
    echo "Warning: e4s-cl command not found. Please ensure E4S-CL is installed and available in PATH."
    exit 1
fi

# Check if an e4s-cl profile exists
if ! e4s-cl profile show &> /dev/null; then
    echo "Warning: No e4s-cl profile found or e4s-cl profile is not properly configured."
    echo "Please create and configure an e4s-cl profile first using:"
    echo "  e4s-cl profile create <profile-name>"
    echo "  e4s-cl profile activate <profile-name>"
    exit 1
fi

# Generate commands and filter only the executable ones
COMMANDS=$($GENERATOR_SCRIPT | grep '^e4s-cl profile edit')

if [ -z "$COMMANDS" ]; then
    echo "No valid e4s-cl profile edit commands were generated."
    echo "This could mean:"
    echo "  - Required Chapel/Arkouda libraries are not available in the expected locations"
    echo "  - The generator script failed to find compatible library installations"
    echo "  - Libraries are installed but not in standard paths"
    echo ""
    echo "Please check:"
    echo "  1. Chapel installation and CHPL_HOME environment variable"
    echo "  2. Arkouda installation and dependencies"
    echo "  3. Library paths in the generator script"
    exit 1
fi

echo "Found $(echo "$COMMANDS" | wc -l) library/directory entries to add."
echo ""

# Ask for confirmation unless --auto flag is provided
if [ "$1" != "--auto" ]; then
    echo "Commands to execute:"
    echo "$COMMANDS"
    echo ""
    read -p "Execute these commands? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "Executing e4s-cl profile commands..."
echo ""

# Execute each command with error handling
SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS= read -r cmd; do
    echo "Running: $cmd"
    if eval "$cmd"; then
        echo "  [OK] Success"
        ((SUCCESS_COUNT++))
    else
        echo "  [FAIL] Failed (exit code: $?)"
        ((FAIL_COUNT++))
    fi
    echo ""
done <<< "$COMMANDS"

echo "=== Summary ==="
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "All libraries successfully added to e4s-cl profile!"
    echo "Verify with: e4s-cl profile show"
else
    echo "Some commands failed. Check the output above for details."
    exit 1
fi