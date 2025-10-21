#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# This script is a simplified version of bench.sh focused only on ClickBench benchmarks

# Exit on error
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Emoji definitions (can be disabled by setting NO_EMOJI=1)
if [ -z "$NO_EMOJI" ]; then
    ROCKET="🚀"
    CHECK="✅"
    DOWNLOAD="⬇️"
    RUNNING="⚡"
    DONE="🎉"
    INFO="ℹ️"
    WARNING="⚠️"
    ERROR="❌"
    CHART="📊"
else
    ROCKET="[*]"
    CHECK="[✓]"
    DOWNLOAD="[↓]"
    RUNNING="[>]"
    DONE="[✓]"
    INFO="[i]"
    WARNING="[!]"
    ERROR="[X]"
    CHART="[#]"
fi

# Get script directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Print colored message
print_info() {
    echo -e "${CYAN}${INFO} $1${NC}"
}

print_success() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
}

print_error() {
    echo -e "${RED}${ERROR} $1${NC}"
}

print_header() {
    echo -e "${MAGENTA}${BOLD}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BLUE}${BOLD}▶ $1${NC}"
}

# Execute command and also print it, for debugging purposes
debug_run() {
    echo -e "${CYAN}${RUNNING} Executing: $@${NC}"
    set -x
    "$@"
    set +x
}

# Set Defaults
COMMAND=
BENCHMARK=clickbench_partitioned
DATAFUSION_DIR=${DATAFUSION_DIR:-$SCRIPT_DIR/..}
DATA_DIR=${DATA_DIR:-$SCRIPT_DIR/data}
USE_PREBUILT=${USE_PREBUILT:-0}
ALLOCATOR=${ALLOCATOR:-jemalloc}
JEMALLOC_PROFILE=${JEMALLOC_PROFILE:-0}
JEMALLOC_PROFILE_OUTPUT=${JEMALLOC_PROFILE_OUTPUT:-$SCRIPT_DIR/jeprof_output}
JEMALLOC_PROFILE_INTERVAL=${JEMALLOC_PROFILE_INTERVAL:-}

# Determine binary execution method
if [ "$USE_PREBUILT" = "1" ]; then
    PREBUILT_BIN="${SCRIPT_DIR}/bin/dfbench"
    if [ ! -f "$PREBUILT_BIN" ]; then
        print_error "Prebuilt binary not found at $PREBUILT_BIN"
        print_info "Please upload the binary to ${SCRIPT_DIR}/bin/dfbench"
        exit 1
    fi
    CARGO_COMMAND="$PREBUILT_BIN"
    print_info "Using prebuilt binary: $PREBUILT_BIN"
else
    # Set allocator feature flags
    case "$ALLOCATOR" in
        jemalloc)
            ALLOCATOR_FEATURES="--features jemalloc"
            ;;
        mimalloc)
            ALLOCATOR_FEATURES="--no-default-features --features mimalloc"
            ;;
        snmalloc)
            ALLOCATOR_FEATURES="--no-default-features --features snmalloc"
            ;;
        system)
            ALLOCATOR_FEATURES="--no-default-features"
            ;;
        *)
            print_error "Unknown allocator: $ALLOCATOR"
            print_info "Valid allocators: jemalloc, mimalloc, snmalloc, system"
            exit 1
            ;;
    esac
    CARGO_COMMAND=${CARGO_COMMAND:-"cargo run --release $ALLOCATOR_FEATURES"}
fi

VIRTUAL_ENV=${VIRTUAL_ENV:-$SCRIPT_DIR/venv}
JEMALLOC_UTILS_DIR=${JEMALLOC_UTILS_DIR:-$SCRIPT_DIR/jemalloc-utils}

