#!/bin/sh

[ -e "/tmp/5g_band_patch.log" ] && exit 0

HOOK_SRC="/data/custom/hooks/99-set-5g-bands"
HOOK_DEST="/etc/hotplug.d/iface/99-set-5g-bands"

[ -x "$HOOK_SRC" ] || chmod 755 "$HOOK_SRC"

mkdir -p /etc/hotplug.d/iface

if [ ! -e "$HOOK_DEST" ] || [ ! -f "$HOOK_DEST" ]; then
    ln -sf "$HOOK_SRC" "$HOOK_DEST"
fi

echo "5g band hook installed" > /tmp/5g_band_patch.log