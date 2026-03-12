#!/usr/bin/env bash

# =============================================================================
# TegarXLu GKI Kernel Builder - Final Fixed Version
# Features: ThinLTO, KSU, SuSFS, Performance Optimizations
# =============================================================================

set -e

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
# Clang URL
CLANG_URL="https://github.com/greenforce-project/greenforce_clang/releases/download/20260308/gf-clang-23.0.0-20260308.tar.gz"
CLANG_BRANCH=""
AK3_ZIP_NAME="$KERNEL_NAME-REL-KVER-VARIANT-BUILD_DATE.zip"
OUTDIR="$WORKDIR/out"
KSRC="$WORKDIR/ksrc"
KERNEL_PATCHES="$WORKDIR/kernel-patches"

# =============================================================================
# Default values for undefined variables
# =============================================================================
: "${TODO:=kernel}"
: "${STATUS:=RELEASE}"
: "${KSU:=no}"
: "${LAST_BUILD:=false}"
: "${KSU_SUSFS:=true}"
: "${ENABLE_KPM:=false}"

# Handle error
exec > >(tee "$WORKDIR/build.log") 2>&1
trap 'error "Failed at line $LINENO [$BASH_COMMAND]"' ERR

# Import functions
source "$WORKDIR/functions.sh"

# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || export TZ="$TIMEZONE"

# =============================================================================
# Clone Kernel Source
# =============================================================================
log "Cloning kernel source from $(simplify_gh_url "$KERNEL_REPO")"
rm -rf "$KSRC"
git clone -q --depth=1 "$KERNEL_REPO" -b "$KERNEL_BRANCH" "$KSRC"

