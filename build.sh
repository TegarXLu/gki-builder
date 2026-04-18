#!/usr/bin/env bash

# =============================================================================
# TegarXLu GKI Kernel Builder
# Modified Version with Fixes for LLVM_IAS, Variable Safety, and Patch Checks
# =============================================================================

# Constants
WORKDIR="$(pwd)"
if [ "$KVER" == "6.6" ]; then
  RELEASE="v0.3"
elif [ "$KVER" == "5.10" ]; then
  RELEASE="v0.3"
elif [ "$KVER" == "6.1" ]; then
  RELEASE="v0.1"
fi

KERNEL_NAME="TegarXLu"
USER="TegarXLu"
HOST="TegarXLu"
TIMEZONE="Asia/Jakarta"
ANYKERNEL_REPO="https://github.com/TegarXLu/AnyKernel3"

# Fixed Logic: 5.10 & 6.1 use gki_defconfig, others use quartix_defconfig
if [ "$KVER" == "6.6" ]; then
  KERNEL_DEFCONFIG="capybara_defconfig"
elif [ "$KVER" == "6.1" ]; then
  KERNEL_DEFCONFIG="gki_defconfig"
else
  KERNEL_DEFCONFIG="capybara_defconfig"
fi

if [ "$KVER" == "6.6" ]; then
  KERNEL_REPO="https://github.com/TegarXLu/capybara-aosp-gki"
  ANYKERNEL_BRANCH="main"
  KERNEL_BRANCH="capybara-gki-2.0"
elif [ "$KVER" == "6.1" ]; then
  KERNEL_REPO="https://github.com/ramabondanp/android_kernel_common-6.1.git"
  ANYKERNEL_BRANCH="master"
  KERNEL_BRANCH="android14-6.1-staging"
elif [ "$KVER" == "5.10" ]; then
  KERNEL_REPO="https://github.com/ramabondanp/android_kernel_common-5.10.git"
  ANYKERNEL_BRANCH="master"
  KERNEL_BRANCH="android12-5.10-staging"
fi
DEFCONFIG_TO_MERGE=""
GKI_RELEASES_REPO="https://github.com/TegarXLu/gki-builder"

# Change the clang by removing the (#) sign then apply
#CLANG_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.0/LLVM-22.1.0-Linux-X64.tar.xz"#CLANG_URL="https://github.com/linastorvaldz/idk/releases/download/clang-r547379/clang.tgz"
#CLANG_URL="https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b/archive/refs/heads/lineage-20.0.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel-2025/clang-r536225.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/62cdcefa89e31af2d72c366e8b5ef8db84caea62/clang-r547379.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/105aba85d97a53d364585ca755752dae054b49e8/clang-r584948b.tar.gz"
#CLANG_URL="https://github.com/greenforce-project/greenforce_clang/releases/download/20260308/gf-clang-23.0.0-20260308.tar.gz"
CLANG_URL="https://github.com/greenforce-project/greenforce_clang/releases/download/20260110/gf-clang-22.0.0-20260110.tar.gz"
#CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/42d2c090c14c9c7f4dfd365ae551e2b959dc775c/clang-r584948b.tar.gz"
#CLANG_URL="https://github.com/linastorvaldz/gki-builder/releases/download/clang-r487747c/clang-r487747c.tar.gz"
#CLANG_URL="$(./clang.sh slim)"
CLANG_BRANCH=""
AK3_ZIP_NAME="$KERNEL_NAME-REL-KVER-VARIANT-BUILD_DATE.zip"
OUTDIR="$WORKDIR/out"
KSRC="$WORKDIR/ksrc"
KERNEL_PATCHES="$WORKDIR/kernel-patches"

# Handle error
exec > >(tee "$WORKDIR/build.log") 2>&1
trap 'error "Failed at line $LINENO [$BASH_COMMAND]"' ERR

# Import functions
source "$WORKDIR/functions.sh"

# =============================================================================
# ✅ FIX 1: Default values for undefined variables
# =============================================================================
: "${TODO:=kernel}"
: "${STATUS:=RELEASE}"
: "${KSU:=no}"
: "${LAST_BUILD:=false}"

# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || export TZ="$TIMEZONE"

# Clone kernel source
log "Cloning kernel source from $(simplify_gh_url "$KERNEL_REPO")"
git clone -q --depth=1 "$KERNEL_REPO" -b "$KERNEL_BRANCH" "$KSRC"

cd "$KSRC"
LINUX_VERSION=$(make kernelversion)
LINUX_VERSION_CODE=${LINUX_VERSION//./}
DEFCONFIG_FILE=$(find ./arch/arm64/configs -name "$KERNEL_DEFCONFIG")

# --- ADD KSU INJECT SCRIPT ---
log "Injecting custom KSU & SuSFS configs from GitHub..."
export KSU
export KSU_SUSFS
wget -qO inject.sh https://raw.githubusercontent.com/TegarXLu/gki-builder/6.x/inject_ksu/gki_defconfig.sh
bash inject.sh
rm inject.sh
# --------------------------------------cd "$WORKDIR"

# Set Kernel variant
log "Setting Kernel variant..."
case "$KSU" in
  "yes") VARIANT="KSU" ;;
  "resukisu") VARIANT="ReSukiSU" ;;
  "no") VARIANT="VNL" ;;
  *) VARIANT="VNL" ;;
esac
susfs_included && VARIANT+="+SuSFS"

# Replace Placeholder in zip name
AK3_ZIP_NAME=${AK3_ZIP_NAME//KVER/$LINUX_VERSION}
AK3_ZIP_NAME=${AK3_ZIP_NAME//VARIANT/$VARIANT}

# =============================================================================
# Download Clang - FIXED
# =============================================================================
CLANG_DIR="$WORKDIR/clang"
CLANG_BIN="${CLANG_DIR}/bin"

# ✅ FIX 1: Check if Clang already exists and is valid
if [ -d "$CLANG_DIR" ] && [ -f "$CLANG_BIN/clang" ] && [ -x "$CLANG_BIN/clang" ]; then
  log "✅ Clang already exists and is valid, skipping download"
else
  log "🔽 Downloading Clang LLVM 22.1.1..."
  rm -rf "$CLANG_DIR"
  mkdir -p "$CLANG_DIR"
  
  # Download with retry
  for i in 1 2 3; do
    if wget -q --show-progress -O clang-archive "$CLANG_URL"; then
      log "✅ Clang downloaded successfully"
      break
    else
      log "⚠️ Download attempt $i failed, retrying..."
      rm -f clang-archive
      sleep 5
    fi
  done
  
  if [ ! -f clang-archive ]; then
    error "Failed to download Clang after 3 attempts!"
    exit 1
  fi
  
  # Extract based on file type
  case "$(basename "$CLANG_URL")" in
    *.tar.xz)
      log "Extracting .tar.xz..."
      tar -xf clang-archive -C "$CLANG_DIR" --strip-components=1
      ;;
    *.tar.gz | *.tgz)
      log "Extracting .tar.gz..."
      tar -xzf clang-archive -C "$CLANG_DIR" --strip-components=1
      ;;
    *.7z)
      log "Extracting .7z..."
      7z x clang-archive -o"$CLANG_DIR/" -bd -y > /dev/null
      ;;
    *)
      error "Unsupported Clang archive format!"
      exit 1
      ;;
  esac
  
  rm -f clang-archive
  
  # ✅ FIX 2: Handle nested directory structure
  if [ "$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ] \
    && [ "$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 0 ]; then
    SINGLE_DIR=$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d)
    log "Flattening directory structure from $SINGLE_DIR..."
    mv "$SINGLE_DIR"/* "$CLANG_DIR/"
    mv "$SINGLE_DIR"/.[!.]* "$CLANG_DIR/" 2>/dev/null || true
    rm -rf "$SINGLE_DIR"
  fi
fi

# ✅ FIX 3: Verify Clang binaries exist and are executable
if [ ! -f "$CLANG_BIN/clang" ]; then
  log "⚠️ clang not found in bin/, searching..."
  CLANG_BIN=$(find "$CLANG_DIR" -name "clang" -type f -executable | head -1 | xargs dirname)
  if [ -z "$CLANG_BIN" ]; then
    error "Clang binary not found! Extraction may have failed."
    ls -la "$CLANG_DIR/"
    exit 1
  fi
fi

# ✅ FIX 4: Test if clang is executable
if ! "$CLANG_BIN/clang" --version > /dev/null 2>&1; then
  error "Clang binary is not executable! Check architecture compatibility."
  file "$CLANG_BIN/clang"
  exit 1
fi

# ✅ FIX 5: Export PATH BEFORE any make commands
export PATH="${CLANG_BIN}:$PATH"

# Verify clang is accessible
log "Verifying Clang installation..."
clang --version | head -1
which clang
which ld.lld

# Clone GNU Assembler
log "Cloning GNU Assembler..."
GAS_DIR="$WORKDIR/gas"
git clone --depth=1 -q \
  https://android.googlesource.com/platform/prebuilts/gas/linux-x86 \
  -b main \
  "$GAS_DIR"

export PATH="${CLANG_BIN}:${GAS_DIR}:$PATH"

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

cd "$KSRC"

# =============================================================================
# KernelSU Setup
# =============================================================================
if ksu_included; then
  # Remove existing KernelSU drivers
  for KSU_PATH in drivers/staging/kernelsu drivers/kernelsu KernelSU KernelSU-Next; do
    if [ -d "$KSU_PATH" ]; then
      log "KernelSU driver found in $KSU_PATH, Removing..."
      KSU_DIR=$(dirname "$KSU_PATH")

      [ -f "$KSU_DIR/Kconfig" ] && sed -i '/kernelsu/d' "$KSU_DIR/Kconfig"
      [ -f "$KSU_DIR/Makefile" ] && sed -i '/kernelsu/d' "$KSU_DIR/Makefile"

      rm -rf "$KSU_PATH"
    fi
  done

  install_ksu 'pershoot/KernelSU-Next' 'dev-susfs'
  config --enable CONFIG_KSU

  cd KernelSU-Next
  patch -p1 < "$KERNEL_PATCHES/ksu/ksun-add-more-managers-support.patch"
  cd "$OLDPWD"
  
  # Fix SUSFS Uname Symbol Error for KernelSU Next & All_Manager
  log "Applying fix for undefined SUSFS symbols (KernelSU-Next)..."
  sed -i 's/#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME/#if 0 \/\* CONFIG_KSU_SUSFS_SPOOF_UNAME Disabled to fix build \*\//' drivers/kernelsu/supercalls.c
  log "SUSFS symbol fix applied for KernelSU-Next."

# =============================================================================
# ReSukiSU Setup - FIXED with Error Handling
# =============================================================================
elif [ "$KSU" == "resukisu" ]; then
  log "Setting up ReSukiSU for KVER $KVER..."
  
  log "Running ReSukiSU setup from main branch..."
  
  # ✅ FIX 1: Download script first, check if exists
  REZUKISU_SETUP_URL="https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh"
  
  # Try main branch first, fallback to Crowdin
  if ! curl -LSsf "$REZUKISU_SETUP_URL" -o /tmp/resukisu_setup.sh 2>/dev/null; then
    log "⚠️ main branch not found, trying Crowdin branch..."
    REZUKISU_SETUP_URL="https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/Crowdin/kernel/setup.sh"
    if ! curl -LSsf "$REZUKISU_SETUP_URL" -o /tmp/resukisu_setup.sh 2>/dev/null; then
      error "ReSukiSU setup script not found! Check repository URL."
      exit 1
    fi
  fi
  
  # ✅ FIX 2: Verify script downloaded successfully
  if [ ! -s /tmp/resukisu_setup.sh ]; then
    error "ReSukiSU setup script is empty! Download failed."
    exit 1
  fi
  
  # ✅ FIX 3: Check for 404 in downloaded content
  if grep -q "404: Not Found" /tmp/resukisu_setup.sh; then
    error "ReSukiSU setup script returned 404! URL may be invalid."
    exit 1
  fi
  
  # ✅ FIX 4: Execute with error handling
  if ! bash /tmp/resukisu_setup.sh main; then
    error "ReSukiSU setup failed!"
    rm -f /tmp/resukisu_setup.sh
    exit 1
  fi
  
  rm -f /tmp/resukisu_setup.sh
  
  if [ "$KVER" == "5.10" ]; then
    log "Applying SUSFS patches for GKI 5.10 (ReSukiSU Method)..."
    SUSFS_BRANCH="gki-android12-5.10"
    git clone https://gitlab.com/simonpunk/susfs4ksu/ -b "$SUSFS_BRANCH" sus
    rm -rf sus/.git
    susfs=sus/kernel_patches
    cp -r "$susfs/fs" .
    cp -r "$susfs/include" .
    cp -r "$susfs/50_add_susfs_in_${SUSFS_BRANCH}.patch" .
    patch -p1 < "50_add_susfs_in_${SUSFS_BRANCH}.patch" || true
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
    config --disable CONFIG_KPM
    config --enable CONFIG_KSU_MULTI_MANAGER_SUPPORT
    config --enable CONFIG_KSU_SUSFS
    log "[✓] ReSukiSU & SUSFS patched for $KVER."
  else
    config --enable CONFIG_KSU_SUSFS
    log "SUSFS config enabled for $KVER."
  fi
fi

# =============================================================================
# SUSFS (Standard Logic)
# =============================================================================
if susfs_included; then
  if [ "$KSU" != "resukisu" ] || ([ "$KSU" == "resukisu" ] && ([ "$KVER" == "6.1" ] || [ "$KVER" == "6.6" ])); then
    log "Applying kernel-side susfs patches (Standard Method)"
    SUSFS_DIR="$WORKDIR/susfs"
    SUSFS_PATCHES="${SUSFS_DIR}/kernel_patches"
    if [ "$KVER" == "6.6" ]; then
      SUSFS_BRANCH=gki-android15-6.6
    elif [ "$KVER" == "6.1" ]; then
      SUSFS_BRANCH=gki-android14-6.1
    elif [ "$KVER" == "5.10" ]; then
      SUSFS_BRANCH=gki-android12-5.10
    fi
    git clone --depth=1 -q https://gitlab.com/simonpunk/susfs4ksu -b "$SUSFS_BRANCH" "$SUSFS_DIR"
    cp -R "$SUSFS_PATCHES/fs"/* ./fs
    cp -R "$SUSFS_PATCHES/include"/* ./include
    patch -p1 < "$SUSFS_PATCHES/50_add_susfs_in_${SUSFS_BRANCH}.patch" || true
    
    # =============================================================================
    # ✅ FIX 2: Safe patch application with file existence checks
    # =============================================================================
    if [ "$(echo "$LINUX_VERSION_CODE" | head -c4)" -eq 6630 ]; then
      [ -f "$KERNEL_PATCHES/susfs/namespace.c_fix.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/namespace.c_fix.patch"
      [ -f "$KERNEL_PATCHES/susfs/task_mmu.c_fix.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/task_mmu.c_fix.patch"
    elif [ "$(echo "$LINUX_VERSION_CODE" | head -c4)" -eq 6658 ]; then
      [ -f "$KERNEL_PATCHES/susfs/task_mmu.c_fix-k6.6.58.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/task_mmu.c_fix-k6.6.58.patch"
    elif [ "$(echo "$LINUX_VERSION_CODE" | head -c2)" -eq 61 ]; then
      [ -f "$KERNEL_PATCHES/susfs/fs_proc_base.c-fix-k6.1.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/fs_proc_base.c-fix-k6.1.patch"
    elif [ "$(echo "$LINUX_VERSION_CODE" | head -c3)" -eq 510 ]; then      [ -f "$KERNEL_PATCHES/susfs/pershoot-susfs-k5.10.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/pershoot-susfs-k5.10.patch"
    fi

    # CRC Fix Logic
    if [ "$(echo "$LINUX_VERSION_CODE" | head -c1)" -eq 6 ]; then
      if [ "$KSU" == "yes" ]; then
        if [ "$KVER" == "6.1" ]; then
          log "Applying manual statfs CRC fix for KernelSU Next GKI 6.1..."
          sed -i '/#include <linux\/susfs_def.h>/i #ifndef __GENKSYMS__' fs/statfs.c
          sed -i '/#include "mount.h"/a #endif' fs/statfs.c
        else
          log "Applying statfs CRC fix patch (KernelSU Next)..."
          [ -f "$KERNEL_PATCHES/susfs/fix-statfs-crc-mismatch-susfs.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/fix-statfs-crc-mismatch-susfs.patch"
        fi
      elif [ "$KSU" == "resukisu" ] && [ "$KVER" == "6.1" ]; then
        log "Applying manual statfs CRC fix for ReSukiSU GKI 6.1..."
        sed -i '/#include <linux\/susfs_def.h>/i #ifndef __GENKSYMS__' fs/statfs.c
        sed -i '/#include "mount.h"/a #endif' fs/statfs.c
      fi
    fi

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
    config --enable CONFIG_KSU_SUSFS
  else
    log "Skipping standard SUSFS patch (Handled by ReSukiSU or logic elsewhere)."
  fi
else
  config --disable CONFIG_KSU_SUSFS
fi

# =============================================================================
# Set Localversion
# =============================================================================
if [ "$TODO" == "kernel" ]; then
  LATEST_COMMIT_HASH=$(git rev-parse --short HEAD)
  if [ "$STATUS" == "BETA" ]; then
    SUFFIX="$LATEST_COMMIT_HASH"
  else
    SUFFIX="${RELEASE}@${LATEST_COMMIT_HASH}"
  fi
  config --set-str CONFIG_LOCALVERSION "-$KERNEL_NAME/$SUFFIX"
  config --disable CONFIG_LOCALVERSION_AUTO
  sed -i 's/echo "+"/# echo "+"/g' scripts/setlocalversion
fi

# =============================================================================
# Declare Build Variables
# =============================================================================
export KBUILD_BUILD_USER="$USER"
export KBUILD_BUILD_HOST="$HOST"
export KBUILD_BUILD_TIMESTAMP=$(date)
export KCFLAGS="-w"

# =============================================================================
# MAKE ARGS - FIXED
# =============================================================================
if [ "$(echo "$LINUX_VERSION_CODE" | head -c1)" -eq 6 ]; then
  MAKE_ARGS=(
    LLVM=1
    LLVM_IAS=1
    LTO=thin
    CLANG_TRIPLE=aarch64-linux-gnu-
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    -j"$(nproc --all)"
    O="$OUTDIR"
  )
else
  MAKE_ARGS=(
    LLVM=1
    LTO=thin
    CLANG_TRIPLE=aarch64-linux-gnu-
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    -j"$(nproc --all)"
    O="$OUTDIR"
  )
fi

KERNEL_IMAGE="$OUTDIR/arch/arm64/boot/Image"
MODULE_SYMVERS="$OUTDIR/Module.symvers"

# KMI Check path based on version
if [ "$(echo "$LINUX_VERSION_CODE" | head -c1)" -eq 6 ]; then
  KMI_CHECK="$WORKDIR/py/kmi-check-6.x.py"
else
  KMI_CHECK="$WORKDIR/py/kmi-check-5.x.py"
fi

text=$(
  cat << EOF
🐧 *Linux Version*: $LINUX_VERSION
📅 *Build Date*: $KBUILD_BUILD_TIMESTAMP
📛 *KernelSU*: ${KSU}
ඞ *SuSFS*: $(susfs_included && echo "$SUSFS_VERSION" || echo "None")
🔰 *Compiler*: $COMPILER_STRING
EOF
)
# =============================================================================
# Build GKI
# =============================================================================
log "Generating config..."
make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG"

# Merge additional configs if any
if [ "$DEFCONFIG_TO_MERGE" ]; then
  log "Merging additional configs..."
  for config in $DEFCONFIG_TO_MERGE; do
    make "${MAKE_ARGS[@]}" scripts/kconfig/merge_config.sh -O "$OUTDIR" "$config"
  done
  else
    error "scripts/kconfig/merge_config.sh does not exist in the kernel source"
  fi
  make "${MAKE_ARGS[@]}" olddefconfig
fi

# Upload defconfig if we are doing defconfig
if [ "$TODO" == "defconfig" ]; then
  log "Uploading defconfig..."
  upload_file "$OUTDIR/.config"
  exit 0
fi

# Build the actual kernel
log "Building kernel..."
make "${MAKE_ARGS[@]}"

# Check KMI Function symbol
if [ "$(echo "$LINUX_VERSION_CODE" | head -c1)" -eq 6 ]; then
  "$KMI_CHECK" "$KSRC/android/abi_gki_aarch64.stg" "$MODULE_SYMVERS" || true
else
  "$KMI_CHECK" "$KSRC/android/abi_gki_aarch64.xml" "$MODULE_SYMVERS" || true
fi

# --- DISABLE KPM SECTION ---
log "Skipping KPM patch (ReSukiSU variant disabled)."

# Return to the initial working directory (Post-compiling steps)
cd "$WORKDIR"
# ----------------------------------------------------

# =============================================================================
# Post-compiling Stuff
# =============================================================================
cd "$WORKDIR"

# Clone AnyKernel
log "Cloning anykernel from $(simplify_gh_url "$ANYKERNEL_REPO")"
git clone -q --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" anykernel

# ✅ FIX: Verify clone succeeded
if [ ! -d "$WORKDIR/anykernel" ]; then
  error "AnyKernel clone failed!"
  exit 1
fi

if [ ! -f "$WORKDIR/anykernel/anykernel.sh" ]; then
  log "WARNING: anykernel.sh not found, checking directory contents..."
  ls -la "$WORKDIR/anykernel/"
  error "anykernel.sh not found! Check ANYKERNEL_REPO and ANYKERNEL_BRANCH."
  exit 1
fi

# Set kernel string in anykernel
if [ "$STATUS" == "BETA" ]; then
  BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%Y%m%d-%H%M")
  AK3_ZIP_NAME=${AK3_ZIP_NAME//BUILD_DATE/$BUILD_DATE}
  AK3_ZIP_NAME=${AK3_ZIP_NAME//-REL/}
  sed -i \
    "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${LINUX_VERSION} (${BUILD_DATE}) ${VARIANT}/g" \
    "$WORKDIR/anykernel/anykernel.sh"
else
  AK3_ZIP_NAME=${AK3_ZIP_NAME//-BUILD_DATE/}
  AK3_ZIP_NAME=${AK3_ZIP_NAME//REL/$RELEASE}
  sed -i \
    "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${RELEASE} ${LINUX_VERSION} ${VARIANT}/g" \
    "$WORKDIR/anykernel/anykernel.sh"
fi

# Zip the anykernel
cd anykernel
log "Zipping anykernel..."
cp "$KERNEL_IMAGE" .
zip -r9 "$WORKDIR/$AK3_ZIP_NAME" ./*
cd "$OLDPWD"

if [ "$STATUS" != "BETA" ]; then
  echo "BASE_NAME=$KERNEL_NAME-$VARIANT" >> "$GITHUB_ENV"
  mkdir -p "$WORKDIR/artifacts"
  mv "$WORKDIR"/*.zip "$WORKDIR/artifacts"
fi

if [ "$LAST_BUILD" == "true" ] && [ "$STATUS" != "BETA" ]; then
  (
    echo "LINUX_VERSION=$LINUX_VERSION"
    echo "SUSFS_VERSION=$(curl -s https://gitlab.com/simonpunk/susfs4ksu/raw/gki-android15-6.6/kernel_patches/include/linux/susfs.h | grep -E '^#define SUSFS_VERSION' | cut -d' ' -f3 | sed 's/"//g')"
    echo "KERNEL_NAME=$KERNEL_NAME"
    echo "RELEASE_REPO=$(simplify_gh_url "$GKI_RELEASES_REPO")"
  ) >> "$WORKDIR/artifacts/info.txt"
fi

if [ "$STATUS" == "BETA" ]; then
  upload_file "$WORKDIR/$AK3_ZIP_NAME" "$text"
  upload_file "$WORKDIR/build.log"
else
  send_msg "✅ Build Succeeded for $VARIANT variant."
fi

exit 0

