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

echo "Installing Repo and Other Tools Needed for Build!"
apt update && apt upgrade -y && apt install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc xxd zip zlib1g-dev

mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

echo "--- Syncing"
mkdir -p ./lineage/lineage-16.0/.repo/local_manifests
mkdir -p "./lineage/lineage-16.0"
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
repo sync --detach --current-branch --no-tags --force-remove-dirty --force-sync -j"$(nproc --all)"

# Source the target compiler macro tool environment scripts
chmod +x ./build/envsetup.sh
source build/envsetup.sh

echo "--- Clobber Workspaces"
rm -rf out*

echo "--- Breakfast Validation"
breakfast lt01wifi

if [[ $TARGET_PRODUCT != lineage_* ]]; then
    echo "Breakfast dependency configuration validation failed, halting script execution."
    exit 1
fi

echo "--- Compiling ROM Zip via Brunch Engine"
brunch lt01wifi

echo "--- Script Execution Complete"
