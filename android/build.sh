#!/bin/bash
set -eo pipefail

echo "--- Setup"
unset CCACHE_EXEC
export PYTHONDONTWRITEBYTECODE=true
export BUILD_ENFORCE_SELINUX=1
export BUILD_NO=
unset BUILD_NUMBER

export CPU_SSE42=false

# Fallbacks for crucial runtime environmental variables
if [ -z "$VERSION" ]; then
  export VERSION=lineage-16.0
fi

if [ -z "$DEVICE" ]; then
  export DEVICE=lt01wifi
fi

if [ -z "$REPO_VERSION" ]; then
  export REPO_VERSION=v2.50.1
fi

if [ -z "$TYPE" ]; then
  export TYPE=userdebug
fi

OFFSET="10000000"
export BUILD_NUMBER=$(($OFFSET + ${BUILDKITE_BUILD_NUMBER:-1}))

export KERNEL_REPO_PROJECT_OBJECTS_DIR=/lineage/${VERSION}/.repo/project-objects-kernel
export KERNEL_REPO_PROJECTS_DIR=/lineage/${VERSION}/.repo/projects-kernel

echo "--- Syncing"
mkdir -p ~/lineage/${VERSION}/.repo/local_manifests
cd ~/lineage/${VERSION}
rm -rf .repo/local_manifests/*
rm -rf vendor || true

# Copy your local manifest folder structures over before firing the initialization routine
if [ -d "$BUILDKITE_BUILD_CHECKOUT_PATH/.buildkite/local_manifests" ]; then
    cp "$BUILDKITE_BUILD_CHECKOUT_PATH/.buildkite/local_manifests/"*.xml .repo/local_manifests/
fi

# Initializing LineageOS Base with optimized group parameters
yes | repo init -u https://github.com/LineageOS/android.git -b ${VERSION} -g default,-darwin,-muppets --repo-rev=${REPO_VERSION} --git-lfs --no-clone-bundle || if [[ $? -eq 141 ]]; then true; else false; fi
repo version

echo "Syncing Repositories"
repo forall -c "git reset --hard && git clean -fdx" || true

# Sequential fallback execution block to ensure a successful source checkout
repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j$(nproc --all) || \
repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j$(nproc --all) || \
repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j$(nproc --all)

repo forall -vpc "if [ -f .gitattributes ]; then git lfs pull; fi"

# Source the target compiler macro tool environment scripts
. build/envsetup.sh

echo "--- Clobber Workspaces"
rm -rf out*

echo "--- Breakfast Validation"
breakfast ${DEVICE} ${TYPE}

if [[ "$TARGET_PRODUCT" != lineage_* ]]; then
    echo "Breakfast dependency configuration validation failed, halting script execution."
    exit 1
fi

echo "--- Compiling ROM Zip via Brunch Engine"
brunch ${DEVICE}

echo "--- Script Execution Complete"
