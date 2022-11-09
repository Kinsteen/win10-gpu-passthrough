# Windows 10 VM, with GPU Passthrough on a Asus Zephyrus G14 QA401QE
Based on this tutorial, by Asus-Linux: https://asus-linux.org/wiki/vfio-guide

I've made some changes from this tutorial.

My setup:
- Arch Linux, linux-zen kernel
- KDE Plasma as my desktop manager, on Wayland
- Nvidia DKMS driver, latest

## Compute mode -> VFIO fix
On my PC, if I used compute mode without launching the VM, the VM won't boot after, crashing at the start. This is due to the memory being allocated by the Nvidia driver not matching the caching technique expected by the VFIO driver, in the Page Attribute Table. Nvidia allocates a write-combining page on some addresses, while vfio-pci driver expects uncached-minus. This behavior is expected and it seems to NOT be a bug in the Linux kernel/drivers.

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

Also, this behavior only exists on kernel 5.14 and onwards. On kernels earlier, 5.13, 5.12 etc, this is NOT a problem. Something introduced on this kernel version creates this behavior.

### First solution: easiest and recommended
The way I fixed it was to launch a small program, allocating memory on the GPU WITH the vfio-pci driver.

This is what I used: https://raw.githubusercontent.com/awilliam/tests/master/vfio-pci-device-open.c

And then, a small systemd service to launch it on startup and we're good! (see vfio-fix.service)

This way, the VM will launch without complaining. Also, the Nvidia driver will be able to load and function properly for the most part, even with the "wrong" caching technique on the allocated pages.

However, on my specific machine, it means that I have awful performance on specific Wine games. For example, Cult of the Lamb drops from 144 fps (VSync) to 8 fps. This is a very strange bug, that is also reproducible on other games, to a lesser extent. CotL is the one game I went to test with, as it's fast to boot and the performance drop is clearly visible.

Another solution exists, which requires patching the Linux Kernel.

### Second solution: patching the Linux kernel
For this solution, you need to fetch the sources of the Linux kernel, and compile it yourself while changing a little function.

Here is the code responsible for checking the conflicts on page memory allocation according to the caching technique:


File arch/x86/mm/pat/memtype_interval.c, line 78 (Linux kernel version 6.1-rc3)
```c
static int memtype_check_conflict(u64 start, u64 end,
				  enum page_cache_mode reqtype,
				  enum page_cache_mode *newtype)
{
	struct memtype *entry_match;
	enum page_cache_mode found_type = reqtype;

	entry_match = interval_iter_first(&memtype_rbroot, start, end-1);
	if (entry_match == NULL)
		goto success;

	if (entry_match->type != found_type && newtype == NULL)
		goto failure;

	dprintk("Overlap at 0x%Lx-0x%Lx\n", entry_match->start, entry_match->end);
	found_type = entry_match->type;

	entry_match = interval_iter_next(entry_match, start, end-1);
	while (entry_match) {
		if (entry_match->type != found_type)
			goto failure;

		entry_match = interval_iter_next(entry_match, start, end-1);
	}
success:
	if (newtype)
		*newtype = found_type;

	return 0;

failure:
	pr_info("x86/PAT: %s:%d conflicting memory types %Lx-%Lx %s<->%s\n",
		current->comm, current->pid, start, end,
		cattr_name(found_type), cattr_name(entry_match->type));

	return -EBUSY;
}
```

Here we can see the error message we got earlier in dmesg: `conflicting memory types xxxxxxx`.

To remove the check, and allocation page anyway with the different caching technique, we just need to remove this check that makes it fail. Here is the modification that makes it work:

```c
    ...
	entry_match = interval_iter_first(&memtype_rbroot, start, end-1);
	if (entry_match == NULL)
		goto success;

	if (entry_match->type != found_type && newtype == NULL)
		goto failure;

	dprintk("Overlap at 0x%Lx-0x%Lx\n", entry_match->start, entry_match->end);
	found_type = entry_match->type;

	// entry_match = interval_iter_next(entry_match, start, end-1);
	// while (entry_match) {
	// 	if (entry_match->type != found_type)
	// 		goto failure;

	// 	entry_match = interval_iter_next(entry_match, start, end-1);
	// }
    ...
```

This removes the check that triggers the error. With the patch, and this kernel, it works perfectly.

We can boot in integrated, switch in compute mode, play some games, switch to VFIO and boot the VM. The VM doesn't seem to have a performance penalty either.

With this, we can have the best of both worlds!

CAUTION: I am daily driving this patched kernel without any problem yet. I cannot guarantee that this is definitely stable! It could cause a kernel panic, driver crashes, and maybe data loss.

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
