# arch-vm-firefox-repro-test
Pinned Arch Linux VM installer scripts for isolating the GPU as a variable when reproducing possible driver bugs by passing through different cards into an identical, version-locked guest.

## Details
Aims to provide reproducibility for bugs [Firefox](https://bugzilla.mozilla.org/show_bug.cgi?id=2063860) and [Mesa](https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16102), in which a driver crash causes a complete system freeze when triggered via Firefox on Wayland but remains contained via Firefox on XWayland and Chromium on Wayland

## Guest Set Up
1) Configure VM with minimum 4GB of RAM.
2) Mount and boot [arch installation meda](https://archive.archlinux.org/iso/2026.06.01/)
3) Run: ```curl -O https://raw.githubusercontent.com/cheeseball456/arch-vm-firefox-repro-test/refs/heads/main/install.sh; bash install.sh ```
4) Set root password, user name, and user password when prompted.
5) Reboot into installed system as root.
6) Clone the repo: ```git clone https://github.com/cheeseball456/arch-vm-firefox-repro-test``` and ```cd``` into it.
7) Run: ```bash kernels.sh; bash packages.sh``` to install kernel entries and pinned packages. 
8) Copy repo to ```$home``` of user and reboot or reboot and clone repo again.
9) Open ```crash.html``` in Firefox
