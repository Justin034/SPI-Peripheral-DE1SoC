#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_tests.sh  -  lint, simulate and synthesize the SPI register-file design
#
# Usage:
#   ./run_tests.sh lint              Verilator lint of the full design
#   ./run_tests.sh unit [name]       Unit testbench(es): all, or one of
#                                    shift_reg sync_2ff edge_detect bit_counter hex7seg
#   ./run_tests.sh master            SPI master model check (tb_spi_master)
#   ./run_tests.sh top               System testbench (tb_spi_top)
#   ./run_tests.sh sweep [MHz ...]   Run tb_spi_top at several SCLK speeds to
#                                    find the simulated limit (default 1-12 MHz)
#   ./run_tests.sh synth             Yosys synthesis check (latches, cell count)
#   ./run_tests.sh waves <tb_name> [+ARGS]
#                                    Run that testbench with +WAVES, then open
#                                    build/<tb_name>.vcd in GTKWave
#                                    (e.g. waves tb_spi_top +SCLK_MHZ=8)
#   ./run_tests.sh all               lint + unit + top + synth
#   ./run_tests.sh clean             Delete the build/ directory
#
# Simulator: Icarus by default. Use Verilator with:
#   SIM=verilator ./run_tests.sh unit
#
# Waveforms: each testbench writes build/<tb_name>.vcd only when run with
# +WAVES, so normal runs and sweeps stay fast. A new testbench needs:
#   initial if ($test$plusargs("WAVES")) begin
#       $dumpfile("build/<tb_name>.vcd"); $dumpvars(0, <tb_name>);
#   end
# -----------------------------------------------------------------------------
set -u

cd "$(dirname "$0")"            # always run from the project root
BUILD=build
SIM="${SIM:-icarus}"

# Compile order matters: the package must come first.
RTL=(
    rtl/spi_pkg.sv
    rtl/sync_2ff.sv
    rtl/edge_detect.sv
    rtl/shift_reg.sv
    rtl/tx_shift_reg.sv
    rtl/bit_counter.sv
    rtl/hex7seg.sv
    rtl/reg_file.sv
    rtl/spi_slave.sv
    rtl/spi_top.sv
)

UNITS=(shift_reg sync_2ff edge_detect bit_counter hex7seg)

FAILED=()

# Extra run-time arguments passed to every simulation (e.g. +WAVES).
RUN_ARGS=()

# ---- Helpers -----------------------------------------------------------------

banner() { printf '\n==== %s ====\n' "$1"; }

# Run a simulation and record PASS/FAIL from the testbench's summary line.
#   $1 = testbench name, remaining args = source files
simulate() {
    local tb=$1; shift
    local log="$BUILD/$tb.log"

    banner "$tb ($SIM)"

    if [[ "$SIM" == "verilator" ]]; then
        verilator --binary --timing --trace -Wno-fatal \
            --top-module "$tb" -Mdir "$BUILD/obj_$tb" "$@" \
            > "$BUILD/$tb.build.log" 2>&1 \
            || { cat "$BUILD/$tb.build.log"; echo "BUILD FAILED: $tb"; FAILED+=("$tb"); return; }
        "./$BUILD/obj_$tb/V$tb" "${RUN_ARGS[@]}" | tee "$log"
    else
        iverilog -g2012 -o "$BUILD/$tb.vvp" "$@" \
            || { echo "BUILD FAILED: $tb"; FAILED+=("$tb"); return; }
        vvp -n "$BUILD/$tb.vvp" "${RUN_ARGS[@]}" | tee "$log"
    fi

    # A run only counts as passing if the testbench printed its PASS line.
    if ! grep -q "^PASS: $tb" "$log"; then
        FAILED+=("$tb")
    fi
}

# ---- Commands ----------------------------------------------------------------

do_lint() {
    banner "lint (verilator)"
    verilator --lint-only -Wall --top-module spi_top "${RTL[@]}" \
        || FAILED+=("lint")
}

