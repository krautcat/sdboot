#!/bin/bash

DEVICE=""
MODEL=""
MODEL_LIST=("artik5" "artik10" "artik530" "artik710")
FORMAT=false
CLEARSDCARD=false
RECOVERY=false
PREBUILT_IMAGE=""
BOOT_IMAGE=""
PLATFORM_IMAGE=""

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR=`mktemp -d`
SDCARD_SIZE=""

PART_SEPARATOR="p"
BOOTPART=1
MODULESPART=2
ROOTFSPART=3
SYSTEMDATAPART=5
USERPART=6

SDBOOTIMG="sd_boot.img"
BOOTIMG="boot.img"
MODULESIMG="modules.img"
ROOTFSIMG="rootfs.img"
SYSTEMDATAIMG="system-data.img"
USERIMG="user.img"

SFDISK_VER=''
SFDISK_OLD=true

function setup_env {
	if [ $MODEL = "artik5" ]; then
		kernel_dtb="exynos3250-artik5.dtb"
		kernel=zImage
		boot_part_type=vfat
		env_offset=4159
		sdboot_files=("bl1.bin" "bl2.bin" "u-boot.bin" "tzsw.bin")
		sdboot_offsets=(1 31 63 2111)
	elif [ $MODEL = "artik10" ]; then
		kernel_dtb="exynos5422-artik10.dtb"
		kernel=zImage
		boot_part_type=vfat
		env_offset=4159
		sdboot_files=("bl1.bin" "bl2.bin" "u-boot.bin" "tzsw.bin")
		sdboot_offsets=(1 31 63 2111)
	elif [ $MODEL = "artik530" ]; then
		kernel_dtb="s5p4418-artik530-raptor-*"
		kernel=zImage
		boot_part_type=ext4
		env_offset=6273
		recovery_boot_files=("partmap_emmc.txt" "bl1-emmcboot.img" "bootloader.img")
		sdboot_files=("bl1-sdboot.img" "bootloader.img")
		sdboot_offsets=(1 129)
	elif [ $MODEL = "artik710" ]; then
		kernel_dtb="s5p6818-artik710-raptor-*"
		kernel=Image
		boot_part_type=ext4
		env_offset=5889
		recovery_boot_files=("partmap_emmc.txt" "bl1-emmcboot.img" "fip-loader-emmc.img" "fip-secure.img" "fip-nonsecure.img")
		sdboot_files=("bl1-sdboot.img" "fip-loader-sd.img" "fip-secure.img" "fip-nonsecure.img")
		sdboot_offsets=(1 129 769 3841)
	fi

	BL1="bl1.bin"
	BL2="bl2.bin"
	UBOOT="u-boot.bin"
	TZSW="tzsw.bin"
	PARAMS="params.bin"
	INITRD="uInitrd"
	KERNEL_DTB=$kernel_dtb
	KERNEL=$kernel
	BOOT_PART_TYPE=$boot_part_type

	if [ $recovery_boot_files ]; then
		RECOVERY_BOOT_FILES=("${recovery_boot_files[@]}")
	else
		RECOVERY_BOOT_FILES=("${sdboot_files[@]}")
	fi
	SDBOOT_FILES=("${sdboot_files[@]}")
	SDBOOT_OFFSETS=("${sdboot_offsets[@]}")

	BL1_OFFSET=1
	BL2_OFFSET=31
	UBOOT_OFFSET=63
	TZSW_OFFSET=2111
	ENV_OFFSET=$env_offset

	SKIP_BOOT_SIZE=4
	BOOT_SIZE=32
	MODULE_SIZE=32
	if $RECOVERY; then
		ROOTFS_SIZE=128
	else
		ROOTFS_SIZE=2048
	fi
	DATA_SIZE=1024
	USER_SIZE=""
}

