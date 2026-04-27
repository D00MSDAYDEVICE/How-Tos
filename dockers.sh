#!/bin/bash

# Define Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BOLD}--- Disk Usage ---${NC}"
df -h / | grep -v Filesystem
echo ""
echo -e "${BOLD}--- Docker Containers ---${NC}"

# Header: Added more room for Status (30) and moved Ports to last
printf "${BOLD}%-20s %-30s %-15s %-20s${NC}\n" "NAME" "STATUS" "SIZE" "PORTS"

# Get data from docker and loop through it
docker ps -a --size --format "{{.Names}}|{{.Status}}|{{.Ports}}|{{.Size}}" | while read -r line; do
    NAME=$(echo $line | cut -d'|' -f1)
    STATUS=$(echo $line | cut -d'|' -f2)

    # Clean Ports
    PORTS=$(echo $line | cut -d'|' -f3 | sed 's/0.0.0.0://g; s/::://g; s/\/tcp//g; s/\/udp//g; s/,//g')

    # Clean Size
    SIZE=$(echo $line | cut -d'|' -f4 | sed 's/ (virtual.*//')

    # Apply Color based on Status
    if [[ $STATUS == Up* ]]; then
        COLOR=$GREEN
    else
        COLOR=$RED
    fi

    # Print formatted row: Name (20), Status (30), Size (15), Ports (20)
    printf "%-20s ${COLOR}%-30s${NC} %-15s %-20s\n" "$NAME" "$STATUS" "$SIZE" "$PORTS"
done
