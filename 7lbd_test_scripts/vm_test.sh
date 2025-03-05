#!/usr/bin/env bash

# This script runs a VM on the host with a VNC console at port 5901.
# It then runs websockify so it is possible to access the console of this VM through the Open OnDemand reverse proxy using websockify.
# If preferred, you could attach to the console directly on port 5901 with a VNC client on the same host.

# The goal of this step is to ensure that the VM will boot.  
# Once the VM boots correctly, shut down the VM, kill websockify and move on to the next step.

# Set environment variables for VM paths and parameters
QEMU_EXEC="/usr/libexec/qemu-kvm"
OVMF_FIRMWARE="/usr/share/edk2/ovmf/OVMF_CODE.fd"
DISK_IMAGE="/home/ja56/win11/winpractice-clone.qcow2"
MACHINE_TYPE="pc-q35-rhel9.4.0"

# Used to connect through websockify and noVNC below
ONDEMAND_SERVER="https://ondemand.rc.byu.edu"

echo "Performing pre-flight checks for the VM..."

# 1. Check QEMU executable
if [ ! -x "$QEMU_EXEC" ]; then
    echo "Error: QEMU executable $QEMU_EXEC does not exist or is not executable."
    exit 1
fi

# 2. Check OVMF firmware file (for UEFI boot)
if [ ! -r "$OVMF_FIRMWARE" ]; then
    echo "Error: OVMF firmware file $OVMF_FIRMWARE not found or not readable."
    exit 1
fi

# 3. Check disk image file
if [ ! -r "$DISK_IMAGE" ]; then
    echo "Error: Disk image $DISK_IMAGE not found or not readable."
    exit 1
fi

# 4. Validate machine type support in QEMU
if ! "$QEMU_EXEC" -machine help | grep -q "$MACHINE_TYPE"; then
    echo "Error: Machine type $MACHINE_TYPE is not supported by your QEMU installation."
    exit 1
fi

echo "All checks passed. Starting VM..."

# Launch the VM using the environment variables
"$QEMU_EXEC" \
    -name guest="${USER}_insecure_vm_test_win11,debug-threads=on" \
    -machine "$MACHINE_TYPE" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_FIRMWARE" \
    -device ich9-ahci,id=sata_controller \
    -drive file="$DISK_IMAGE",format=qcow2,if=none,id=drive0 \
    -device ide-hd,drive=drive0,bus=sata_controller.0 \
    -m 8G \
    -cpu max \
    -smp 5 \
    -boot c \
    -vnc 127.0.0.1:1 \
    -rtc base=localtime \
    -usb -device usb-tablet &
QEMU_PID=$!
echo "QEMU started with PID: $QEMU_PID"

# Check if websockify is already in PATH
if ! command -v websockify >/dev/null 2>&1; then
    echo "WS_CONSOLE.SH: Loading required modules"
    #include all necessary modules or path statements here
    # In other words... customize the following line of code.
    module load python/3.12 websockify
    # Verify websockify was loaded successfully
    if ! command -v websockify >/dev/null 2>&1; then
        echo "WS_CONSOLE.SH: Failed to load websockify module"
        exit 1
    fi
fi

echo "Starting Websockify..."
# Run websockify and have it redirect localhost port 5901 to a websocket on port 41250
websockify 41250 localhost:5901 &
WS_PID=$!
echo "websockify started with PID: $WS_PID"

echo ""
echo "VM and websockify are now running."
echo "For a graceful shutdown, please use the guest OS's shutdown mechanism (for example, ACPI shutdown)."
echo "If there is an issue and you need to force-stop the processes, you can use the following commands:"
echo "    kill $QEMU_PID   # To terminate the VM"
echo "    kill $WS_PID     # To stop websockify"

# The Windows VM should now be accessible via noVNC through Open OnDemand's reverse proxy.
# Use this to troubleshoot boot issues and get Windows set up as needed.
echo "Connect to: $ONDEMAND_SERVER/pun/sys/dashboard/noVNC-1.3.0/vnc.html?autoconnect=true&path=rnode%2F$(hostname -f)%2F41250&resize=remote"
echo "\n...or\n"
echo "From a redirected display, issue:\n"
echo "vncviewer 127.0.0.1:1\n"