function die {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

function contains {
	local n=$#
	local value=${!n}
	for ((i=1;i < $#;i++)) {
		if [ "${!i}" == "${value}" ]; then
			echo "y"
			return 0
		fi
	}
	echo "n"
	return 1
}

function check_options {
	test $(contains "${MODEL_LIST[@]}" $MODEL) == y || die "The model name ($MODEL) is incorrect. Please, enter supported model name.  [artik5|artik10]"

	setup_env

	if [ -z $PREBUILT_IMAGE]; then
		PREBUILT_IMAGE="tizen-sd-boot-"$MODEL".tar.gz"
	fi
	test -e $BUILD_DIR/$PREBUILT_IMAGE  || die "file not found : "$PREBUILT_IMAGE
	test -e $BOOT_IMAGE  || die "file not found : "$BOOT_IMAGE
	test -e $PLATFORM_IMAGE  || die "file not found : "$PLATFORM_IMAGE

	test "$DEVICE" != "" || die "Please, enter disk name. /dev/sd[x]"
	if [[ "$DEVICE" == *"mmcblk"* ]]; then
		PART="p"
	fi

	VER_SFDISK=(`sfdisk -v | awk '{print $4}' |sed -e s/[.]/' '/g`)
	if [ ${VER_SFDISK[0]} -ge 2 ]; then
		if [ ${VER_SFDISK[0]} -gt 2 ] || [ ${VER_SFDISK[1]} -ge 26 ]; then
			OLD_SFDISK=false
		fi
	fi

	SIZE=`sudo sfdisk -s $DEVICE`
	test "$SIZE" != "" || die "The disk name ($DEVICE) is incorrect. Please, enter valid disk name.  /dev/sd[x]"

	SDCARD_SIZE=$((SIZE >> 10))
	USER_SIZE=`expr $SDCARD_SIZE - $SKIP_BOOT_SIZE - $BOOT_SIZE - $MODULE_SIZE - $ROOTFS_SIZE - $DATA_SIZE - 2`
	test 100 -lt $USER_SIZE || die  "We recommend to use more than 4GB disk"

	if [ $FORMAT == false ] && [ $RECOVERY == false ] ; then
		test -e $DEVICE$PART_SEPARATOR$USERPART || die "Need to format the disk. Please, use '-f' option."
	fi
}

function show_usage {
	echo ""
	echo "Usage:"
	echo " ./mk_sdboot.sh [options]"
	echo " ex) ./mk_sdboot.sh -m atrik5 -d /dev/sd[x] -f"
	echo " ex) ./mk_sdboot.sh -m atrik5 -d /dev/sd[x] -r"
	echo " ex) ./mk_sdboot.sh -m atrik5 -d /dev/sd[x] -b boot.tar.gz"
	echo " ex) ./mk_sdboot.sh -m atrik5 -d /dev/sd[x] -p platform.tar.gz"
	echo ""
	echo " Be careful, Just replace the /dev/sd[x] for your device!"
	echo ""
	echo "Options:"
	echo " -h, --help			Show help options"
	echo " -m, --model <name>		Model name ex) -m artik5"
	echo " -d, --disk <name>		Disk name ex) -d /dev/sd[x]"
	echo " -f, --format			Format & Partition the Disk"
	echo " -r, --recovery			Make a microsd recovery image"
	echo " -b, --boot-image <file>	Boot file name"
	echo " -p, --platform-image <file>	Platform file name"
	echo ""
	exit 0
}

function parse_options {
	if [ $# -lt 1 ]; then
		show_usage
		exit 0
	fi

	for opt in  "$@"
	do
		case "$opt" in
			-h|--help)
				show_usage
				shift ;;
			-m|--model)
				MODEL="$2"
				shift ;;
			-d|--disk)
				DEVICE=$2
				shift ;;
			-f|--format)
				FORMAT=true
				shift ;;
			-r|--recovery)
				RECOVERY=true
				shift ;;
			-b|--boot-image)
				BOOT_IMAGE=$2
				shift ;;
			-p|--platform-image)
				PLATFORM_IMAGE=$2
				shift ;;
			-c|--clear-sdcard)
				CLEARSDCARD=true
				shift ;;
			*)
				shift ;;
		esac
	done
}

########## Start make_sdbootimg ##########

