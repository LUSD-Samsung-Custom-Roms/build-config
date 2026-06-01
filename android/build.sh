#!/bin/bash
set -eo pipefail
echo "--- Setup"
rm /tmp/android-*.log || true
unset CCACHE_EXEC
export PYTHONDONTWRITEBYTECODE=true
export BUILD_ENFORCE_SELINUX=1
export BUILD_NO=
unset BUILD_NUMBER

#TODO(zif): convert this to a runtime check, grep "sse4_2.*popcnt" /proc/cpuinfo
export CPU_SSE42=false
# Following env is set from build
# VERSION
# DEVICE
# TYPE
# RELEASE_TYPE
# EXP_PICK_CHANGES

if [ -z "$BUILD_UUID" ]; then
  echo "BUILD_UUID environment variable required"
  exit 1
fi

if [ -z "$REPO_VERSION" ]; then
  export REPO_VERSION=v2.50.1
fi

if [ -z "$TYPE" ]; then
  export TYPE=userdebug
fi

if [ -z "$RELEASE_TYPE" ]; then
  echo "RELEASE_TYPE environment variable required"
  exit 1
fi

OFFSET="10000000"
export BUILD_NUMBER=$(($OFFSET + $BUILDKITE_BUILD_NUMBER))

export KERNEL_REPO_PROJECT_OBJECTS_DIR=/lineage/${VERSION}/.repo/project-objects-kernel
export KERNEL_REPO_PROJECTS_DIR=/lineage/${VERSION}/.repo/projects-kernel

echo "--- Syncing"

mkdir -p /lineage/${VERSION}/.repo/local_manifests
cd /lineage/${VERSION}
rm -rf .repo/local_manifests/*
rm -rf vendor || true
if [ -f /lineage/setup.sh ]; then
    source /lineage/setup.sh
fi
# catch SIGPIPE from yes
yes | repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 -g default,-darwin,-muppets --git-lfs --no-clone-bundle || if [[ $? -eq 141 ]]; then true; else false; fi
repo version

echo "Syncing"
repo forall -c "git reset --hard && git clean -fdx" || true
(
  repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j4 ||
  repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j4 ||
  repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j4
) > /tmp/android-sync.log 2>&1
repo forall -vpc "if [ -f .gitattributes ]; then git lfs pull; fi" >> /tmp/android-sync.log 2>&1
. build/envsetup.sh


echo "--- clobber"
rm -rf out*

echo "--- breakfast"
breakfast ${DEVICE} ${TYPE}

if [[ "$TARGET_PRODUCT" != lineage_* ]]; then
    echo "Breakfast failed, exiting"
    exit 1
fi

if [ "$RELEASE_TYPE" '==' "experimental" ]; then
  if [ ! -z "$EXP_PICK_CHANGES" ]; then
    read -ra EXP_PICK_CHANGES <<< "$EXP_PICK_CHANGES"
    repopick ${EXP_PICK_CHANGES[@]}
  fi
fi
echo "--- Uploading to GitHub Releases"

# 1. Locate the compiled user-flashable installation ZIP file
ZIP_PATH=$(ls out/target/product/${DEVICE}/lineage-16.0-*-UNOFFICIAL-${DEVICE}.zip | head -n 1)

# 2. Check if the file actually compiled successfully before trying to upload
if [ -z "$ZIP_PATH" ] || [ ! -f "$ZIP_PATH" ]; then
  echo "Error: Flashable ROM ZIP not found. Build must have failed."
  exit 1
fi

# 3. Explicitly define your repository (Replace YOUR_ORGANIZATION_NAME with your real GitHub name)
TARGET_REPO="YOUR_ORGANIZATION_NAME/Gitpod-Rom-Builder"
echo "Targeting GitHub Repository: $TARGET_REPO"

# 4. Use the GitHub CLI to look up your existing releases and calculate the next version number
LATEST_TAG=$(gh release list --repo "$TARGET_REPO" --limit 1 | awk '{print $1}')

if [ -z "$LATEST_TAG" ]; then
  NEXT_VER="1.0"
else
  # Strips the prefix to isolate the version number (e.g., "1.1"), then increments it by 0.1
  VERSION_NUM=$(echo "$LATEST_TAG" | sed "s/lineage-16.0-${DEVICE}-//")
  NEXT_VER=$(echo "$VERSION_NUM + 0.1" | bc)
fi

TAG_NAME="lineage-16.0-${DEVICE}-${NEXT_VER}"
echo "Calculated Tag Name: $TAG_NAME"

# 5. Create the GitHub Release inside your repo and upload your flashable ZIP
gh release create "$TAG_NAME" "$ZIP_PATH" \
  --repo "$TARGET_REPO" \
  --title "$TAG_NAME" \
  --notes "Automated build for ${DEVICE} generated via Buildkite cloud runner."


echo "--- cleanup"
rm -rf out*
