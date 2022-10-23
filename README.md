# Windows 10 VM, with GPU Passthrough on a Asus Zephyrus G14 QA401QE
Based on this tutorial, by Asus-Linux: https://asus-linux.org/wiki/vfio-guide

I've made some changes from this tutorial.

My setup:
- Arch Linux, linux-zen kernel
- KDE Plasma as my desktop manager, on Wayland
- Nvidia DKMS driver, latest

## Compute mode -> VFIO fix
On my PC, if I used compute mode without launching the VM, the VM won't boot after, crashing at the start. I suspect that this is due to the memory being allocated wrongly by the Nvidia driver...

In QEMU logs (spamming):
```
2022-07-12T09:35:22.129998Z qemu-system-x86_64: vfio_region_write(0000:01:00.0:region1+0xfe360008, 0xfffffffe000001ff,8) failed: Cannot allocate memory
```

In dmesg (spamming):
```
[ 1151.411303] x86/PAT: CPU 0/KVM:148082 conflicting memory types fe00000000-ff00000000 write-combining<->uncached-minus
[ 1151.411305] x86/PAT: memtype_reserve failed [mem 0xfe00000000-0xfeffffffff], track uncached-minus, req uncached-minus
[ 1151.411306] ioremap memtype_reserve failed -16
```

Some people suggested that /dev/nvidia was still in use, which was not the case, or a BIOS update was the culprit, which wasn't the case.

The way I fixed it was to launch a small program, allocating memory on the GPU WITH the vfio-pci driver.

This is what I used: https://raw.githubusercontent.com/awilliam/tests/master/vfio-pci-device-open.c

And then, a small systemd service to launch it on startup and we're good! (see vfio-fix.service)

## Mouse not left-clicking when keyboard is typing
Another problem I had was the mouse. I used EvDev to passthough my (internal and external) keyboard and my external mouse. But when gaming for example, my left-click would be disabled as long as I pressed keys on the keyboard, specifically letter keys.

I thought that it was Windows thinking that my mouse was somehow a trackpad, and disabled it, but I could still move my mouse, right-click etc... Only left-click was missing.

Using virtio drivers didn't fix anything, as it seems that it's not using it? (I did install the drivers correctly on Windows.)

The fix was to use on libvirt an input type usb, which fixes everything. So the inputs are like this in the XML:

- EvDev declaration
- input virtio (seems to not be useful?)
- input usb
- input ps2 (mandatory)

With this, everything works, even back-forward buttons on the mouse.

## Helper scripts to attach and detach USB devices
One small issue I had was that it was quite cumbersome to add/remove USB devices on the fly: we had to open virt-manager on the host, open the VM, go into setting, add device, select USB device, click okay...

Very long and very boring if you ask me.

I then created some bash scripts: you just type `attachusb`, then a list pops with the USB devices connected to your host. Type the number, and boom! The device is now attached, and if you close and open the VM again, the device will still be passed through.

A script `detachusb` is also done, but way less useful, and works in the same way: live-detach  USB device, and remove it from XML.

You may need to modify `attachusb` to change "fermé" to "closed", or whatever the word closed is in your language. Check answer from `virsh list --all`.

## Helper script to remove USB device on VM startup
One other quirk that was quite annoying is that to start the VM, USB devices NEED to be connected, otherwise the VM won't start. I made a script that checks if every USB device in the XML is connected, and starts the VM.

If a USB device is not connected, it will remove it from the XML before starting the VM.

## Do not go into sleep when looking glass is running
Just a small service using systemd-inhibit so that the pc doesn't go to sleep/dim screen, because it's not receiving any input (because EvDev)