function gen_sdboot_image {
	local SD_BOOT_SZ=`expr $ENV_OFFSET + 32`

	pushd ${TARGET_DIR}

	dd if=/dev/zero of=$SDBOOTIMG bs=512 count=$SD_BOOT_SZ
	for index in ${!SDBOOT_FILES[*]}; do
		dd conv=notrunc if=$TARGET_DIR/${SDBOOT_FILES[$index]} of=$SDBOOTIMG bs=512 seek=${SDBOOT_OFFSETS[$index]}
	done
	dd conv=notrunc if=$TARGET_DIR/$PARAMS of=$SDBOOTIMG bs=512 seek=$ENV_OFFSET

	sync; sync;

	popd
}


function make_sdbootimg {
	for index in ${!SDBOOT_FILES[*]}; do
		test -e $TARGET_DIR/${SDBOOT_FILES[$index]} || die "file not found : "${SDBOOT_FILES[$index]}
	done

	if $RECOVERY; then
		PARAMS="params_recovery.bin"
	elif $FORMAT; then
		PARAMS="params_sdboot.bin"
	else
		PARAMS="params.bin"
		#sed -i -e 's/rootdev=0/rootdev=1/g' $TARGET_DIR/$PARAMS
	fi
	test -e $TARGET_DIR/$PARAMS || die "file not found : "$PARAMS

	gen_sdboot_image
}

########## Start make_bootimg ##########

function gen_boot_image {
	dd if=/dev/zero of=$BOOTIMG bs=1M count=$BOOT_SIZE
	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		mkfs.vfat -n boot $BOOTIMG
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		mkfs.ext4 -F -L boot -b 4096 $BOOTIMG
	fi
}

function install_boot_image {
	test -d mnt || mkdir mnt
	sudo mount -o loop $BOOTIMG mnt

	sudo su -c "install -m 664 $KERNEL mnt"
	sudo su -c "install -m 664 $KERNEL_DTB mnt"
	sudo su -c "install -m 664 $INITRD mnt"

	sync; sync;
	sudo umount mnt

	rm -rf mnt
}

function make_bootimg {
	test -e $TARGET_DIR/$KERNEL || die "file not found : "$KERNEL
	#test -e $TARGET_DIR/$KERNEL_DTB || die "file not found : "$KERNEL_DTB
	test -e $TARGET_DIR/$INITRD || die "file not found : "$INITRD

	pushd $TARGET_DIR

	gen_boot_image
	install_boot_image

	popd
}

########## Start make_recoveryimg ##########

function gen_recovery_image {
	dd if=/dev/zero of=$ROOTFSIMG bs=1M count=$ROOTFS_SIZE
	mkfs.ext4 -F -L rootfs -b 4096 $ROOTFSIMG
}

function install_recovery_image {
	test -d mnt || mkdir mnt
	sudo mount -o loop $ROOTFSIMG mnt

	for index in ${!RECOVERY_BOOT_FILES[*]}; do
		sudo su -c "cp ${RECOVERY_BOOT_FILES[$index]} mnt"
	done

	sudo su -c "cp $PARAMS mnt"
	sudo su -c "cp $KERNEL mnt"
	sudo su -c "cp $KERNEL_DTB mnt"
	sudo su -c "cp $INITRD mnt"
	sudo su -c "cp $BOOTIMG mnt"
	sudo su -c "cp $MODULESIMG mnt"

	sync; sync;
	sudo umount mnt

	rm -rf mnt
}

function make_recoveryimg {
	PARAMS="params.bin"

	test -e $TARGET_DIR/$PARAMS || die "file not found : "$PARAMS

	pushd $TARGET_DIR

	gen_recovery_image
	install_recovery_image

	popd
}

########## Start fuse_images ##########

