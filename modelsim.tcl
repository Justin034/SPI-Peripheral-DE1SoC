# -----------------------------------------------------------------------------
# modelsim.tcl  -  compile and run the SPI register-file testbenches in ModelSim
#
# In the ModelSim GUI (Transcript window):
#   cd <path to spi_register_file_peripheral>
#   do modelsim.tcl                  compile everything, list the commands
#
#   run_tb tb_spi_top                run one testbench, waves in the Wave window
#   run_tb tb_spi_top +SCLK_MHZ=9    extra plusargs go to the simulation
#   run_all                          run every testbench, print PASS/FAIL summary
#   compile                          recompile after editing RTL or testbenches
#
# Batch mode (no GUI), e.g. from a Linux shell:
#   vsim -c -do "do modelsim.tcl; run_all; quit -f"
#
# Library: build/work (no modelsim.ini is created in the project).
# -----------------------------------------------------------------------------

# Project root = the directory this script lives in.
set ::PROJ [file dirname [file normalize [info script]]]
cd $::PROJ
set ::LIB build/work

# Compile order matters: the package must come first.
set ::RTL {
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
}

set ::TBS {
    tb_shift_reg
    tb_sync_2ff
    tb_edge_detect
    tb_bit_counter
    tb_hex7seg
    tb_spi_master
    tb_spi_top
}

# ---- compile: RTL + all testbenches into build/work -------------------------
proc compile {} {
    file mkdir build
    if {![file exists $::LIB]} {
        vlib $::LIB
    }
    set files $::RTL
    foreach tb $::TBS {
        lappend files tb/$tb.sv
    }
    # -timescale applies only to files without their own `timescale (the RTL),
    # so every module ends up with the same 1ns/1ps units.
    if {[catch {vlog -sv -work $::LIB -timescale 1ns/1ps {*}$files} msg]} {
        echo "COMPILE FAILED - see the messages above"
        return -code error $msg
    }
    echo "Compiled [llength $::RTL] RTL files and [llength $::TBS] testbenches into $::LIB"
}

# ---- load one testbench (internal) ------------------------------------------
# -voptargs=+acc keeps every signal visible for the Wave window and examine.
# -onfinish stop makes $finish stop the run instead of closing the simulation,
# so the waves stay open and the result can be read afterwards.
proc load_tb {tb plusargs} {
    if {[lsearch -exact $::TBS $tb] < 0} {
        return -code error "Unknown testbench '$tb'. Choose from: $::TBS"
    }
    quit -sim
    vsim -lib $::LIB -voptargs=+acc -onfinish stop -wlf build/$tb.wlf $tb {*}$plusargs
}

# Every testbench counts failed checks in an `int errors` at the top level.
proc tb_errors {tb} {
    return [string trim [examine -radix decimal /$tb/errors]]
}

# ---- run_tb: one testbench with waveforms -----------------------------------
proc run_tb {tb args} {
    load_tb $tb $args
    if {![batch_mode]} {
        log -r /*                    ;# record every signal, so any can be added later
        add wave -r /$tb/*
    }
    run -all
    if {![batch_mode]} {
        wave zoom full
    }
    set e [tb_errors $tb]
    if {$e == 0} {
        echo "RESULT: $tb PASSED"
    } else {
        echo "RESULT: $tb FAILED ($e error(s))"
    }
}

# ---- run_all: every testbench, no waves, summary at the end -----------------
proc run_all {} {
    set failed {}
    foreach tb $::TBS {
        echo "==== $tb ===="
        load_tb $tb {}
        run -all
        set e [tb_errors $tb]
        if {$e != 0} {
            lappend failed "$tb ($e)"
        }
    }
    quit -sim
    echo "==== summary ===="
    if {[llength $failed] == 0} {
        echo "ALL PASSED ([llength $::TBS] testbenches)"
    } else {
        echo "FAILED: [join $failed {, }]"
    }
}

# ---- on load: compile and show the commands ---------------------------------
compile
echo ""
echo "Commands:"
echo "  run_tb <tb> \[+ARGS\]   run one testbench with waves  (e.g. run_tb tb_spi_top +SCLK_MHZ=8)"
echo "  run_all               run all testbenches, print a summary"
echo "  compile               recompile after editing files"
echo "Testbenches: $::TBS"
