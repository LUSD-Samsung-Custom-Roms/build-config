#!/bin/bash
set -eo pipefail

echo "--- Setup"
unset CCACHE_EXEC
export PYTHONDONTWRITEBYTECODE=true
export BUILD_ENFORCE_SELINUX=1
export BUILD_NO=
unset BUILD_NUMBER

export CPU_SSE42=false


OFFSET="10000000"
export BUILD_NUMBER=$(($OFFSET + ${BUILDKITE_BUILD_NUMBER:-1}))

export KERNEL_REPO_PROJECT_OBJECTS_DIR=./lineage/lineage-16.0/.repo/project-objects-kernel
export KERNEL_REPO_PROJECTS_DIR=./lineage/lineage-16.0/.repo/projects-kernel

echo "--- Syncing"
mkdir -p ./lineage/lineage-16.0/.repo/local_manifests
mkdir -p ./lineage/lineage-16.0"
cd ./lineage/lineage-16.0
rm -rf .repo/local_manifests/*
rm -rf vendor || true

# Copy your local manifest folder structures over before firing the initialization routine
if [ -d "$BUILDKITE_BUILD_CHECKOUT_PATH/.buildkite/local_manifests" ]; then
    cp "$BUILDKITE_BUILD_CHECKOUT_PATH/.buildkite/local_manifests/"*.xml .repo/local_manifests/
fi

# Initializing LineageOS Base with optimized group parameters
yes | repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 -g default,-darwin,-muppets --repo-rev=v2.50.1 --git-lfs --no-clone-bundle || if [[ $? -eq 141 ]]; then true; else false; fi
repo version

echo "Syncing Repositories"
repo forall -c "git reset --hard && git clean -fdx" || true

# Sequential fallback execution block to ensure a successful source checkout
repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j$(nproc --all)

# Source the target compiler macro tool environment scripts
. build/envsetup.sh

echo "--- Clobber Workspaces"
rm -rf out*

echo "--- Breakfast Validation"
breakfast lt01wifi userdebug

if [[ "$TARGET_PRODUCT" != lineage_* ]]; then
    echo "Breakfast dependency configuration validation failed, halting script execution."
    exit 1
fi

echo "--- Compiling ROM Zip via Brunch Engine"
brunch lt01wifi


