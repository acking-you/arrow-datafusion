# Memory Allocator and Profiling Guide

This guide explains how to use different memory allocators and enable jemalloc profiling in the ClickBench benchmarks.

## Memory Allocators

The benchmark binary supports four different memory allocators that can be selected at compile time via Cargo features:

### Available Allocators

1. **jemalloc** (default) - High-performance allocator with profiling support
2. **mimalloc** - Microsoft's fast allocator
3. **snmalloc** - Secure allocator from Microsoft Research
4. **system** - System default allocator (glibc malloc on Linux)

### Selecting an Allocator

Use the `ALLOCATOR` environment variable to choose an allocator:

```bash
# Use jemalloc (default)
./clickbench.sh run clickbench_1

# Use mimalloc
ALLOCATOR=mimalloc ./clickbench.sh run clickbench_1

# Use snmalloc
ALLOCATOR=snmalloc ./clickbench.sh run clickbench_1

# Use system allocator
ALLOCATOR=system ./clickbench.sh run clickbench_1
```

## Jemalloc Profiling

When using jemalloc, you can enable heap profiling to analyze memory allocation patterns.

### Setup

First, install the jemalloc-utils submodule:

```bash
./clickbench.sh setup_jemalloc_utils
```

This will clone the [jemalloc-utils](https://github.com/acking-you/jemalloc-utils.git) repository into the `benchmarks/jemalloc-utils` directory.

### Basic Profiling

Enable profiling with the `JEMALLOC_PROFILE` environment variable:

```bash
# Run with profiling enabled (dump on exit only)
JEMALLOC_PROFILE=1 ./clickbench.sh run clickbench_1
```

This will:
- Automatically build the release binary with debug symbols if not using prebuilt binary
- Run the benchmark with jemalloc profiling enabled via `jemalloc_profile.sh` wrapper
- Generate heap dump files in `./jeprof_output/`
- Print analysis commands after completion

**Note:** When profiling is enabled, the script automatically compiles the binary with the `profiling` profile (optimized with debug symbols) because jeprof requires symbol information to analyze heap dumps.

### Periodic Profiling

To dump profiles periodically during execution (useful for long-running benchmarks):

```bash
# Dump profile every 512MB allocated
JEMALLOC_PROFILE=1 JEMALLOC_PROFILE_INTERVAL=512 ./clickbench.sh run clickbench_1

# Dump profile every 1GB allocated
JEMALLOC_PROFILE=1 JEMALLOC_PROFILE_INTERVAL=1024 ./clickbench.sh run clickbench_partitioned
```

### Custom Profile Output Directory

```bash
# Save profiles to a custom directory
JEMALLOC_PROFILE=1 JEMALLOC_PROFILE_OUTPUT=/tmp/my_profiles ./clickbench.sh run clickbench_1
```

## Analyzing Profiles

After running with profiling enabled, use `jeprof` to analyze the results:

### View Text Summary

```bash
# Show top allocations (cumulative)
jeprof --text target/profiling/dfbench jeprof_output/jeprof.*.heap | head -30

# Show current memory usage (not cumulative)
jeprof --inuse_space --text target/profiling/dfbench jeprof_output/jeprof.*.heap | head -30
```

### Generate Visual Reports

```bash
# Generate PDF call graph
jeprof --pdf --drop_negative target/profiling/dfbench jeprof_output/jeprof.*.heap > profile.pdf

# Generate SVG call graph
jeprof --svg --drop_negative target/profiling/dfbench jeprof_output/jeprof.*.heap > profile.svg

# Interactive web interface
jeprof --web target/profiling/dfbench jeprof_output/jeprof.*.heap
```

### Compare Multiple Profiles

If you used `JEMALLOC_PROFILE_INTERVAL`, you'll have multiple heap dumps:

```bash
# List all heap dumps
ls -lh jeprof_output/jeprof.*.heap

# Compare two specific dumps
jeprof --base=jeprof_output/jeprof.0001.heap --text target/profiling/dfbench jeprof_output/jeprof.0002.heap
```

## Complete Examples

### Run Specific Queries

Run only specific queries instead of all 43 queries (q0-q42):

```bash
# Run a single query
./clickbench.sh run clickbench_1 5

# Run multiple specific queries
QUERIES="0,5,10,15,20" ./clickbench.sh run clickbench_1

# Run a range of queries
QUERIES="0-10" ./clickbench.sh run clickbench_partitioned

# Run mixed specification
QUERIES="0,5,10-15,20-25,42" ./clickbench.sh run clickbench_1
```

### Compare Allocators

Run the same benchmark with different allocators:

```bash
# jemalloc
ALLOCATOR=jemalloc RESULTS_NAME=results_jemalloc ./clickbench.sh run clickbench_1

# mimalloc
ALLOCATOR=mimalloc RESULTS_NAME=results_mimalloc ./clickbench.sh run clickbench_1

# Compare results
./clickbench.sh compare results_jemalloc results_mimalloc
```

### Profile Memory Usage Over Time

```bash
# Run with periodic profiling
JEMALLOC_PROFILE=1 JEMALLOC_PROFILE_INTERVAL=256 ./clickbench.sh run clickbench_partitioned

# Analyze memory growth over time
for heap in jeprof_output/jeprof.*.heap; do
  echo "=== $heap ==="
  jeprof --inuse_space --text target/profiling/dfbench "$heap" | head -10
done
```

### Full Profiling Run with Custom Settings

```bash
ALLOCATOR=jemalloc \
JEMALLOC_PROFILE=1 \
JEMALLOC_PROFILE_OUTPUT=./profiles/clickbench_$(date +%Y%m%d_%H%M%S) \
JEMALLOC_PROFILE_INTERVAL=512 \
RESULTS_NAME=profiled_run \
./clickbench.sh run clickbench_1 5
```

## Troubleshooting

### Profiling Not Working

If profiling doesn't work:

1. Ensure jemalloc-utils is installed:
   ```bash
   ./clickbench.sh setup_jemalloc_utils
   ```

2. Verify you're using the jemalloc allocator:
   ```bash
   echo $ALLOCATOR  # Should be empty or "jemalloc"
   ```

3. Check that jeprof is available:
   ```bash
   which jeprof
   ```

### Install jeprof

If `jeprof` is not installed:

```bash
# On Ubuntu/Debian
sudo apt-get install libjemalloc-dev

# On macOS
brew install jemalloc

# Or use the auto-install in jemalloc_profile.sh
```

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `ALLOCATOR` | `jemalloc` | Memory allocator to use (jemalloc, mimalloc, snmalloc, system) |
| `JEMALLOC_PROFILE` | `0` | Enable jemalloc profiling (set to 1) |
| `JEMALLOC_PROFILE_OUTPUT` | `./jeprof_output` | Directory for profile files |
| `JEMALLOC_PROFILE_INTERVAL` | _(none)_ | Dump profile every N MB allocated |
| `JEMALLOC_UTILS_DIR` | `./jemalloc-utils` | Path to jemalloc-utils directory |
| `QUERIES` | _(all)_ | Queries to run: single ("5"), list ("0,5,10"), range ("0-10"), or mixed ("0,5,10-15,20") |

## Additional Resources

- [jemalloc documentation](http://jemalloc.net/)
- [jeprof usage guide](https://github.com/jemalloc/jemalloc/wiki/Use-Case%3A-Heap-Profiling)
- [jemalloc-utils repository](https://github.com/acking-you/jemalloc-utils)
