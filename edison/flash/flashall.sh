#!/bin/bash


BACKUP_IFS=$IFS
IFS=$(echo -en "\n\b")

USB_VID=8087
USB_PID=0a99
TIMEOUT_SEC=240

# Handle Ifwi file for DFU update
IFWI_DFU_FILE=ifwi/edison_ifwi-dbg

# Path to u-boot that we want to use
UBOOT_BINARY=u-boot/u-boot-edison-2017_05.bin

# Parse arguments
IMAGE_ROOT=""
GATEWAY_ID=""
HW_MODEL=""
FTPROG=0
ONLYFS=0
ONLYHOME=0

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --image)
    IMAGE_ROOT="$2"
    shift # past argument
    ;;
    --id)
    GATEWAY_ID="$2"
    shift # past argument
    ;;
    --model)
    HW_MODEL="$2"
    shift # past argument
    ;;
    --ftprog)
    FTPROG=1
    ;;
    --onlyfs)
    ONLYFS=1
    ;;
    --onlyhome)
    ONLYHOME=1
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

function usage {
	echo "usage: sudo ./flashall.sh --id <gateway id> --image <image root> --model <model>"
	echo "examp: sudo ./flashall.sh --id c0:98:e5:c0:00:01 --image swarm_gateway-2.0.0-edison-umich --model edison-v3"
}

