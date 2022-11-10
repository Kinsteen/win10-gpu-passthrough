#!/bin/sh

set +x

if [[ -z $SUDO_USER ]]; then
    echo "Script must be run as root with sudo."
    exit 1
fi

if [[ ! -d $1 ]]; then
    echo "You must specify a folder where the Linux kernel is"
    exit 1
fi

folder=$1
cd $folder

if ! grep -q "Linux kernel" README 2>/dev/null; then
    echo "The folder you specified is not a valid Linux kernel"
    exit 1
fi

if patch -p0 -s -f --dry-run < ../pat_patch.diff; then
    read -p "Can apply the PAT patch automatically, do you want to do that? (Y/n)" yn

    case $yn in
        n )
            echo "Not patching."
        ;;
        * )
            sudo -u $SUDO_USER patch -p0 < ../pat_patch.diff
    esac
else
    read -p "Couldn't apply patch. Continue compiling? (y/N)" yn

    case $yn in
        y )

        ;;
        * )
        exit 0
    esac
fi

VERSION=$(grep -m 1 VERSION Makefile | sed 's/^.*= //g')
PATCHLEVEL=$(grep -m 1 PATCHLEVEL Makefile | sed 's/^.*= //g')
SUBLEVEL=$(grep -m 1 SUBLEVEL Makefile | sed 's/^.*= //g')
EXTRAVERSION=$(grep -m 1 EXTRAVERSION Makefile | sed 's/^.*= //g')

version=$VERSION.$PATCHLEVEL.$SUBLEVEL$EXTRAVERSION

if [[ ! -f .config ]]; then
    sudo -u $SUDO_USER zcat /proc/config.gz > .config
    sudo -u $SUDO_USER make olddefconfig
fi

sudo -u $SUDO_USER make -j$(nproc)
sudo -u $SUDO_USER make modules
make modules_install
sudo -u $SUDO_USER make bzImage
cp arch/x86/boot/bzImage /boot/vmlinuz-linux-$version
mkinitcpio -k $version -g /boot/initramfs-linux-$version.img

# DKMS schenanigans

{
modules=$(dkms status|cut -d"," -f1|uniq)
IFS=$'\n'
for module in $modules; do
    dkms remove $module -k $version
    dkms install $module -k $version
done
}

grub-mkconfig -o /boot/grub/grub.cfg