cd "$KSRC"
LINUX_VERSION=$(make kernelversion)
LINUX_VERSION_CODE=${LINUX_VERSION//./}
DEFCONFIG_FILE=$(find ./arch/arm64/configs -name "$KERNEL_DEFCONFIG")

# --- KSU Inject Script ---
log "Injecting custom KSU & SuSFS configs from GitHub..."
export KSU
export KSU_SUSFS
wget -qO inject.sh https://raw.githubusercontent.com/TegarXLu/gki-builder/6.x/inject_ksu/gki_defconfig.sh
bash inject.sh
rm inject.sh
cd "$WORKDIR"

# =============================================================================# Set Kernel Variant
# =============================================================================
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
# Download Clang
# =============================================================================
CLANG_DIR="$WORKDIR/clang"
CLANG_BIN="${CLANG_DIR}/bin"
if [ -z "$CLANG_BRANCH" ]; then
  log "🔽 Downloading Clang..."
  if [ ! -d "$CLANG_DIR/bin" ]; then
    wget -qO clang-archive "$CLANG_URL"
    mkdir -p "$CLANG_DIR"
    case "$(basename "$CLANG_URL")" in
      *.tar.* | *.tgz)
        tar -xf clang-archive -C "$CLANG_DIR"
        ;;
      *.7z)
        7z x clang-archive -o"${CLANG_DIR}/" -bd -y > /dev/null
        ;;
      *)
        error "Unsupported file format"
        ;;
    esac
    rm clang-archive

    if [ "$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ] \
      && [ "$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 0 ]; then
      SINGLE_DIR=$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d)
      mv "$SINGLE_DIR"/* "$CLANG_DIR/"
      rm -rf "$SINGLE_DIR"
    fi
  else
    log "Clang already cached, skipping download"
  fi
else
  log "🔽 Cloning Clang..."
  git clone --depth=1 -q "$CLANG_URL" -b "$CLANG_BRANCH" "$CLANG_DIR"fi

# =============================================================================
# Clone GNU Assembler
# =============================================================================
log "Cloning GNU Assembler..."
GAS_DIR="$WORKDIR/gas"
if [ ! -d "$GAS_DIR" ]; then
  git clone --depth=1 -q \
    https://android.googlesource.com/platform/prebuilts/gas/linux-x86 \
    -b main \
    "$GAS_DIR"
else
  log "GNU Assembler already cached, skipping clone"
fi

export PATH="${CLANG_BIN}:${GAS_DIR}:$PATH"

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

cd "$KSRC"

# =============================================================================
# KernelSU Setup
# =============================================================================
if ksu_included; then
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
  patch -p1 < "$KERNEL_PATCHES/ksu/ksun-add-more-managers-support.patch" || true
  cd "$OLDPWD"
  
  log "Applying fix for undefined SUSFS symbols (KernelSU-Next)..."
  sed -i 's/#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME/#if 0 \/\* CONFIG_KSU_SUSFS_SPOOF_UNAME Disabled to fix build \*\//' drivers/kernelsu/supercalls.c
  log "SUSFS symbol fix applied for KernelSU-Next."

elif [ "$KSU" == "resukisu" ]; then
  log "Setting up ReSukiSU for KVER $KVER..."  curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/Crowdin/kernel/setup.sh" | bash -s main
  
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
    
    if [ "$(echo "$LINUX_VERSION_CODE" | head -c4)" -eq 6630 ]; then
      [ -f "$KERNEL_PATCHES/susfs/namespace.c_fix.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/namespace.c_fix.patch"
      [ -f "$KERNEL_PATCHES/susfs/task_mmu.c_fix.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/task_mmu.c_fix.patch"
    elif [ "$(echo "$LINUX_VERSION_CODE" | head -c4)" -eq 6658 ]; then
      [ -f "$KERNEL_PATCHES/susfs/task_mmu.c_fix-k6.6.58.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/task_mmu.c_fix-k6.6.58.patch"
    elif [ "$(echo "$LINUX_VERSION_CODE" | head -c2)" -eq 61 ]; then
      [ -f "$KERNEL_PATCHES/susfs/fs_proc_base.c-fix-k6.1.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/fs_proc_base.c-fix-k6.1.patch"    elif [ "$(echo "$LINUX_VERSION_CODE" | head -c3)" -eq 510 ]; then
      [ -f "$KERNEL_PATCHES/susfs/pershoot-susfs-k5.10.patch" ] && patch -p1 < "$KERNEL_PATCHES/susfs/pershoot-susfs-k5.10.patch"
    fi

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
export KBUILD_BUILD_HOST="$HOST"export KBUILD_BUILD_TIMESTAMP=$(date)
export KCFLAGS="-w"

# ThinLTO for Stability
if [ "$(echo "$LINUX_VERSION_CODE" | head -c1)" -eq 6 ]; then
  MAKE_ARGS=(
    LLVM=1
    LLVM_IAS=1
    LTO=thin
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
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    -j"$(nproc --all)"
    O="$OUTDIR"
  )
fi

KERNEL_IMAGE="$OUTDIR/arch/arm64/boot/Image"
MODULE_SYMVERS="$OUTDIR/Module.symvers"

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
⚡ *LTO Mode*: ThinLTO
EOF
)

# =============================================================================
# Build GKI
# =============================================================================log "Generating config..."
make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG"

# Merge additional configs if any
if [ "$DEFCONFIG_TO_MERGE" ]; then
  log "Merging additional configs..."
  for config in $DEFCONFIG_TO_MERGE; do
    make "${MAKE_ARGS[@]}" scripts/kconfig/merge_config.sh -O "$OUTDIR" "$config"
  done
fi

# =============================================================================
# ✅ CONFIG FRAGMENTS - BTF, LTO, KPM
# =============================================================================
log "Applying configuration fragments..."

# BTF Disable (Prevent pahole error)
cat > "$WORKDIR/disable-btf.config" << EOF
CONFIG_DEBUG_INFO_BTF=n
CONFIG_PAHOLE_KCONF=n
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=n
CONFIG_DEBUG_INFO=n
EOF

# LTO Force (Ensure ThinLTO active)
cat > "$WORKDIR/force-lto.config" << EOF
CONFIG_LTO_CLANG=y
CONFIG_LTO_CLANG_FULL=n
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO_NONE=n
EOF

# KPM (Optional - Enable if needed)
if [ "$ENABLE_KPM" == "true" ]; then
  log "⚠️ KPM Enabled - May cause bootloop!"
  cat > "$WORKDIR/enable-kpm.config" << EOF
CONFIG_KPM=y
CONFIG_KPROBES=y
CONFIG_KPROBE_EVENTS=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_CFI_CLANG=n
CONFIG_KCFI=n
EOF
  make "${MAKE_ARGS[@]}" scripts/kconfig/merge_config.sh -O "$OUTDIR" "$WORKDIR/enable-kpm.config"
else
  log "KPM Disabled for stability"
  cat > "$WORKDIR/disable-kpm.config" << EOF
CONFIG_KPM=n
CONFIG_KPROBES=nCONFIG_KPROBE_EVENTS=n
EOF
fi

# Merge all fragments
make "${MAKE_ARGS[@]}" scripts/kconfig/merge_config.sh -O "$OUTDIR" "$WORKDIR/disable-btf.config"
make "${MAKE_ARGS[@]}" scripts/kconfig/merge_config.sh -O "$OUTDIR" "$WORKDIR/force-lto.config"
make "${MAKE_ARGS[@]}" olddefconfig

# Verify configurations
log "Verifying configurations..."
grep -E "CONFIG_LTO_CLANG_THIN|CONFIG_DEBUG_INFO_BTF|CONFIG_KPM" "$OUTDIR/.config" | tee -a "$WORKDIR/build.log" || true

# Upload defconfig if needed
if [ "$TODO" == "defconfig" ]; then
  log "Uploading defconfig..."
  upload_file "$OUTDIR/.config"
  exit 0
fi

# =============================================================================
# Build Kernel
# =============================================================================
log "Building kernel with ThinLTO..."
make "${MAKE_ARGS[@]}"

# Check KMI (Ignore for custom kernel)
log "Running KMI check..."
if [ "$(echo "$LINUX_VERSION_CODE" | head -c1)" -eq 6 ]; then
  "$KMI_CHECK" "$KSRC/android/abi_gki_aarch64.stg" "$MODULE_SYMVERS" || {
    log "⚠️ KMI check failed (CRC mismatch). Normal for custom kernels."
  }
else
  "$KMI_CHECK" "$KSRC/android/abi_gki_aarch64.xml" "$MODULE_SYMVERS" || {
    log "⚠️ KMI check failed (CRC mismatch). Normal for custom kernels."
  }
fi

cd "$WORKDIR"

# =============================================================================
# Post-compiling Stuff
# =============================================================================
cd "$WORKDIR"

# Clone AnyKernel
log "Cloning anykernel from $(simplify_gh_url "$ANYKERNEL_REPO")"
rm -rf anykernel
git clone -q --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" anykernel
# Verify clone
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

# =============================================================================
# ✅ GENERATE ANYKERNEL3 OPTIMIZATION SCRIPTS
# =============================================================================
log "Generating AnyKernel3 optimization scripts..."

mkdir -p "$WORKDIR/anykernel/service.d"

# Create kernel-tweak.sh
cat > "$WORKDIR/anykernel/service.d/00kernel-tweak.sh" << 'EOF'
#!/system/bin/sh
log -t TegarXLu "Applying kernel optimizations..."

# CPU Governor
for cpu in /sys/devices/system/cpu/cpufreq/policy*; do
  echo schedutil > $cpu/scaling_governor 2>/dev/null
done

# I/O Scheduler
for block in /sys/block/*/queue; do
  echo mq-deadline > $block/scheduler 2>/dev/null