# Make sure we got valid ID
if [ ${#GATEWAY_ID} -ne 17 ]; then
	echo "ERROR: Invalid gateway ID $GATEWAY_ID"
	usage
	exit
fi

VALID_MODELS="edison-v3 edison-v2 edison"
if [[ ! " $VALID_MODELS " =~ " $HW_MODEL " ]]; then
	echo "ERROR: Invalid HW model ($HW_MODEL)"
	echo "Valid models: $VALID_MODELS"
	usage
	exit
fi

if [[ $ONLYFS -eq 1 ]] && [[ $ONLYHOME -eq 1 ]]; then
  echo "ERROR: Cannot do onlyfs and onlyhome"
  exit
fi

if [[ $ONLYFS -eq 1 ]]; then
	echo "Only flashing the boot, root, and home partitions"
fi

if [[ $ONLYHOME -eq 1 ]]; then
	echo "Only flashing the home partition"
fi

BASE=${GATEWAY_ID:0:12}
END=${GATEWAY_ID:13:4}

ADDR_USB_DFU="${BASE}e${END}"
ADDR_USB_FTDI="${BASE}f${END}"

# Copy the stock gateway env vars string file
cp  u-boot/edison-gateway.txt  u-boot/edison-gateway-custom.txt

# Replace the gateway ID in the u boot environment variables text strings file
sed -i -E "s/gateway_id=(.*)$/gateway_id=$GATEWAY_ID/" u-boot/edison-gateway-custom.txt
sed -i -E "s/model=(.*)$/model=$HW_MODEL/" u-boot/edison-gateway-custom.txt

# Create the binary we can flash onto the edison.
mkenvimage -s 65536 -r -o u-boot/edison-gateway-custom.bin u-boot/edison-gateway-custom.txt

LOG_FILENAME="flash.log"
OUTPUT_LOG_CMD="2>&1 | tee -a ${LOG_FILENAME} | ( sed -n '19 q'; head -n 1; cat >/dev/null )"

DFUTOOL="dfu-util"
echo Using $DFUTOOL

if [ ! -f $IMAGE_ROOT.root ]; then
    echo "File $IMAGE_ROOT.root not found!"
    echo "Can't flash then."
    exit -1
fi
if [ ! -f $IMAGE_ROOT.home ]; then
    echo "File $IMAGE_ROOT.home not found!"
    echo "Can't flash then."
    exit -1
fi
if [ ! -f $IMAGE_ROOT.boot ]; then
    echo "File $IMAGE_ROOT.boot not found!"
    echo "Can't flash then."
    exit -1
fi

# Check that that tar files are extracted
if [ ! -f ${IFWI_DFU_FILE}-00-dfu.bin ]; then
	echo "Extracting IFWI firmware binaries"
	pushd ifwi
	tar xf edison_ifwi-dbg.tar.gz
	popd
fi

function flash-command-try {
	eval sudo $DFUTOOL -v -d ${USB_VID}:${USB_PID} $@ $OUTPUT_LOG_CMD
}

function flash-dfu-ifwi {
	ifwi_hwid_found=`sudo ${DFUTOOL} -l -d ${USB_VID}:${USB_PID} | grep -c $1`
	if [ $ifwi_hwid_found -ne 0 ];
	then
		flash-command ${@:2}
	fi
}

function flash-command {
	flash-command-try $@
	if [ $? -ne 0 ] ;
	then
		echo "Flash failed on $@"
		exit -1
	fi
}

function flash-debug {
	echo "DEBUG: lsusb"
	lsusb
	echo "DEBUG: ${DFUTOOL} -l"
	$DFUTOOL -l
}

function dfu-wait {
	echo "Now waiting for dfu device ${USB_VID}:${USB_PID}"
	if [ -z "$@" ]; then
		echo "Please plug and reboot the board"
        fi
	while [ `sudo ${DFUTOOL} -l -d ${USB_VID}:${USB_PID} | grep Found | grep -c ${USB_VID}` -eq 0 ] \
		&& [ $TIMEOUT_SEC -gt 0 ] && [ $(( TIMEOUT_SEC-- )) ];
	do
		sleep 1
	done

	if [ $TIMEOUT_SEC -eq 0 ];
	then
		echo "Timed out while waiting for dfu device ${USB_VID}:${USB_PID}"
		flash-debug
		if [ -z "$@" ]; then
			echo "Did you plug and reboot your board?"
			echo "If yes, please try a recovery by calling this script with the --recovery option"
                fi
		exit -2
	fi
}

if [[ $FTPROG -eq 1 ]]; then
	echo "Setting the FTDI parameters for the gateway"
	./ftx_prog --manufacturer Lab11 --product "swarm-gateway serial" --new-serial-number $ADDR_USB_FTDI > /dev/null
fi


echo "** Flashing Edison Board $(date) **" >> ${LOG_FILENAME}

echo "Using U-Boot target: edison-gateway-custom"
VARIANT_FILE="u-boot/edison-gateway-custom.bin"

dfu-wait

if [[ $ONLYFS -eq 0 ]] && [[ $ONLYHOME -eq 0 ]]; then
echo "Flashing IFWI"

flash-dfu-ifwi ifwi00  --alt ifwi00  -D "${IFWI_DFU_FILE}-00-dfu.bin"
flash-dfu-ifwi ifwib00 --alt ifwib00 -D "${IFWI_DFU_FILE}-00-dfu.bin"

flash-dfu-ifwi ifwi01  --alt ifwi01  -D "${IFWI_DFU_FILE}-01-dfu.bin"
flash-dfu-ifwi ifwib01 --alt ifwib01 -D "${IFWI_DFU_FILE}-01-dfu.bin"

flash-dfu-ifwi ifwi02  --alt ifwi02  -D "${IFWI_DFU_FILE}-02-dfu.bin"
flash-dfu-ifwi ifwib02 --alt ifwib02 -D "${IFWI_DFU_FILE}-02-dfu.bin"

flash-dfu-ifwi ifwi03  --alt ifwi03  -D "${IFWI_DFU_FILE}-03-dfu.bin"
flash-dfu-ifwi ifwib03 --alt ifwib03 -D "${IFWI_DFU_FILE}-03-dfu.bin"

flash-dfu-ifwi ifwi04  --alt ifwi04  -D "${IFWI_DFU_FILE}-04-dfu.bin"
flash-dfu-ifwi ifwib04 --alt ifwib04 -D "${IFWI_DFU_FILE}-04-dfu.bin"

flash-dfu-ifwi ifwi05  --alt ifwi05  -D "${IFWI_DFU_FILE}-05-dfu.bin"
flash-dfu-ifwi ifwib05 --alt ifwib05 -D "${IFWI_DFU_FILE}-05-dfu.bin"

flash-dfu-ifwi ifwi06  --alt ifwi06  -D "${IFWI_DFU_FILE}-06-dfu.bin"
flash-dfu-ifwi ifwib06 --alt ifwib06 -D "${IFWI_DFU_FILE}-06-dfu.bin"

echo "Flashing U-Boot"
flash-command --alt u-boot0 -D "${UBOOT_BINARY}"

echo "Flashing U-Boot Environment"
flash-command --alt u-boot-env0 -D "${VARIANT_FILE}"

echo "Flashing U-Boot Environment Backup"
flash-command --alt u-boot-env1 -D "${VARIANT_FILE}" -R
echo "Rebooting to apply partition changes"
dfu-wait no-prompt
fi

if [[ $ONLYHOME -eq 0 ]]; then
echo "Flashing boot partition (kernel)"
flash-command --alt boot -D "${IMAGE_ROOT}.boot"

echo "Flashing rootfs, (it can take up to 10 minutes... Please be patient)"
flash-command --alt rootfs -D "${IMAGE_ROOT}.root"
fi

echo "Flashing home, (it can take up to 10 minutes... Please be patient)"
flash-command -v --alt home -D "${IMAGE_ROOT}.home" -R


echo "Rebooting"
echo "U-boot & Kernel System Flash Success..."

IFS=${BACKUP_IFS}
