#!/bin/bash

set -e

echo "-- Generating changelog for release..."

echo "-- Cloning Eden repository..."
# Clean up any existing folder to prevent conflicts
rm -rf ./eden
git clone 'https://git.eden-emu.dev/eden-emu/eden.git' ./eden
cd ./eden
echo "   Done."

BASE_DOWNLOAD_URL="https://github.com/Ati1707/eden-nightly/releases/download"
CHANGELOG_FILE=~/changelog
SOURCE_NAME_BASE="Eden-Source-Code"

# ==========================================
# MODE 1: CUSTOM PR BUILD (Single or Multiple)
# ==========================================
if [ -n "$PR_ID" ]; then
  echo "--- DETECTED PR BUILD: $PR_ID ---"
  
  # Configure git to allow merging
  git config user.email "bot@github-actions"
  git config user.name "GitHub Actions"

  # Clean input: remove spaces (e.g. "42, 45" -> "42,45")
  CLEAN_IDS=$(echo "$PR_ID" | tr -d ' ')
  
  # Initialize Changelog Header
  echo "> [!CAUTION]" > "$CHANGELOG_FILE"
  echo "> **This is a TEST BUILD merging the following Pull Requests:**" >> "$CHANGELOG_FILE"
  
  # Split IDs by comma into an array
  IFS=',' read -ra PR_ARRAY <<< "$CLEAN_IDS"
  
  # Determine Tag Prefix
  if [ "${#PR_ARRAY[@]}" -eq 1 ]; then
     TAG_PREFIX="PR-${PR_ARRAY[0]}"
  else
     TAG_PREFIX="PR-Multi"
  fi

  # --- LOOP: Fetch and Merge all requested PRs ---
  for id in "${PR_ARRAY[@]}"; do
      echo "   Processing PR #$id..."
      
      # Fetch the specific PR head to a temporary branch 'pr-{id}'
      git fetch origin "refs/pull/$id/head:pr-$id"
      
      # Merge into current branch
      git merge "pr-$id" --no-edit
      
      # Add summary line to changelog
      PR_TITLE=$(git log -1 --pretty=format:"%s")
      echo "> * **PR #$id**: $PR_TITLE" >> "$CHANGELOG_FILE"
  done
  
  echo ">" >> "$CHANGELOG_FILE"
  echo "> It may be unstable. Do not report bugs unless you are the PR author." >> "$CHANGELOG_FILE"
  echo "" >> "$CHANGELOG_FILE"

  # Generate Release Info
  COUNT="$(git rev-list --count HEAD)"
  DATE="$(date +"%Y-%m-%d")"
  TAG="${TAG_PREFIX}-${DATE}-${COUNT}"
  SOURCE_NAME="${SOURCE_NAME_BASE}-${COUNT}"

  # Save Tag and Count for the workflow to use
  echo "$TAG" > ~/tag
  echo "$COUNT" > ~/count
  echo "   Release tag: $TAG"
  echo "   Commit count: $COUNT"

  # Append Technical Commit Details to Changelog
  echo "## Merged Commit Details" >> "$CHANGELOG_FILE"
  for id in "${PR_ARRAY[@]}"; do
      echo "### PR #$id Details" >> "$CHANGELOG_FILE"
      git log -1 --pretty=format:"%B" "pr-$id" >> "$CHANGELOG_FILE"
      echo -e "\n" >> "$CHANGELOG_FILE"
  done

  # Generate Download Table (Using the new TAG)
  echo "## Test Release Downloads:" >> "$CHANGELOG_FILE"
  echo "| Platform | Normal builds | PGO optimized builds |" >> "$CHANGELOG_FILE"
  echo "|--|--|--|" >> "$CHANGELOG_FILE"
  echo "| Windows (MSVC) | **7z**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-msvc-x86_64.7z)<br><br>\
**Installer**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-msvc-x86_64-Installer.exe) |" >> "$CHANGELOG_FILE"
  echo "| Windows (CLANG) | **7z**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-clang-x86_64.7z)<br><br>\
**Installer**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-clang-x86_64-Installer.exe) |" >> "$CHANGELOG_FILE"
  
  echo "-- PR Changelog generated."
  cat "$CHANGELOG_FILE"
  
  # === PACK SOURCE CODE FOR PR BUILD ===
  echo "-- Fetching source code for release..."
  git fetch --all
  chmod a+x tools/cpm-fetch-all.sh
  tools/cpm-fetch-all.sh

  cd ..
  mkdir -p artifacts
  mkdir "$SOURCE_NAME"
  cp -a eden "$SOURCE_NAME"
  echo "-- Creating 7z archive: $SOURCE_NAME.7z"
  7z a -t7z -mx=9 "$SOURCE_NAME.7z" "$SOURCE_NAME"
  mv -v "$SOURCE_NAME.7z" artifacts/
  
  echo "=== PR BUILD PREP DONE! ==="
  
  exit 0
fi

# ==========================================
# MODE 2: STANDARD NIGHTLY BUILD
# ==========================================

