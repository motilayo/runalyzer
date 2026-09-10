#!/bin/sh
# Xcode Cloud Post-Clone Script
# This script runs automatically in Xcode Cloud after repository checkout.

set -e

echo "==> Xcode Cloud: Checking environment..."

# Install or run linters if desired in Xcode Cloud
# brew install swiftlint
# swiftlint lint --config ../.swiftlint.yml

echo "==> Xcode Cloud: Post-clone setup complete."
