#!/usr/bin/env bash
set -e

if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then
  echo "Manual trigger (workflow_dispatch). Forcing build."
  echo "skip=false" >> "$GITHUB_OUTPUT"
elif gh release view "$LATEST_VERSION" >/dev/null 2>&1; then
  echo "Version $LATEST_VERSION is already released."
  echo "skip=true" >> "$GITHUB_OUTPUT"
else
  echo "New version detected. Proceeding to patch and release."
  echo "skip=false" >> "$GITHUB_OUTPUT"
fi
