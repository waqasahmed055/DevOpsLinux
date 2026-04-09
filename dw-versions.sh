#!/usr/bin/env bash
# =============================================================================
#  Tool Version Checker
#  Platform : Oracle Linux 8.x (OCI)
#  Author   : Systems Team
#  Version  : 1.0.0
# =============================================================================

set -euo pipefail

# ─── Colour Palette ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Globals ─────────────────────────────────────────────────────────────────
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
OS_PRETTY=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Unknown OS}" || echo "Unknown OS")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
REPORT_FILE=""
FAILED_TOOLS=()
FOUND_TOOLS=()

# ─── Helpers ─────────────────────────────────────────────────────────────────
# Print a banner line
banner() {
    local char="${1:--}" len=70
    printf '%0.s'"${char}" $(seq 1 $len)
    echo
}

# Write output to terminal (and optionally file)
output() { echo -e "$*"; }

# Determine if colours should be suppressed (e.g. piped output)
[[ -t 1 ]] || { RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''; }

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check installed tool versions on Oracle Linux / OCI.

Options:
  -o, --output FILE    Save a plain-text report to FILE
  -j, --json           Print results as JSON
  -q, --quiet          Only show found/not-found summary
  -h, --help           Show this help message

EOF
    exit 0
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
JSON_MODE=false
QUIET_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)    REPORT_FILE="${2:?"--output requires a filename"}"; shift 2 ;;
        -j|--json)      JSON_MODE=true; shift ;;
        -q|--quiet)     QUIET_MODE=true; shift ;;
        -h|--help)      usage ;;
        *)              echo "Unknown option: $1" >&2; usage ;;
    esac
done

# ─── Version Extraction Functions ────────────────────────────────────────────

