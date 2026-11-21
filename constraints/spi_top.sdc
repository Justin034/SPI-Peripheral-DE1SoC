# -----------------------------------------------------------------------------
# spi_top.sdc  -  Timing constraints for the SPI register-file peripheral
#
# Target: Terasic DE1-SoC (Cyclone V), Quartus Prime Timing Analyzer.
# Add this file to the Quartus project (Project > Add/Remove Files) so the
# Timing Analyzer uses it.
#
# The whole design runs in ONE clock domain (CLOCK_50). Every other input is
# asynchronous to it and enters through a synchronizer, so the only timing
# paths that matter are flip-flop to flip-flop inside the FPGA.
# -----------------------------------------------------------------------------

# ---- 1. The system clock ------------------------------------------------------
# 50 MHz oscillator on the DE1-SoC -> 20 ns period.
# Every register-to-register path is checked against this.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Adds clock jitter / uncertainty margins to the analysis (Intel recommended).
derive_clock_uncertainty

# ---- 2. Asynchronous inputs -----------------------------------------------------
# These have no timing relationship with CLOCK_50:
#   SW[9:0]                       -> sync_2ff (10 bits) in spi_top
#   KEY[3:0]                      -> KEY[0] reset synchronizer (async assert,
#                                    sync de-assert); KEY[3:1] unused
#   spi_sclk, spi_cs_n, spi_mosi  -> sync_2ff (3 bits) in spi_slave
# Each one is handled by a 2-flop synchronizer, so timing paths from the pins
# to the first flop are intentionally not analysed.
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {spi_sclk spi_cs_n spi_mosi}]

# ---- 3. Outputs ---------------------------------------------------------------------
# No timing requirement relative to CLOCK_50:
#   LEDR, HEX0-HEX5 : drive LEDs and displays (human-speed).
#   spi_miso        : sampled by the ESP32 on ITS SCLK edges; its timing is set
#                     by the SPI protocol and the oversampling latency
#                     (see DESIGN.md section 10), not by CLOCK_50 output delay.
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
set_false_path -to [get_ports {spi_miso}]
