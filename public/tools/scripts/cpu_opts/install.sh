#!/bin/sh
# PeDitXOS - CPU Optimizations
echo "Applying CPU optimizations..."
for CPU in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$CPU" ] && echo "performance" > "$CPU"
done
echo "CPU optimizations applied."
