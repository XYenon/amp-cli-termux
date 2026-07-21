#!/usr/bin/env bash
set -e

if [ -z "$LATEST_VERSION" ]; then
  echo "Error: LATEST_VERSION environment variable is not set."
  exit 1
fi

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add cli/cli-version.txt

if git diff --quiet && git diff --staged --quiet; then
  echo "No changes to version file."
else
  git commit -m "Update version file to ${LATEST_VERSION}"
  git push
fi

# Record the commit the release tag should point to (the version-file commit)
echo "VERSION_COMMIT=$(git rev-parse HEAD)" >> "$GITHUB_ENV"
