#!/bin/bash

# Define Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Parse flags
SHOW_ALL=false
for arg in "$@"; do
    [[ "$arg" == "-all" ]] && SHOW_ALL=true
done

if $SHOW_ALL; then
    echo -e "${BOLD}--- Unique Listening Ports - TCP + UDP (Sorted) ---${NC}"
else
    echo -e "${BOLD}--- Unique Listening Ports - TCP (Sorted) ---${NC}"
fi

printf "${BOLD}%-10s %-10s %-25s %-10s${NC}\n" "PROTO" "PORT" "PROCESS" "PID"

parse_ss() {
    local proto=$1
    local flags=$2
    sudo ss $flags | tail -n +2 | awk -v proto="$proto" '{
        split($4, addr, ":");
        port = addr[length(addr)];

        split($6, proc_parts, "\"");
        process = proc_parts[2];
        match($6, /pid=[0-9]+/);
        pid = substr($6, RSTART+4, RLENGTH-4);

        if (process == "") process = "unknown";
        if (pid == "") pid = "-";

        print proto, port, process, pid;
    }'
}

# Always collect TCP; add UDP if -all
{
    parse_ss "tcp" "-ltnp"
    $SHOW_ALL && parse_ss "udp" "-lunp"
} | sort -k2 -n | awk '!seen[$2,$3,$4]++' | while read -r PROTO PORT PROCESS PID; do
    printf "%-10s ${GREEN}%-10s${NC} ${CYAN}%-25s${NC} ${YELLOW}%-10s${NC}\n" \
        "$PROTO" "$PORT" "$PROCESS" "$PID"
done
