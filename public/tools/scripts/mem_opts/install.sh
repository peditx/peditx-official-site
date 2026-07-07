#!/bin/sh
# PeDitXOS - Memory Optimizations
echo "Applying Memory optimizations..."
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=50
echo "Memory optimizations applied."
