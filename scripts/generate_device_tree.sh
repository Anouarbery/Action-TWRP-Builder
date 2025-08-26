#!/bin/bash
set -e

# -------------------------
# Variables
# -------------------------
FIRMWARE_REPO="https://gitgud.io/Van-Firmware-Dumps/samsung/a56x"
MAGISKBOOT_REPO="https://github.com/Lyinceer/AnyKernel3.git"
WORKDIR="$HOME/a56x_firmware"
DEVICEDIR="$WORKDIR/device/samsung/a56x"
VENDORDIR="$WORKDIR/vendor/samsung/a56x"
TMPDIR="$WORKDIR/tmp_extraction"
MAGISKBOOT_DIR="$WORKDIR/magiskboot"
GIT_REPO_DIR="$HOME/a56x_device_tree"
BRANCH="device_tree_a56x"

mkdir -p "$WORKDIR" "$DEVICEDIR" "$VENDORDIR" "$TMPDIR"

# -------------------------
# Clone firmware
git clone "$FIRMWARE_REPO" "$WORKDIR"

# -------------------------
# Clone magiskboot tools
git clone "$MAGISKBOOT_REPO" "$MAGISKBOOT_DIR"

# Compile magiskboot
cd "$MAGISKBOOT_DIR/tools"
make
cd "$WORKDIR"

# -------------------------
# Extract boot/vendor_boot images
for IMG in $(find "$WORKDIR" -type f -name "boot.img" -o -name "vendor_boot.img"); do
    IMG_BASENAME=$(basename "$IMG")
    mkdir -p "$TMPDIR/boot"
    cp "$IMG" "$TMPDIR/boot/"
    cd "$TMPDIR/boot"

    "$MAGISKBOOT_DIR/tools/magiskboot" unpack "$IMG_BASENAME"

    if [ -f "ramdisk.cpio" ]; then
        mkdir -p ramdisk
        cd ramdisk
        cpio -idm < ../ramdisk.cpio
        cp -v init*.rc fstab.* "$DEVICEDIR/" 2>/dev/null || true
        cd ..
    fi

    if [ -f "split_img/boot.img-dtb" ]; then
        dtc -I dtb -O dts -o "$DEVICEDIR/kernel_extracted.dts" split_img/boot.img-dtb
    fi
    cd "$WORKDIR"
done

# -------------------------
# Extract system/vendor.img
for SYSIMG in $(find "$WORKDIR" -type f -name "system.img" -o -name "vendor.img"); do
    mkdir -p "$TMPDIR/sys"
    cp "$SYSIMG" "$TMPDIR/sys/raw.img"
    simg2img "$TMPDIR/sys/raw.img" "$TMPDIR/sys/system.raw.img"
    mkdir -p "$TMPDIR/sys/mnt"
    sudo mount -o loop "$TMPDIR/sys/system.raw.img" "$TMPDIR/sys/mnt"
    cp -r "$TMPDIR/sys/mnt"/* "$VENDORDIR/"
    sudo umount "$TMPDIR/sys/mnt"
done

# -------------------------
# Create device tree files
cat > "$DEVICEDIR/BoardConfig.mk" << EOF
BOARD_KERNEL_CMDLINE := androidboot.hardware=samsung
BOARD_KERNEL_BASE := 0x10008000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_TAGS_ADDR := 0x10000100
BOARD_KERNEL_TAGS_SIZE := 0x200
BOARD_RAMDISK_OFFSET := 0x01000000
EOF

cat > "$DEVICEDIR/AndroidProducts.mk" << EOF
include \$(CLEAR_VARS)
LOCAL_MODULE := android-info
LOCAL_SRC_FILES := android-info.txt
LOCAL_MODULE_PATH := \$(TARGET_OUT)/system/etc
include \$(BUILD_PREBUILT)
EOF

cat > "$DEVICEDIR/device.mk" << EOF
include \$(CLEAR_VARS)
LOCAL_MODULE := libstagefright
LOCAL_SRC_FILES := \$(call all-subdir-java-files)
LOCAL_MODULE_TAGS := optional
include \$(BUILD_MULTI_PREBUILT)
EOF

cat > "$DEVICEDIR/fstab.a56x" << EOF
/dev/block/bootdevice/by-name/system      /system      ext4    ro      wait
/dev/block/bootdevice/by-name/vendor      /vendor      ext4    ro      wait
/dev/block/bootdevice/by-name/cache       /cache       ext4    rw      wait
EOF

# -------------------------
# Generate proprietary-files.txt
cd "$VENDORDIR"
find . -type f | sed "s|^\./||" > proprietary-files.txt

# -------------------------
# Create Git repo ready to push
mkdir -p "$GIT_REPO_DIR"
cd "$GIT_REPO_DIR"
git init
git checkout -b $BRANCH
mkdir -p device/samsung/a56x vendor/samsung/a56x
cp -r $DEVICEDIR/* device/samsung/a56x/
cp -r $VENDORDIR/* vendor/samsung/a56x/
git add .
git commit -m "Device tree Galaxy A56x complet + blobs propriétaires"

rm -rf "$TMPDIR"
echo "[*] Device tree et repo Git prêts à push"