function repartition_sd_recovery {
	local BOOT=boot
	local MODULE=modules
	local ROOTFS=rootfs

	echo "========================================"
	echo "Label          dev           size"
	echo "========================================"
	echo $BOOT"		" $DEVICE$PART"1  	" $BOOT_SIZE "MB"
	echo $MODULE"		" $DEVICE$PART"2  	" $MODULE_SIZE "MB"
	echo $ROOTFS"		" $DEVICE$PART"3  	" $ROOTFS_SIZE "MB"

	MOUNT_LIST=`sudo mount | grep $DEVICE | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		sudo umount $mnt
	done

	echo "Remove partition table..."
	sudo su -c "dd if=/dev/zero of=$DEVICE bs=512 count=1 conv=notrunc"

	if $OLD_SFDISK; then
		sudo sfdisk --Linux --unit M $DEVICE <<-__EOF__
		$SKIP_BOOT_SIZE,$BOOT_SIZE,0xE,*
		,$MODULE_SIZE,,-
		,$ROOTFS_SIZE,,-
		__EOF__
	else
		sudo sfdisk $DEVICE <<-__EOF__
		${SKIP_BOOT_SIZE}MiB,${BOOT_SIZE}MiB,0xE,*
		8MiB,${MODULE_SIZE}MiB,,-
		8MiB,${ROOTFS_SIZE}MiB,,-
		__EOF__
	fi
	
	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		sudo su -c "mkfs.vfat -F 16 $DEVICE$PART_SEPARATOR$BOOTPART -n $BOOT"
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$BOOTPART -L $BOOT -F"
	fi
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$MODULESPART -L $MODULE -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$ROOTFSPART -L $ROOTFS -F"
}

function repartition_sd_boot {
	local BOOT=boot
	local MODULE=modules
	local ROOTFS=rootfs
	local SYSTEMDATA=system-data
	local USER=user

	echo "========================================"
	echo "Label          dev           size"
	echo "========================================"
	echo $BOOT"		" $DEVICE$PART"1  	" $BOOT_SIZE "MB"
	echo $MODULE"		" $DEVICE$PART"2  	" $MODULE_SIZE "MB"
	echo $ROOTFS"		" $DEVICE$PART"3  	" $ROOTFS_SIZE "MB"
	echo "[Extend]""	" $DEVICE$PART"4"
	echo " "$SYSTEMDATA"	" $DEVICE$PART"5  	" $DATA_SIZE "MB"
	echo " "$USER"		" $DEVICE$PART"6  	" $USER_SIZE "MB"

	MOUNT_LIST=`sudo mount | grep $DEVICE | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		sudo umount $mnt
	done

	echo "Remove partition table..."
	sudo su -c "dd if=/dev/zero of=$DEVICE bs=512 count=1 conv=notrunc"

	if $OLD_SFDISK; then
		sudo sfdisk --Linux --unit M $DEVICE <<-__EOF__
		${SKIP_BOOT_SIZE}M,${BOOT_SIZE}M,0xE,*
		$(($SKIP_BOOT_SIZE+$BOOT_SIZE))M,${MODULE_SIZE}M,,-
		$(($SKIP_BOOT_SIZE+$BOOT_SIZE+$MODULE_SIZE))M,${ROOTFS_SIZE}M,,-
		$(($SKIP_BOOT_SIZE+$BOOT_SIZE+$MODULE_SIZE+$ROOTFS_SIZE))M,,E,-
		,${DATA_SIZE}M,,-
		,${USER_SIZE}M,,-
		__EOF__
	else
		sudo sfdisk $DEVICE <<-__EOF__
		${SKIP_BOOT_SIZE}MiB,${BOOT_SIZE}MiB,0xE,*
		8MiB,${MODULE_SIZE}MiB,,-
		8MiB,${ROOTFS_SIZE}MiB,,-
		8MiB,,E,-
		,${DATA_SIZE}MiB,,-
		,${USER_SIZE}MiB,,-
		__EOF__
	fi


	echo "Creating new filesystems..."
	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		sudo su -c "mkfs.vfat -F 16 $DEVICE$PART_SEPARATOR$BOOTPART -n $BOOT"
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$BOOTPART -L $BOOT -F"
	fi
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$MODULESPART -L $MODULE -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$ROOTFSPART -L $ROOTFS -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$SYSTEMDATAPART -L $SYSTEMDATA -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$USERPART -L $USER -F"
}

