#!/bin/sh
# Discover the /dev/input/eventX for the gpio_keys device
for sysdev in /sys/class/input/event*/device; do
    name=$(cat "$sysdev/name" 2>/dev/null)
    if [ "$name" = "gpio_keys" ]; then
        echo "/dev/input/$(basename "$(dirname "$sysdev")")"
        exit 0
    fi
done
echo "ERROR: gpio_keys input device not found" >&2
exit 1