# Get current commit info
echo "-- Setup release information..."
COUNT="$(git rev-list --count HEAD)"
DATE="$(date +"%Y-%m-%d")"
TAG="${DATE}-${COUNT}"
SOURCE_NAME="Eden-${COUNT}-Source-Code"
echo "$TAG" > ~/tag
echo "$COUNT" > ~/count
echo "   Release tag: $TAG"
echo "   Commit count: $COUNT"

BASE_COMMIT_URL="https://git.eden-emu.dev/eden-emu/eden/commit"
BASE_COMPARE_URL="https://git.eden-emu.dev/eden-emu/eden/compare"

# Fallback if OLD_COUNT is empty or null
echo "-- Checking previous release count..."
if [ -z "$OLD_COUNT" ] || [ "$OLD_COUNT" = "null" ]; then
  echo "   OLD_COUNT is empty, falling back to current COUNT (&COUNT)"
  OLD_COUNT="$COUNT"
else
  echo "   Previous release count found: $OLD_COUNT"
fi
OLD_HASH=$(git rev-list --reverse HEAD | sed -n "${OLD_COUNT}p")
i=$((OLD_COUNT + 1))

# Add reminder and Release Overview link
echo "-- Generating changelog file..."
echo ">[!WARNING]" > "$CHANGELOG_FILE"
echo "**This repository is not affiliated with the official Eden development team. It exists solely to provide an easy way for users to try out the latest features from recent commits.**" >> "$CHANGELOG_FILE"
echo "**These builds are experimental and may be unstable. Use them at your own risk, and please do not report issues from these builds to the official channels unless confirmed on official releases.**" >> "$CHANGELOG_FILE"
echo >> "$CHANGELOG_FILE"
echo "> [!IMPORTANT]" >> "$CHANGELOG_FILE"
echo "> See the **[Release Overview](https://github.com/Ati1707/eden-nightly?tab=readme-ov-file#release-overview)** section for detailed differences between builds." >> "$CHANGELOG_FILE"
echo ">" >> "$CHANGELOG_FILE"
echo  -e "> **PGO-optimized** builds are now available, can offer up to **5–10%** higher FPS in theory depending on games.\n>**But note that they are now extremely experimental with unstable performance boost across different builds even with the same game.**" >> "$CHANGELOG_FILE"
echo >> "$CHANGELOG_FILE"
echo "   - Added reminder and Release Overview link."

# Add changelog section
echo "## Changelog:" >> "$CHANGELOG_FILE"
git log --reverse --pretty=format:"%H%x09%s%x09%an" "${OLD_HASH}..HEAD" |
while IFS=$'\t' read -r full_hash msg author || [ -n "$full_hash" ]; do
  short_hash="$(git rev-parse --short "$full_hash")"
  echo -e "- Merged commit: \`${i}\` [\`${short_hash}\`](${BASE_COMMIT_URL}/${full_hash}) by **${author}**\n  ${msg}" >> "$CHANGELOG_FILE"
  echo >> "$CHANGELOG_FILE"
  i=$((i + 1))
done

# Add full changelog from lastest official tag release
echo "Full Changelog: [\`v0.0.3...master\`](${BASE_COMPARE_URL}/v0.0.3...master)" >> "$CHANGELOG_FILE"
echo >> "$CHANGELOG_FILE"
echo "   - Added changelog section."

# Generate release table
echo "## Release table:" >> "$CHANGELOG_FILE"
echo "| Platform | Normal builds | PGO optimized builds |" >> "$CHANGELOG_FILE"
echo "|--|--|--|" >> "$CHANGELOG_FILE"
echo "| Windows (MSVC) | **7z**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-msvc-x86_64.7z)<br><br>\
**Installer**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-msvc-x86_64-Installer.exe) |" >> "$CHANGELOG_FILE"
echo "| Windows (CLANG) | **7z**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-clang-x86_64.7z)<br><br>\
**Installer**<br>────────────────<br>\
[\`x86_64\`](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Windows-clang-x86_64-Installer.exe) |" >> "$CHANGELOG_FILE"
echo "| Source Code | [Source](${BASE_DOWNLOAD_URL}/${TAG}/Eden-${COUNT}-Source-Code.7z) | |" >> "$CHANGELOG_FILE"
echo "   - Added release table."

echo "-- Full changelog generated:"
cat "$CHANGELOG_FILE"


# Fetch all repo history and cpm pakages
echo "-- Fetching source code for release..."
git fetch --all
chmod a+x tools/cpm-fetch-all.sh
tools/cpm-fetch-all.sh

# Pack up source for upload
cd ..
mkdir -p artifacts
mkdir "$SOURCE_NAME"
cp -a eden "$SOURCE_NAME"
echo "-- Creating 7z archive: $SOURCE_NAME.7z"
7z a -t7z -mx=9 "$SOURCE_NAME.7z" "$SOURCE_NAME"
mv -v "$SOURCE_NAME.7z" artifacts/

echo "=== ALL DONE! ==="