get_rabbitmq_version() {
    local ver="" method=""

    # Method 1: rabbitmqctl status (preferred — accurate for running instances)
    if command -v rabbitmqctl &>/dev/null; then
        ver=$(rabbitmqctl status 2>/dev/null \
              | grep -Eo 'RabbitMQ[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[^,)]*' \
              | head -1 | awk '{print $2}')
        [[ -n "$ver" ]] && { echo "$ver (via rabbitmqctl status)"; return 0; }

        # Method 2: rabbitmqctl version
        ver=$(rabbitmqctl version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1)
        [[ -n "$ver" ]] && { echo "$ver (via rabbitmqctl version)"; return 0; }
    fi

    # Method 3: rabbitmq-server --version
    if command -v rabbitmq-server &>/dev/null; then
        ver=$(rabbitmq-server --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1)
        [[ -n "$ver" ]] && { echo "$ver (via rabbitmq-server --version)"; return 0; }
    fi

    # Method 4: RPM package database
    ver=$(rpm -q rabbitmq-server 2>/dev/null \
          | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+[^-]*' | head -1)
    [[ -n "$ver" ]] && { echo "$ver (via RPM)"; return 0; }

    # Method 5: systemd unit file path for version hint
    local unit; unit=$(systemctl show rabbitmq-server.service 2>/dev/null \
                        | grep -oP '(?<=ExecStart=)[^ ]+' | head -1)
    if [[ -n "$unit" && -f "$unit" ]]; then
        ver=$(strings "$unit" 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [[ -n "$ver" ]] && { echo "$ver (via binary strings)"; return 0; }
    fi

    return 1
}

get_java_version() {
    local ver="" method=""

    # Method 1: java -version (OpenJDK)
    if command -v java &>/dev/null; then
        ver=$(java -version 2>&1 | head -1 \
              | grep -Eo 'openjdk version "[^"]*"' \
              | sed 's/openjdk version "//;s/"//')
        [[ -z "$ver" ]] && ver=$(java -version 2>&1 | head -1 \
                                 | grep -Eo '"[^"]*"' | tr -d '"')
        local edition; edition=$(java -version 2>&1 | head -1 \
                                 | grep -ioP 'openjdk|java' | head -1)
        [[ -n "$ver" ]] && { echo "${edition:-OpenJDK} $ver ($(java -version 2>&1 | sed -n '3p' | grep -oP '(?<=\()[^)]+'))"; return 0; }
    fi

    # Method 2: alternatives --display java
    if command -v alternatives &>/dev/null; then
        ver=$(alternatives --display java 2>/dev/null \
              | grep -Eo 'jvm-openjdk-[0-9]+' | head -1 | grep -Eo '[0-9]+')
        [[ -n "$ver" ]] && { echo "OpenJDK $ver (via alternatives)"; return 0; }
    fi

    # Method 3: RPM – find all installed java/openjdk packages
    ver=$(rpm -qa 2>/dev/null | grep -iE '^java-[0-9]+-openjdk-[0-9]' \
          | grep -Ev 'devel|headless|src|javadoc|debug' \
          | head -1)
    [[ -n "$ver" ]] && { echo "$ver (via RPM)"; return 0; }

    return 1
}

get_openssl_version() {
    local ver=""

    # Method 1: openssl version
    if command -v openssl &>/dev/null; then
        ver=$(openssl version 2>/dev/null)
        [[ -n "$ver" ]] && { echo "$ver"; return 0; }
    fi

    # Method 2: RPM
    ver=$(rpm -q openssl 2>/dev/null | head -1)
    [[ -n "$ver" ]] && { echo "$ver (via RPM)"; return 0; }

    return 1
}

get_fop_version() {
    local ver=""

    # Method 1: fop command
    if command -v fop &>/dev/null; then
        ver=$(fop -version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        [[ -n "$ver" ]] && { echo "Apache FOP $ver ($(command -v fop))"; return 0; }
    fi

    # Method 2: common install paths
    local fop_dirs=(/opt/fop /usr/local/fop /opt/apache-fop*)
    for d in "${fop_dirs[@]}"; do
        [[ -x "$d/fop" ]] || continue
        ver=$("$d/fop" -version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        [[ -n "$ver" ]] && { echo "Apache FOP $ver ($d/fop)"; return 0; }
    done

    # Method 3: locate fop JAR and read MANIFEST
    local fop_jar
    fop_jar=$(find /opt /usr /var /home -name 'fop-*.jar' -o -name 'fop.jar' \
               2>/dev/null | head -1)
    if [[ -n "$fop_jar" ]]; then
        ver=$(unzip -p "$fop_jar" META-INF/MANIFEST.MF 2>/dev/null \
              | grep -i 'Implementation-Version' | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        [[ -n "$ver" ]] && { echo "Apache FOP $ver (via JAR: $fop_jar)"; return 0; }
    fi

    # Method 4: RPM
    ver=$(rpm -qa 2>/dev/null | grep -i fop | head -1)
    [[ -n "$ver" ]] && { echo "$ver (via RPM)"; return 0; }

    return 1
}

get_gcc_version() {
    local ver=""

    # Method 1: gcc --version
    if command -v gcc &>/dev/null; then
        ver=$(gcc --version 2>/dev/null | head -1)
        [[ -n "$ver" ]] && { echo "$ver ($(command -v gcc))"; return 0; }
    fi

    # Method 2: check SCL / module-loaded gcc variants (gcc-toolset-*)
    local scl_gcc
    scl_gcc=$(find /opt/rh -name gcc -type f 2>/dev/null | head -1)
    if [[ -n "$scl_gcc" ]]; then
        ver=$("$scl_gcc" --version 2>/dev/null | head -1)
        [[ -n "$ver" ]] && { echo "$ver ($scl_gcc)"; return 0; }
    fi

    # Method 3: RPM
    ver=$(rpm -qa 2>/dev/null | grep -E '^gcc-[0-9]' | head -1)
    [[ -n "$ver" ]] && { echo "$ver (via RPM, binary not in PATH)"; return 0; }

    return 1
}

get_perl_version() {
    local ver=""

    # Method 1: perl -V:version
    if command -v perl &>/dev/null; then
        ver=$(perl -e 'print $^V' 2>/dev/null | tr -d 'v')
        local full; full=$(perl -V:version 2>/dev/null | grep -Eo "'[^']+'" | tr -d "'")
        [[ -n "$full" ]] && { echo "Perl $full ($(command -v perl))"; return 0; }
        [[ -n "$ver"  ]] && { echo "Perl $ver ($(command -v perl))"; return 0; }
    fi

    # Method 2: RPM
    ver=$(rpm -q perl 2>/dev/null | head -1)
    [[ -n "$ver" ]] && { echo "$ver (via RPM)"; return 0; }

    return 1
}

# ─── Display Helpers ─────────────────────────────────────────────────────────

print_header() {
    echo
    output "${BOLD}${CYAN}"
    banner '='
    printf '  %-66s  \n' "Tool Version Report"
    banner '='
    output "${RESET}"
    output "  ${DIM}Hostname  :${RESET} ${BOLD}${HOSTNAME_VAL}${RESET}"
    output "  ${DIM}OS        :${RESET} ${OS_PRETTY}"
    output "  ${DIM}Generated :${RESET} ${TIMESTAMP}"
    output "${DIM}"
    banner '-'
    output "${RESET}"
}

print_row() {
    local label="$1" status="$2" info="$3"
    local icon color
    if [[ "$status" == "FOUND" ]]; then
        icon="✔"; color="${GREEN}"
    else
        icon="✘"; color="${RED}"
    fi
    printf "  ${color}${BOLD}[%s] %-18s${RESET}  %s\n" "$icon" "$label" "$info"
}

print_footer() {
    local found=${#FOUND_TOOLS[@]} failed=${#FAILED_TOOLS[@]}
    local total=$(( found + failed ))
    echo
    output "${DIM}"
    banner '-'
    output "${RESET}"
    output "  ${BOLD}Summary:${RESET}  ${GREEN}${found} found${RESET}  /  ${RED}${failed} not found${RESET}  /  ${total} checked"
    if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
        output ""
        output "  ${YELLOW}${BOLD}Not found:${RESET}  ${FAILED_TOOLS[*]}"
        output "  ${DIM}Tip: ensure the packages are installed and their binaries are in \$PATH.${RESET}"
    fi
    output "${DIM}"
    banner '='
    output "${RESET}"
    echo
}

# ─── JSON Output ─────────────────────────────────────────────────────────────

print_json() {
    local -n _results=$1
    echo "{"
    printf '  "hostname": "%s",\n'   "$HOSTNAME_VAL"
    printf '  "os": "%s",\n'         "$OS_PRETTY"
    printf '  "generated": "%s",\n'  "$TIMESTAMP"
    echo  '  "tools": ['
    local keys=("${!_results[@]}")
    local last="${keys[-1]}"
    for tool in "${keys[@]}"; do
        local status="${_results[$tool]%%|*}"
        local version="${_results[$tool]#*|}"
        local comma=","
        [[ "$tool" == "$last" ]] && comma=""
        printf '    {"tool": "%s", "status": "%s", "version": "%s"}%s\n' \
               "$tool" "$status" "$version" "$comma"
    done
    echo  '  ]'
    echo  "}"
}

# ─── Core Check Logic ────────────────────────────────────────────────────────

run_checks() {
    declare -A RESULTS

    # --- Tool definitions: (label, function) ---
    declare -a TOOLS=(
        "RabbitMQ|get_rabbitmq_version"
        "Java OpenJDK|get_java_version"
        "OpenSSL|get_openssl_version"
        "Apache FOP|get_fop_version"
        "GCC Compiler|get_gcc_version"
        "Perl|get_perl_version"
    )

    for entry in "${TOOLS[@]}"; do
        local label="${entry%%|*}"
        local func="${entry##*|}"
        local ver=""

        if ver=$("$func" 2>/dev/null) && [[ -n "$ver" ]]; then
            RESULTS["$label"]="FOUND|$ver"
            FOUND_TOOLS+=("$label")
        else
            RESULTS["$label"]="NOT_FOUND|Not installed or not in PATH"
            FAILED_TOOLS+=("$label")
        fi
    done

    # Output
    if $JSON_MODE; then
        print_json RESULTS
        return
    fi

    if ! $QUIET_MODE; then
        print_header
    fi

    # Maintain defined display order
    local order=("RabbitMQ" "Java OpenJDK" "OpenSSL" "Apache FOP" "GCC Compiler" "Perl")
    for label in "${order[@]}"; do
        local status="${RESULTS[$label]%%|*}"
        local ver_info="${RESULTS[$label]#*|}"
        if ! $QUIET_MODE; then
            print_row "$label" "$status" "$ver_info"
        fi
    done

    if ! $QUIET_MODE; then
        print_footer
    else
        # Quiet mode: minimal output
        for label in "${order[@]}"; do
            local status="${RESULTS[$label]%%|*}"
            local ver_info="${RESULTS[$label]#*|}"
            printf "%-18s  [%s]  %s\n" "$label" "$status" "$ver_info"
        done
    fi

    # Write report file if requested
    if [[ -n "$REPORT_FILE" ]]; then
        {
            echo "Tool Version Report"
            echo "Hostname  : ${HOSTNAME_VAL}"
            echo "OS        : ${OS_PRETTY}"
            echo "Generated : ${TIMESTAMP}"
            echo "$(printf '%0.s-' {1..70})"
            for label in "${order[@]}"; do
                local status="${RESULTS[$label]%%|*}"
                local ver_info="${RESULTS[$label]#*|}"
                printf "%-18s  [%s]  %s\n" "$label" "$status" "$ver_info"
            done
            echo "$(printf '%0.s-' {1..70})"
            echo "Found: ${#FOUND_TOOLS[@]}  /  Not found: ${#FAILED_TOOLS[@]}  /  Total: $(( ${#FOUND_TOOLS[@]} + ${#FAILED_TOOLS[@]} ))"
        } > "$REPORT_FILE"
        output "\n  ${DIM}Report saved to:${RESET} ${BOLD}${REPORT_FILE}${RESET}\n"
    fi
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
run_checks
