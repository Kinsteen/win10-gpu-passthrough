set -x

echo "0000:01:00.0" > /sys/bus/pci/devices/0000:01:00.0/driver/unbind &
echo "0000:01:00.1" > /sys/bus/pci/devices/0000:01:00.1/driver/unbind &

if ! rmmod vfio-pci --force; then
exit 1
fi
if ! rmmod vfio_iommu_type1 --force; then
exit 1
fi
if ! rmmod vfio_pci_core --force; then
exit 1
fi
if ! rmmod vfio --force; then
exit 1
fi

echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 > /sys/bus/pci/devices/0000:01:00.1/remove

sleep 1

echo 1 > /sys/bus/pci/rescan

nvidia-modprobe -m

systemctl start nvidia-powerd