usage() {
    echo -e "${BOLD}${ROCKET} ClickBench Benchmark Runner for DataFusion${NC}\n"
    echo -e "${BOLD}Usage:${NC}"
    echo "  $0 data [benchmark]"
    echo "  $0 run [benchmark] [query]"
    echo "  $0 compare <branch1> <branch2>"
    echo "  $0 compare_detail <branch1> <branch2>"
    echo "  $0 venv"
    echo "  $0 setup_jemalloc_utils"
    echo ""
    print_header "📝 Examples"
    echo "  # Download ClickBench datasets"
    echo -e "  ${GREEN}./clickbench.sh data${NC}"
    echo ""
    echo "  # Run all ClickBench benchmarks"
    echo -e "  ${GREEN}./clickbench.sh run all${NC}"
    echo ""
    echo "  # Run only the single file benchmark"
    echo -e "  ${GREEN}./clickbench.sh run clickbench_1${NC}"
    echo ""
    echo "  # Run a specific query (e.g., query 5)"
    echo -e "  ${GREEN}./clickbench.sh run clickbench_1 5${NC}"
    echo ""
    echo "  # Run multiple queries (e.g., queries 0,5,10)"
    echo -e "  ${GREEN}QUERIES=\"0,5,10\" ./clickbench.sh run clickbench_1${NC}"
    echo ""
    echo "  # Run a range of queries (e.g., queries 0-10)"
    echo -e "  ${GREEN}QUERIES=\"0-10\" ./clickbench.sh run clickbench_1${NC}"
    echo ""
    echo "  # Run mixed query specification (e.g., queries 0,5,10-15,20)"
    echo -e "  ${GREEN}QUERIES=\"0,5,10-15,20\" ./clickbench.sh run clickbench_1${NC}"
    echo ""
    echo "  # Run with mimalloc allocator"
    echo -e "  ${GREEN}ALLOCATOR=mimalloc ./clickbench.sh run clickbench_1${NC}"
    echo ""
    echo "  # Run with jemalloc profiling enabled"
    echo -e "  ${GREEN}JEMALLOC_PROFILE=1 ./clickbench.sh run clickbench_1${NC}"
    echo ""
    echo "  # Run with jemalloc profiling, dump every 512MB"
    echo -e "  ${GREEN}JEMALLOC_PROFILE=1 JEMALLOC_PROFILE_INTERVAL=512 ./clickbench.sh run clickbench_1${NC}"
    echo ""
    print_header "🎯 Commands"
    echo -e "  ${CYAN}data${NC}                   Downloads ClickBench data needed for benchmarking"
    echo -e "  ${CYAN}run${NC}                    Runs the named benchmark"
    echo -e "  ${CYAN}compare${NC}                Compares fastest results from benchmark runs"
    echo -e "  ${CYAN}compare_detail${NC}         Compares minimum, average (±stddev), and maximum results"
    echo -e "  ${CYAN}venv${NC}                   Creates new venv and installs compare's requirements"
    echo -e "  ${CYAN}setup_jemalloc_utils${NC}   Clones jemalloc-utils as a git submodule"
    echo ""
    print_header "📊 Benchmarks"
    echo -e "  ${YELLOW}clickbench_partitioned (default)${NC}  ClickBench queries against partitioned (100 files) parquet (~14GB)"
    echo -e "  ${YELLOW}clickbench_1${NC}            ClickBench queries against a single parquet file (~14GB)"
    echo -e "  ${YELLOW}clickbench_pushdown${NC}     ClickBench with filter_pushdown enabled"
    echo -e "  ${YELLOW}clickbench_extended${NC}     ClickBench 'inspired' queries (DataFusion specific)"
    echo -e "  ${YELLOW}all${NC}                     Run all ClickBench benchmarks"
    echo ""
    print_header "⚙️  Configuration (Environment Variables)"
    echo "  DATA_DIR                  Directory to store datasets (default: ./data)"
    echo "  USE_PREBUILT              Use prebuilt binary from ./bin/dfbench (default: 0, set to 1 to use)"
    echo "  CARGO_COMMAND             Command that runs the benchmark binary (default: cargo run --release)"
    echo "  DATAFUSION_DIR            DataFusion directory to use (default: parent of script dir)"
    echo "  RESULTS_NAME              Folder where the benchmark files are stored"
    echo "  VENV_PATH                 Python venv to use for compare (default: ./venv)"
    echo "  NO_EMOJI                  Set to 1 to disable emoji output"
    echo "  DATAFUSION_*              Set the given datafusion configuration"
    echo ""
    echo "  ALLOCATOR                 Memory allocator to use (default: jemalloc)"
    echo "                            Options: jemalloc, mimalloc, snmalloc, system"
    echo ""
    echo "  JEMALLOC_PROFILE          Enable jemalloc profiling (default: 0, set to 1 to enable)"
    echo "  JEMALLOC_PROFILE_OUTPUT   Output directory for jemalloc profiles (default: ./jeprof_output)"
    echo "  JEMALLOC_PROFILE_INTERVAL Dump profile every N MB allocated (optional)"
    echo ""
    echo "  QUERIES                   Queries to run (default: all queries 0-42)"
    echo "                            Examples: \"5\" (single), \"0,5,10\" (list),"
    echo "                            \"0-10\" (range), \"0,5,10-15,20\" (mixed)"
    echo ""
    echo -e "${BOLD}${ROCKET} Using Prebuilt Binaries:${NC}"
    echo "  1. Build locally:      ./build_binaries.sh"
    echo "  2. Deploy and run:     REMOTE_USER=user REMOTE_HOST=host ./deploy.sh [benchmark]"
    echo "  3. Or run locally:     USE_PREBUILT=1 ./clickbench.sh run [benchmark]"
    echo ""
    exit 1
}

