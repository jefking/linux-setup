# Swap Optimization for Framework Laptop Development

## Current Issue
Your system is using 642MB of 1GB swap, which means memory pressure. This hurts performance significantly.

## Recommendations:

### Option 1: Increase Swap Size (Recommended)
Since you're getting a new 2TB NVMe SSD, create a larger swap:

```bash
# When setting up new system, create 4GB swap partition
# Or add a swap file:
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Option 2: Optimize Current Swap
```bash
# Reduce swappiness to minimum (already at 10, could go to 1)
echo 'vm.swappiness=1' | sudo tee -a /etc/sysctl.conf

# Use zswap for compressed swap in RAM
echo 'zswap.enabled=1' | sudo tee -a /etc/default/grub
echo 'zswap.compressor=lz4' | sudo tee -a /etc/default/grub
echo 'zswap.max_pool_percent=20' | sudo tee -a /etc/default/grub
sudo update-grub
```

### Option 3: Monitor and Manage Memory Usage
```bash
# Kill memory hogs automatically
echo "# Kill Firefox if using >8GB RAM
*/5 * * * * /home/jef/bin/memory-monitor.sh" | crontab -
```

## Why Not Disable Swap?
**DON'T disable swap completely** because:
- Linux kernel needs swap for optimal memory management
- Without swap, OOM killer becomes aggressive
- Docker containers may fail under memory pressure
- Better to have slow swap than sudden crashes

## Ideal Configuration for Development:
- **4GB swap** on NVMe SSD
- **swappiness=1** (use swap only when absolutely necessary)
- **zswap enabled** (compress in RAM before going to disk)
- **Memory monitoring** to catch runaway processes