#!/usr/bin/env bash

# Kernel name
KERNEL_NAME="TegarXLu"
# Kernel Build variables
USER="eraselk"
HOST="gacorprjkt"
TIMEZONE="Asia/Makassar"
# AnyKernel
ANYKERNEL_REPO="https://github.com/TegarXLu/AnyKernel3"
ANYKERNEL_BRANCH="main"
# Kernel Source
KERNEL_REPO="https://github.com/TegarXLu/android_kernel_common-5.10"
KERNEL_BRANCH="android12-5.10"
KERNEL_DEFCONFIG="gki_defconfig"
# Release repository
GKI_RELEASES_REPO="https://github.com/TegarXLu/X669C-Release"
# Clang
CLANG_URL="$(./clang.sh mandi-sa)"
CLANG_BRANCH=""
# Zip name
# Format: Kernel_name-Linux_version-Variant-Build_date
ZIP_NAME="$KERNEL_NAME-KVER-VARIANT-BUILD_DATE.zip"
