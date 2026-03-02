#!/usr/bin/env bash

# Define target defconfig location
DEFCONFIG="arch/arm64/configs/rodin_defconfig"

echo "⚙️ Added KSU & SuSFS configuration"

# Base KSU Config & Dependencies
cat >> $DEFCONFIG <<EOF
# ===============================================
# Konfigurasi KernelSU Base
CONFIG_KSU=y
CONFIG_KPM=n
CONFIG_KSU_MULTI_MANAGER_SUPPORT=y
# Kprobes is a hard dependency for KSU-Next
CONFIG_KPROBES=y
CONFIG_KPROBE_EVENTS=y
EOF

# Hook method selection logic based on KSU env
if [ "$KSU" == "SukiSU" ]; then
    # SUKISU SPECIAL HANDLING
    if [ "$KSU_SUSFS" = "true" ]; then
        echo "🔧 Mode: SukiSU + SuSFS Enabled"
        cat >> $DEFCONFIG <<EOF
# --- SuSFS Configuration for SukiSU ---
CONFIG_KSU_SUSFS=y
# Let SukiSU handle the hook & mount details internally.
EOF
    else
        echo "🔧 Mode: SukiSU Standard (No SuSFS)"
    fi

elif [ "$KSU_SUSFS" = "true" ]; then
  # LOGIC STANDARD FOR KSU NEXT, REGULAR, RISSU, RKSU
  echo "🔧 Mode: SuSFS Hook Enabled"
  cat >> $DEFCONFIG <<EOF
# --- SuSFS Configuration ---
    CONFIG_KSU_SUSFS=y
    CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
    CONFIG_KSU_SUSFS_SUS_PATH=y
    CONFIG_KSU_SUSFS_SUS_MOUNT=y
    CONFIG_KSU_SUSFS_SUS_KSTAT_SPOOF_GENERIC=y
    CONFIG_KSU_SUSFS_SUS_KSTAT=y
    CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
    CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
    CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSTAT=y
    CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n
    CONFIG_KSU_SUSFS_TRY_UMOUNT=n
    CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=n
    CONFIG_KSU_SUSFS_SPOOF_UNAME=y
    CONFIG_KSU_SUSFS_ENABLE_LOG=y
    CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
    CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
    CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
    CONFIG_KSU_MANUAL_HOOK=n
    CONFIG_KSU_HAS_MANUAL_HOOK=n
EOF

else
  # Standard Logic Without Susfs kprobes mode
  echo "🔧 Mode: Kprobes Hook Standard"
  cat >> $DEFCONFIG <<EOF
# --- Kprobes Hook Method ---
# Disable SuSFS and Manual Hook
    CONFIG_KSU_SUSFS=n
    CONFIG_KSU_SUSFS_SUS_SU=n
    CONFIG_KSU_MANUAL_HOOK=n
    CONFIG_KSU_HAS_MANUAL_HOOK=n
    CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=n
    CONFIG_KSU_SYSCALL_HOOK=n
EOF
fi