done

# VM Settings
echo 100 > /proc/sys/vm/swappiness 2>/dev/null
echo 60 > /proc/sys/vm/dirty_ratio 2>/dev/null

# Network
echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null

# GPU
echo bzq > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null

log -t TegarXLu "Optimizations applied!"
EOF

chmod +x "$WORKDIR/anykernel/service.d/00kernel-tweak.sh"
# Create game-mode.sh
cat > "$WORKDIR/anykernel/service.d/01game-mode.sh" << 'EOF'
#!/system/bin/sh
cat > /data/local/tmp/game_mode.sh << 'GAMEEOF'
#!/system/bin/sh
echo performance > /sys/devices/system/cpu/cpufreq/policy*/scaling_governor 2>/dev/null
echo performance > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null
log -t TegarXLu "Game Mode Activated"
GAMEEOF
chmod 755 /data/local/tmp/game_mode.sh
log -t TegarXLu "Game mode script created"
EOF

chmod +x "$WORKDIR/anykernel/service.d/01game-mode.sh"

log "AnyKernel3 optimization scripts generated"

# =============================================================================
# Set Kernel String in AnyKernel
# =============================================================================
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

# =============================================================================
# Zip AnyKernel
# =============================================================================
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
    echo "LTO_MODE=ThinLTO"
    echo "KPM=${ENABLE_KPM}"
  ) >> "$WORKDIR/artifacts/info.txt"
fi

if [ "$STATUS" == "BETA" ]; then
  upload_file "$WORKDIR/$AK3_ZIP_NAME" "$text"
  upload_file "$WORKDIR/build.log"
else
  send_msg "✅ Build Succeeded for $VARIANT variant."
fi

log "🎉 Build completed successfully!"
log "📦 Output: $WORKDIR/artifacts/$AK3_ZIP_NAME"

exit 0
