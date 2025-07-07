#!/bin/bash
# Memory monitoring and optimization script

MEMORY_THRESHOLD=85  # Kill processes if memory usage > 85%
LOG_FILE="$HOME/.memory-monitor.log"

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

check_memory() {
    MEMORY_USAGE=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
    
    if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
        log_message "High memory usage: ${MEMORY_USAGE}%"
        
        # Find memory hogs (exclude system processes)
        MEMORY_HOGS=$(ps aux --sort=-%mem --no-headers | awk '$3 > 5.0 && $1 != "root" {print $2":"$11}' | head -3)
        
        echo "🚨 High memory usage detected: ${MEMORY_USAGE}%"
        echo "Top memory consumers:"
        echo "$MEMORY_HOGS"
        
        # Ask user before killing (if interactive)
        if [ -t 1 ]; then
            echo "Kill memory-heavy processes? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "$MEMORY_HOGS" | while IFS=: read -r pid name; do
                    if [[ "$name" == *"firefox"* ]] || [[ "$name" == *"chrome"* ]]; then
                        echo "Killing $name (PID: $pid)"
                        kill -9 "$pid" 2>/dev/null
                        log_message "Killed $name (PID: $pid)"
                    fi
                done
            fi
        fi
    fi
}

# Drop caches if memory pressure is high
drop_caches() {
    AVAILABLE_MEMORY=$(free -g | awk '/^Mem:/{print $7}')
    if [ "$AVAILABLE_MEMORY" -lt 4 ]; then
        echo "💧 Dropping caches to free memory..."
        sync
        sudo sysctl vm.drop_caches=3
        log_message "Dropped caches, available memory was ${AVAILABLE_MEMORY}GB"
    fi
}

# Main execution
check_memory
drop_caches