function clear_sdcard {
	test "$DEVICE" != "" || die "Please, enter disk name. /dev/sd[x]"
	if [[ "$DEVICE" == *"mmcblk"* ]]; then
		PART="p"
	fi

	VER_SFDISK=(`sfdisk -v | awk '{print $4}' |sed -e s/[.]/' '/g`)
	if [ ${VER_SFDISK[0]} -ge 2 ]; then
		if [ ${VER_SFDISK[0]} -gt 2 ] || [ ${VER_SFDISK[1]} -ge 26 ]; then
			OLD_SFDISK=false
		fi
	fi

	MOUNT_LIST=`sudo mount | grep $DEVICE | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		sudo umount $mnt
	done

	SIZE=`sudo sfdisk -s $DEVICE`
	SDCARD_SIZE=$((SIZE >> 10))
	USER_SIZE=`expr $SDCARD_SIZE - 4`
	
	echo "Remove partition table..." $USER_SIZE
	sudo su -c "dd if=/dev/zero of=$DEVICE bs=512 count=1 conv=notrunc"

	if $OLD_SFDISK; then
		sudo sfdisk --in-order --Linux --unit M $DEVICE <<-__EOF__
		4,$USER_SIZE,0xE,*
		__EOF__
	else
		sudo sfdisk $DEVICE <<-__EOF__
		4,${USER_SIZE}MiB,0xE,*
		__EOF__
	fi

	sudo su -c "mkfs.ext4 -q ${DEVICE}${PART}1 -L SDCARD -F"
		sudo su -c "mkfs.vfat -F 16 $DEVICE$PART_SEPARATOR$BOOTPART -n $BOOT"
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$BOOTPART -L $BOOT -F"
	fi
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$MODULESPART -L $MODULE -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$ROOTFSPART -L $ROOTFS -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$SYSTEMDATAPART -L $SYSTEMDATA -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$PART_SEPARATOR$USERPART -L $USER -F"
}

function repartition_sd {
	if $RECOVERY; then
		repartition_sd_recovery
	elif $FORMAT; then
		repartition_sd_boot
	fi

	sync; sync;
}

function fuse_images {
	MOUNT_LIST=`sudo mount | grep $DEVICE | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		sudo umount $mnt
	done

	if [ -f $TARGET_DIR/$SDBOOTIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$SDBOOTIMG of=$DEVICE bs=512 seek=1 skip=1"
	fi

	if [ -f $TARGET_DIR/$BOOTIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$BOOTIMG of=$DEVICE$PART_SEPARATOR$BOOTPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$MODULESIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$MODULESIMG of=$DEVICE$PART_SEPARATOR$MODULESPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$ROOTFSIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$ROOTFSIMG of=$DEVICE$PART_SEPARATOR$ROOTFSPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$SYSTEMDATAIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$SYSTEMDATAIMG of=$DEVICE$PART_SEPARATOR$SYSTEMDATAPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$USERIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$USERIMG of=$DEVICE$PART_SEPARATOR$USERPART bs=1M"
	fi

	sync; sync;
}

##################################

parse_options "$@"

if $CLEARSDCARD; then
	clear_sdcard
	sync
	exit 0
fi

check_options

test -d $TARGET_DIR || mkdir -p $TARGET_DIR

repartition_sd

# make sdcard bootloader image
if $FORMAT || $RECOVERY || [ $BOOT_IMAGE ]; then
	tar -xvf $BUILD_DIR/$PREBUILT_IMAGE -C $TARGET_DIR
	if [ $BOOT_IMAGE ]; then
		tar -xvf $BOOT_IMAGE -C $TARGET_DIR
	fi
	make_sdbootimg
	make_bootimg
fi

# make recovery image
if $RECOVERY; then
	make_recoveryimg
fi

if [ $PLATFORM_IMAGE ]; then
	tar -xvf $PLATFORM_IMAGE -C $TARGET_DIR
fi

fuse_images

rm -rf $TARGET_DIR
