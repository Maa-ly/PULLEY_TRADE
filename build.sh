#!/bin/bash

echo "Building Pulley DeFi Trading Pool System..."
echo "=========================================="

echo "1. Compiling Move contracts..."
aptos move compile --dev

if [ $? -eq 0 ]; then
    echo " Compilation successful!"
    echo ""
    echo "2. Running tests..."
    aptos move test --dev
    
    if [ $? -eq 0 ]; then
        echo " All tests passed!"
        echo ""
        echo "Pulley DeFi system is ready to deploy!"
        echo ""
        echo "Next steps:"
        echo "- Deploy contracts to testnet: aptos move publish --dev"
        echo "- Initialize the system with proper addresses"
        echo "- Set up yield vault strategies"
        echo ""
    else
        echo " Tests failed!"
        exit 1
    fi
else
    echo " Compilation failed!"
    exit 1
fi
