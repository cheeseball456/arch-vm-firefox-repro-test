# arch-vm-firefox-repro-test
Pinned Arch Linux VM installer scripts for isolating the GPU as a variable when reproducing possible driver bugs by passing through different cards into an identical, version-locked guest.

## Details
Aims to provide reproducibility for bugs [Firefox](https://bugzilla.mozilla.org/show_bug.cgi?id=2063860) and [Mesa](https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16102), in which a driver crash causes a complete system freeze when triggered via Firefox on Wayland but remains contained via Firefox on XWayland and Chromium on Wayland