do_unit() {
    local list=("$@")
    [[ ${#list[@]} -eq 0 ]] && list=("${UNITS[@]}")
    for u in "${list[@]}"; do
        if [[ ! -f "rtl/$u.sv" || ! -f "tb/tb_$u.sv" ]]; then
            echo "Unknown unit '$u' (expected rtl/$u.sv and tb/tb_$u.sv)"
            FAILED+=("$u")
            continue
        fi
        simulate "tb_$u" "rtl/$u.sv" "tb/tb_$u.sv"
    done
}

do_master() {
    simulate tb_spi_master tb/tb_spi_master.sv
}

do_top() {
    simulate tb_spi_top "${RTL[@]}" tb/tb_spi_top.sv
}

# Run tb_spi_top at several SCLK frequencies to find the simulated limit.
# Compiles once, then passes +SCLK_MHZ=<f> to each run.
#   $@ = optional list of frequencies in MHz (default list below)
do_sweep() {
    local freqs=("$@")
    [[ ${#freqs[@]} -eq 0 ]] && freqs=(1 2 3 4 5 6 7 8 9 10 12)

    banner "SCLK sweep ($SIM)"

    # ---- Compile once ----
    local run
    if [[ "$SIM" == "verilator" ]]; then
        verilator --binary --timing -Wno-fatal \
            --top-module tb_spi_top -Mdir "$BUILD/obj_sweep" \
            "${RTL[@]}" tb/tb_spi_top.sv > "$BUILD/sweep.build.log" 2>&1 \
            || { cat "$BUILD/sweep.build.log"; echo "BUILD FAILED"; FAILED+=("sweep"); return; }
        run=("./$BUILD/obj_sweep/Vtb_spi_top")
    else
        iverilog -g2012 -o "$BUILD/sweep.vvp" "${RTL[@]}" tb/tb_spi_top.sv \
            || { echo "BUILD FAILED"; FAILED+=("sweep"); return; }
        run=(vvp -n "$BUILD/sweep.vvp")
    fi

    # ---- Run each frequency ----
    local f log result first_fail errs
    local last_pass="none"
    first_fail=""

    printf '\n%10s  %-6s  %s\n' "SCLK (MHz)" "Result" "First failure"
    printf '%10s  %-6s  %s\n'   "----------" "------" "-------------"

    for f in "${freqs[@]}"; do
        log="$BUILD/sweep_${f}MHz.log"
        "${run[@]}" "+SCLK_MHZ=$f" > "$log" 2>&1

        if grep -q "^PASS: tb_spi_top" "$log"; then
            result="PASS"
            [[ -z "$first_fail" ]] && last_pass=$f
            printf '%10s  %-6s\n' "$f" "$result"
        else
            result="FAIL"
            [[ -z "$first_fail" ]] && first_fail=$f
            errs=$(grep -m1 "^FAIL:" "$log" | cut -c1-70)
            printf '%10s  %-6s  %s\n' "$f" "$result" "${errs:-no summary line (see $log)}"
        fi
    done

    # ---- Summary ----
    echo
    echo "Highest passing SCLK before the first failure: $last_pass MHz"
    if [[ -n "$first_fail" ]]; then
        echo "First failing SCLK: $first_fail MHz  (full log: $BUILD/sweep_${first_fail}MHz.log)"
        echo "Refine with e.g.:  $0 sweep $last_pass ... $first_fail"
    else
        echo "No failures in this range - try higher frequencies."
    fi
    # Failures are the expected result of a sweep, so they don't fail the script.
}

do_synth() {
    banner "synth (yosys)"
    local log="$BUILD/yosys.log"
    yosys -q -l "$log" -p "read_verilog -sv ${RTL[*]}; synth -top spi_top; check; stat" \
        || { echo "YOSYS FAILED - see $log"; FAILED+=("synth"); return; }

    # Print the resource summary
    sed -n '/Printing statistics/,$p' "$log"

    # Yosys prints "No latch inferred for ..." for every clean always_comb
    # (good news) and "Latch inferred for signal ..." only for a REAL latch.
    # The search is case-sensitive on purpose, so only real latches match.
    if grep -q "Latch inferred for signal" "$log"; then
        echo "ERROR: latch inferred:"
        grep "Latch inferred for signal" "$log"
        FAILED+=("synth-latch")
    else
        echo "No latches inferred."
    fi
}

# Run one testbench with +WAVES (so it writes build/<tb>.vcd), then open GTKWave.
# Any extra arguments go to the simulation, e.g. waves tb_spi_top +SCLK_MHZ=8
do_waves() {
    local tb=${1:-}
    [[ -z "$tb" ]] && { echo "Usage: $0 waves <tb_name> [+ARGS]   e.g. $0 waves tb_bit_counter"; exit 1; }
    shift
    tb=${tb%.sv}; tb=${tb#tb/}                 # accept tb/tb_x.sv as well as tb_x

    local vcd="$BUILD/$tb.vcd"
    rm -f "$vcd"                               # never show a stale waveform
    RUN_ARGS=(+WAVES "$@")

    case "$tb" in
        tb_spi_top)    do_top ;;
        tb_spi_master) do_master ;;
        tb_*)          do_unit "${tb#tb_}" ;;
        *)             echo "Unknown testbench '$tb' (expected tb_<name>)"; exit 1 ;;
    esac

    [[ -f "$vcd" ]] || { echo "Simulation did not write $vcd"; exit 1; }
    [[ ${#FAILED[@]} -ne 0 ]] && echo "NOTE: $tb failed - opening the waveform anyway to debug it."
    echo "Opening $vcd in GTKWave"
    gtkwave "$vcd" > /dev/null 2>&1 &
}

summary() {
    banner "summary"
    if [[ ${#FAILED[@]} -eq 0 ]]; then
        echo "ALL PASSED"
        exit 0
    else
        echo "FAILED: ${FAILED[*]}"
        exit 1
    fi
}

# ---- Main --------------------------------------------------------------------

mkdir -p "$BUILD"

cmd=${1:-help}
shift || true

case "$cmd" in
    lint)  do_lint;        summary ;;
    unit)  do_unit "$@";   summary ;;
    master) do_master;     summary ;;
    sweep) do_sweep "$@";  summary ;;
    top)   do_top;         summary ;;
    synth) do_synth;       summary ;;
    waves) do_waves "$@" ;;
    all)   do_lint; do_unit; do_master; do_top; do_synth; summary ;;
    clean) rm -rf "$BUILD"; echo "Removed $BUILD/" ;;
    *)     sed -n '3,/^# ---/p' "$0" ;;    # print the usage block above
esac