# Setup jemalloc-utils submodule
setup_jemalloc_utils() {
    print_section "🔧 Setting up jemalloc-utils"

    if [ -d "$JEMALLOC_UTILS_DIR/.git" ]; then
        print_success "jemalloc-utils already exists at $JEMALLOC_UTILS_DIR"
        print_info "Updating jemalloc-utils..."
        pushd "$JEMALLOC_UTILS_DIR" > /dev/null
        git pull
        popd > /dev/null
        print_success "jemalloc-utils updated!"
    else
        print_info "Cloning jemalloc-utils to $JEMALLOC_UTILS_DIR..."
        git clone https://github.com/acking-you/jemalloc-utils.git "$JEMALLOC_UTILS_DIR"
        print_success "jemalloc-utils cloned successfully!"
    fi

    print_info "Making scripts executable..."
    chmod +x "$JEMALLOC_UTILS_DIR"/*.sh
    print_success "Setup complete!"
}

# Wrapper function to run command with optional jemalloc profiling
run_with_profiling() {
    local cmd="$@"

    if [ "$JEMALLOC_PROFILE" = "1" ] && [ "$ALLOCATOR" = "jemalloc" ]; then
        print_info "🔬 Jemalloc profiling enabled"
        print_info "Profile output: $JEMALLOC_PROFILE_OUTPUT"

        # Check if jemalloc_profile.sh exists
        if [ ! -f "$JEMALLOC_UTILS_DIR/jemalloc_profile.sh" ]; then
            print_warning "jemalloc_profile.sh not found!"
            print_info "Run: $0 setup_jemalloc_utils"
            print_info "Continuing without profiling..."
            eval "$cmd"
            return
        fi

        # When profiling is enabled, we need to build the binary first with debug symbols
        # because jemalloc_profile.sh needs an executable binary path and jeprof needs symbols
        if [ "$USE_PREBUILT" != "1" ]; then
            print_info "Building with 'profiling' profile (optimized + debug symbols) for jemalloc profiling..."
            cargo build --profile profiling $ALLOCATOR_FEATURES --bin dfbench
            if [ $? -ne 0 ]; then
                print_error "Build failed!"
                exit 1
            fi

            # Replace cargo run command with direct binary execution
            local binary_path="${DATAFUSION_DIR}/target/profiling/dfbench"
            # Extract arguments from the cargo run command
            # Remove "cargo run --release --features ... --bin dfbench --"
            local args="${cmd#*-- }"
            cmd="$binary_path $args"
            print_info "Using binary: $binary_path"
        fi

        # Build profiling command
        PROFILE_CMD="$JEMALLOC_UTILS_DIR/jemalloc_profile.sh -i 500 -o $JEMALLOC_PROFILE_OUTPUT"
        if [ -n "$JEMALLOC_PROFILE_INTERVAL" ]; then
            PROFILE_CMD="$PROFILE_CMD -i $JEMALLOC_PROFILE_INTERVAL"
            print_info "Profile interval: ${JEMALLOC_PROFILE_INTERVAL}MB"
        fi
        PROFILE_CMD="$PROFILE_CMD -- $cmd"

        print_info "Running with profiling wrapper..."
        eval "$PROFILE_CMD"

        print_success "Profiling complete! Analyze with:"
        if [ "$USE_PREBUILT" = "1" ]; then
            echo -e "  ${CYAN}jeprof --text $PREBUILT_BIN $JEMALLOC_PROFILE_OUTPUT/jeprof.*.heap | head -30${NC}"
            echo -e "  ${CYAN}jeprof --pdf $PREBUILT_BIN $JEMALLOC_PROFILE_OUTPUT/jeprof.*.heap > profile.pdf${NC}"
        else
            echo -e "  ${CYAN}jeprof --text $binary_path $JEMALLOC_PROFILE_OUTPUT/jeprof.*.heap | head -30${NC}"
            echo -e "  ${CYAN}jeprof --pdf $binary_path $JEMALLOC_PROFILE_OUTPUT/jeprof.*.heap > profile.pdf${NC}"
        fi
    else
        eval "$cmd"
    fi
}

# Parse QUERIES environment variable and expand into individual query numbers
# Supports formats:
#   - Single query: "5" -> (5)
#   - Comma-separated list: "0,5,10" -> (0 5 10)
#   - Range: "0-10" -> (0 1 2 3 4 5 6 7 8 9 10)
#   - Mixed: "0,5,10-15,20" -> (0 5 10 11 12 13 14 15 20)
# Returns empty array if QUERIES is not set (run all queries)
parse_queries() {
    local queries_spec="$1"

    if [ -z "$queries_spec" ]; then
        echo ""
        return
    fi

    local result=()
    IFS=',' read -ra parts <<< "$queries_spec"

    for part in "${parts[@]}"; do
        # Trim whitespace
        part=$(echo "$part" | xargs)

        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Range format: start-end
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                result+=($i)
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            # Single number
            result+=($part)
        else
            print_error "Invalid query specification: '$part'"
            print_info "Expected a number or range (e.g., '5' or '0-10')"
            return 1
        fi
    done

    echo "${result[@]}"
}

# Downloads the single file hits.parquet ClickBench dataset
# Creates data in $DATA_DIR/hits.parquet
data_clickbench_1() {
    print_section "${DOWNLOAD} Downloading ClickBench single file dataset"

    pushd "${DATA_DIR}" > /dev/null

    # Avoid downloading if it already exists and is the right size
    OUTPUT_SIZE=$(wc -c hits.parquet 2>/dev/null | awk '{print $1}' || true)
    echo -n "Checking hits.parquet..."
    if test "${OUTPUT_SIZE}" = "14779976446"; then
        echo ""
        print_success "hits.parquet already exists (${OUTPUT_SIZE} bytes / ~14GB)"
    else
        URL="https://datasets.clickhouse.com/hits_compatible/hits.parquet"
        echo ""
        print_info "Downloading ${URL} (~14GB)..."
        print_warning "This may take a while depending on your internet connection"
        wget --continue --progress=bar:force ${URL}
        print_success "Download complete!"
    fi
    popd > /dev/null
}

# Downloads the 100 file partitioned ClickBench dataset
# Creates data in $DATA_DIR/hits_partitioned
data_clickbench_partitioned() {
    MAX_CONCURRENT_DOWNLOADS=10

    print_section "${DOWNLOAD} Downloading ClickBench partitioned dataset (100 files)"

    mkdir -p "${DATA_DIR}/hits_partitioned"
    pushd "${DATA_DIR}/hits_partitioned" > /dev/null

    echo -n "Checking hits_partitioned..."
    OUTPUT_SIZE=$(wc -c -- * 2>/dev/null | tail -n 1 | awk '{print $1}' || true)
    if test "${OUTPUT_SIZE}" = "14737666736"; then
        echo ""
        print_success "hits_partitioned already exists (${OUTPUT_SIZE} bytes / ~14GB)"
    else
        echo ""
        print_info "Downloading 100 partitioned files with ${MAX_CONCURRENT_DOWNLOADS} parallel workers..."
        print_warning "Progress: each dot represents one completed file"
        echo -n "  "
        seq 0 99 | xargs -P${MAX_CONCURRENT_DOWNLOADS} -I{} bash -c 'wget -q --continue https://datasets.clickhouse.com/hits_compatible/athena_partitioned/hits_{}.parquet && echo -n "."'
        echo ""
        print_success "All 100 files downloaded successfully!"
    fi

    popd > /dev/null
}

# Runs the clickbench benchmark with a single large parquet file
run_clickbench_1() {
    print_section "${RUNNING} Running ClickBench (single file) benchmark"

    RESULTS_FILE="${RESULTS_DIR}/clickbench_1.json"
    print_info "Results will be saved to: ${RESULTS_FILE}"

    if [ ! -f "${DATA_DIR}/hits.parquet" ]; then
        print_error "Data file not found! Please run: $0 data clickbench_1"
        exit 1
    fi

    # Determine which queries to run
    local queries_to_run
    if [ -n "$QUERY_ARG" ]; then
        # Single query from command line
        queries_to_run=("$QUERY_ARG")
    elif [ -n "$QUERIES" ]; then
        # Multiple queries from QUERIES env var
        queries_to_run=($(parse_queries "$QUERIES"))
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        # Run all queries
        queries_to_run=("")
    fi

    # Run benchmarks
    for query_num in "${queries_to_run[@]}"; do
        local cmd_query_arg=""
        if [ -n "$query_num" ]; then
            cmd_query_arg="--query $query_num"
            print_info "Running query $query_num..."
        fi

        if [ "$USE_PREBUILT" = "1" ]; then
            run_with_profiling $CARGO_COMMAND clickbench --iterations 5 --path \"${DATA_DIR}/hits.parquet\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/queries\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        else
            run_with_profiling $CARGO_COMMAND --bin dfbench -- clickbench --iterations 5 --path \"${DATA_DIR}/hits.parquet\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/queries\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        fi
    done

    print_success "Benchmark completed! Results saved to ${RESULTS_FILE}"
}

# Runs the clickbench benchmark with the partitioned parquet dataset (100 files)
run_clickbench_partitioned() {
    print_section "${RUNNING} Running ClickBench (100 partitioned files) benchmark"

    RESULTS_FILE="${RESULTS_DIR}/clickbench_partitioned.json"
    print_info "Results will be saved to: ${RESULTS_FILE}"

    if [ ! -d "${DATA_DIR}/hits_partitioned" ] || [ -z "$(ls -A ${DATA_DIR}/hits_partitioned 2>/dev/null)" ]; then
        print_error "Partitioned data not found! Please run: $0 data clickbench_partitioned"
        exit 1
    fi

    # Determine which queries to run
    local queries_to_run
    if [ -n "$QUERY_ARG" ]; then
        queries_to_run=("$QUERY_ARG")
    elif [ -n "$QUERIES" ]; then
        queries_to_run=($(parse_queries "$QUERIES"))
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        queries_to_run=("")
    fi

    # Run benchmarks
    for query_num in "${queries_to_run[@]}"; do
        local cmd_query_arg=""
        if [ -n "$query_num" ]; then
            cmd_query_arg="--query $query_num"
            print_info "Running query $query_num..."
        fi

        if [ "$USE_PREBUILT" = "1" ]; then
            run_with_profiling $CARGO_COMMAND clickbench --iterations 5 --path \"${DATA_DIR}/hits_partitioned\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/queries\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        else
            run_with_profiling $CARGO_COMMAND --bin dfbench -- clickbench --iterations 5 --path \"${DATA_DIR}/hits_partitioned\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/queries\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        fi
    done

    print_success "Benchmark completed! Results saved to ${RESULTS_FILE}"
}

# Runs the clickbench benchmark with the partitioned parquet files and filter_pushdown enabled
run_clickbench_pushdown() {
    print_section "${RUNNING} Running ClickBench (with filter pushdown) benchmark"

    RESULTS_FILE="${RESULTS_DIR}/clickbench_pushdown.json"
    print_info "Results will be saved to: ${RESULTS_FILE}"
    print_info "Filter pushdown and filter reordering enabled"

    if [ ! -d "${DATA_DIR}/hits_partitioned" ] || [ -z "$(ls -A ${DATA_DIR}/hits_partitioned 2>/dev/null)" ]; then
        print_error "Partitioned data not found! Please run: $0 data clickbench_partitioned"
        exit 1
    fi

    # Determine which queries to run
    local queries_to_run
    if [ -n "$QUERY_ARG" ]; then
        queries_to_run=("$QUERY_ARG")
    elif [ -n "$QUERIES" ]; then
        queries_to_run=($(parse_queries "$QUERIES"))
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        queries_to_run=("")
    fi

    # Run benchmarks
    for query_num in "${queries_to_run[@]}"; do
        local cmd_query_arg=""
        if [ -n "$query_num" ]; then
            cmd_query_arg="--query $query_num"
            print_info "Running query $query_num..."
        fi

        if [ "$USE_PREBUILT" = "1" ]; then
            run_with_profiling $CARGO_COMMAND clickbench --pushdown --iterations 5 --path \"${DATA_DIR}/hits_partitioned\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/queries\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        else
            run_with_profiling $CARGO_COMMAND --bin dfbench -- clickbench --pushdown --iterations 5 --path \"${DATA_DIR}/hits_partitioned\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/queries\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        fi
    done

    print_success "Benchmark completed! Results saved to ${RESULTS_FILE}"
}

# Runs the clickbench "extended" benchmark with a single large parquet file
run_clickbench_extended() {
    print_section "${RUNNING} Running ClickBench Extended (DataFusion specific) benchmark"

    RESULTS_FILE="${RESULTS_DIR}/clickbench_extended.json"
    print_info "Results will be saved to: ${RESULTS_FILE}"

    if [ ! -f "${DATA_DIR}/hits.parquet" ]; then
        print_error "Data file not found! Please run: $0 data clickbench_1"
        exit 1
    fi

    # Determine which queries to run
    local queries_to_run
    if [ -n "$QUERY_ARG" ]; then
        queries_to_run=("$QUERY_ARG")
    elif [ -n "$QUERIES" ]; then
        queries_to_run=($(parse_queries "$QUERIES"))
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        queries_to_run=("")
    fi

    # Run benchmarks
    for query_num in "${queries_to_run[@]}"; do
        local cmd_query_arg=""
        if [ -n "$query_num" ]; then
            cmd_query_arg="--query $query_num"
            print_info "Running query $query_num..."
        fi

        if [ "$USE_PREBUILT" = "1" ]; then
            run_with_profiling $CARGO_COMMAND clickbench --iterations 5 --path \"${DATA_DIR}/hits.parquet\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/extended\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        else
            run_with_profiling $CARGO_COMMAND --bin dfbench -- clickbench --iterations 5 --path \"${DATA_DIR}/hits.parquet\" --queries-path \"${SCRIPT_DIR}/queries/clickbench/extended\" -o \"${RESULTS_FILE}\" $cmd_query_arg
        fi
    done

    print_success "Benchmark completed! Results saved to ${RESULTS_FILE}"
}

# Compare benchmark results between two branches
compare_benchmarks() {
    print_section "${CHART} Comparing benchmark results"

    BASE_RESULTS_DIR="${SCRIPT_DIR}/results"
    BRANCH1="$1"
    BRANCH2="$2"
    OPTS="$3"

    if [ -z "$BRANCH1" ] ; then
        print_error "<branch1> not specified"
        print_info "Available branches:"
        ls -1 "${BASE_RESULTS_DIR}"
        exit 1
    fi

    if [ -z "$BRANCH2" ] ; then
        print_error "<branch2> not specified"
        print_info "Available branches:"
        ls -1 "${BASE_RESULTS_DIR}"
        exit 1
    fi

    print_info "Comparing ${BRANCH1} vs ${BRANCH2}"

    FOUND_RESULTS=false
    for RESULTS_FILE1 in "${BASE_RESULTS_DIR}/${BRANCH1}"/clickbench*.json ; do
        BENCH=$(basename "${RESULTS_FILE1}")
        RESULTS_FILE2="${BASE_RESULTS_DIR}/${BRANCH2}/${BENCH}"
        if test -f "${RESULTS_FILE2}" ; then
            FOUND_RESULTS=true
            echo ""
            print_header "${CHART} Benchmark: ${BENCH}"
            PATH=$VIRTUAL_ENV/bin:$PATH python3 "${SCRIPT_DIR}"/compare.py $OPTS "${RESULTS_FILE1}" "${RESULTS_FILE2}"
        else
            print_warning "Skipping ${BENCH} - not found in ${BRANCH2}"
        fi
    done

    if [ "$FOUND_RESULTS" = true ]; then
        echo ""
        print_success "Comparison complete!"
    else
        print_error "No matching benchmark results found for comparison"
        exit 1
    fi
}

# Setup Python virtual environment for comparison scripts
setup_venv() {
    print_section "🐍 Setting up Python virtual environment"

    print_info "Creating virtual environment at: $VIRTUAL_ENV"
    python3 -m venv "$VIRTUAL_ENV"

    print_info "Installing requirements..."
    PATH=$VIRTUAL_ENV/bin:$PATH python3 -m pip install -q -r requirements.txt

    print_success "Virtual environment ready!"
    print_info "Activate with: source $VIRTUAL_ENV/bin/activate"
}

# Parse command line arguments
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            shift
            usage
            ;;
        -*)
            print_error "Unknown option $1"
            echo ""
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"
COMMAND=${1:-"${COMMAND}"}
ARG2=$2
ARG3=$3

# Main command dispatcher
main() {
    case "$COMMAND" in
        data)
            BENCHMARK=${ARG2:-"${BENCHMARK}"}

            print_header "${ROCKET} ClickBench Data Downloader"
            echo -e "  ${BOLD}Command:${NC}    ${COMMAND}"
            echo -e "  ${BOLD}Benchmark:${NC}  ${BENCHMARK}"
            echo -e "  ${BOLD}Data Dir:${NC}   ${DATA_DIR}"
            echo ""

            mkdir -p "${DATA_DIR}"

            case "$BENCHMARK" in
                all)
                    data_clickbench_1
                    data_clickbench_partitioned
                    echo ""
                    print_success "${DONE} All datasets downloaded successfully!"
                    ;;
                clickbench_1)
                    data_clickbench_1
                    echo ""
                    print_success "${DONE} Dataset downloaded successfully!"
                    ;;
                clickbench_partitioned)
                    data_clickbench_partitioned
                    echo ""
                    print_success "${DONE} Dataset downloaded successfully!"
                    ;;
                clickbench_pushdown)
                    print_info "clickbench_pushdown uses the same data as clickbench_partitioned"
                    data_clickbench_partitioned
                    echo ""
                    print_success "${DONE} Dataset downloaded successfully!"
                    ;;
                clickbench_extended)
                    print_info "clickbench_extended uses the same data as clickbench_1"
                    data_clickbench_1
                    echo ""
                    print_success "${DONE} Dataset downloaded successfully!"
                    ;;
                *)
                    print_error "Unknown benchmark '$BENCHMARK' for data generation"
                    echo ""
                    usage
                    ;;
            esac
            ;;
        run)
            BENCHMARK=${ARG2:-"${BENCHMARK}"}
            EXTRA_ARGS=("${POSITIONAL_ARGS[@]:2}")
            QUERY_ARG=${EXTRA_ARGS[0]}

            # Determine what queries will be run for display purposes
            if [ -n "$QUERY_ARG" ]; then
                QUERY_DISPLAY="Query $QUERY_ARG"
            elif [ -n "$QUERIES" ]; then
                QUERY_DISPLAY="Queries: $QUERIES"
            else
                QUERY_DISPLAY="All queries"
            fi

            BRANCH_NAME=$(cd "${DATAFUSION_DIR}" && git rev-parse --abbrev-ref HEAD)
            BRANCH_NAME=${BRANCH_NAME//\//_}
            RESULTS_NAME=${RESULTS_NAME:-"${BRANCH_NAME}"}
            RESULTS_DIR=${RESULTS_DIR:-"$SCRIPT_DIR/results/$RESULTS_NAME"}

            print_header "${ROCKET} ClickBench Benchmark Runner"
            echo -e "  ${BOLD}Command:${NC}         ${COMMAND}"
            echo -e "  ${BOLD}Benchmark:${NC}       ${BENCHMARK}"
            echo -e "  ${BOLD}Query:${NC}           ${QUERY_DISPLAY}"
            echo -e "  ${BOLD}DataFusion Dir:${NC}  ${DATAFUSION_DIR}"
            echo -e "  ${BOLD}Branch:${NC}          ${BRANCH_NAME}"
            echo -e "  ${BOLD}Data Dir:${NC}        ${DATA_DIR}"
            echo -e "  ${BOLD}Results Dir:${NC}     ${RESULTS_DIR}"
            echo -e "  ${BOLD}Allocator:${NC}       ${ALLOCATOR}"
            if [ "$JEMALLOC_PROFILE" = "1" ]; then
                echo -e "  ${BOLD}Build Command:${NC}   cargo build --profile profiling $ALLOCATOR_FEATURES --bin dfbench"
                echo -e "  ${BOLD}Profiling:${NC}       ${GREEN}Enabled${NC}"
                echo -e "  ${BOLD}Profile Output:${NC}  ${JEMALLOC_PROFILE_OUTPUT}"
                if [ -n "$JEMALLOC_PROFILE_INTERVAL" ]; then
                    echo -e "  ${BOLD}Profile Interval:${NC} ${JEMALLOC_PROFILE_INTERVAL}MB"
                fi
            else
                echo -e "  ${BOLD}Cargo Command:${NC}   ${CARGO_COMMAND}"
            fi
            echo ""

            pushd "${DATAFUSION_DIR}/benchmarks" > /dev/null
            mkdir -p "${RESULTS_DIR}"
            mkdir -p "${DATA_DIR}"

            START_TIME=$(date +%s)

            case "$BENCHMARK" in
                all)
                    print_info "Running all ClickBench benchmarks..."
                    run_clickbench_1
                    run_clickbench_partitioned
                    run_clickbench_pushdown
                    run_clickbench_extended
                    ;;
                clickbench_1)
                    run_clickbench_1
                    ;;
                clickbench_partitioned)
                    run_clickbench_partitioned
                    ;;
                clickbench_pushdown)
                    run_clickbench_pushdown
                    ;;
                clickbench_extended)
                    run_clickbench_extended
                    ;;
                *)
                    print_error "Unknown benchmark '$BENCHMARK' for run"
                    echo ""
                    usage
                    ;;
            esac

            END_TIME=$(date +%s)
            DURATION=$((END_TIME - START_TIME))
            MINUTES=$((DURATION / 60))
            SECONDS=$((DURATION % 60))

            popd > /dev/null
            echo ""
            print_success "${DONE} All benchmarks completed in ${MINUTES}m ${SECONDS}s!"
            print_info "Results saved in: ${RESULTS_DIR}"
            ;;
        compare)
            compare_benchmarks "$ARG2" "$ARG3"
            ;;
        compare_detail)
            compare_benchmarks "$ARG2" "$ARG3" "--detailed"
            ;;
        venv)
            setup_venv
            ;;
        setup_jemalloc_utils)
            setup_jemalloc_utils
            ;;
        "")
            usage
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            echo ""
            usage
            ;;
    esac
}

# Start the process
main
