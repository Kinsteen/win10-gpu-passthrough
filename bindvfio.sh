if [[ -f /sys/class/drm/card1-DP-1/status ]]; then
    while [[ $(cat /sys/class/drm/card1-DP-1/status) == "connected" ]]; do
        echo "Waiting for screen to disconnect..."
        sleep 1
    done
fi

set -x

systemctl stop nvidia-powerd

# sleep 3

nvidia-smi

echo "0000:01:00.0" > /sys/bus/pci/devices/0000:01:00.0/driver/unbind &
echo "0000:01:00.1" > /sys/bus/pci/devices/0000:01:00.1/driver/unbind &

if ! rmmod nvidia-drm --force; then
exit 1
fi

if ! rmmod nvidia-uvm --force; then
exit 1
fi
if ! rmmod nvidia-modeset --force; then
exit 1
fi
if ! rmmod nvidia --force; then
exit 1
fi

modprobe vfio-pci

echo "vfio-pci" > /sys/bus/pci/devices/0000:01:00.0/driver_override
echo "vfio-pci" > /sys/bus/pci/devices/0000:01:00.1/driver_override

echo "0000:01:00.0" >  /sys/bus/pci/drivers/vfio-pci/bind
echo "0000:01:00.1" >  /sys/bus/pci/drivers/vfio-pci/bind
