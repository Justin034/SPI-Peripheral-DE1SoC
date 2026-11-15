// -----------------------------------------------------------------------------
// tb_spi_top.sv  -  system-level self-checking testbench
//
// Drives spi_top exactly like the ESP32 will: SPI frames on the four spi_* pins.
// Also drives the switches and checks the LEDs / 7-segment outputs, so the
// whole path (pins -> synchronizers -> FSM -> register file -> board I/O) is
// tested together.
//
// SCLK frequency defaults to 1 MHz. Override at run time to find the limit:
//   vvp -n build/tb_spi_top.vvp +SCLK_MHZ=4
//   ./build/obj_tb_spi_top/Vtb_spi_top +SCLK_MHZ=4
// (implementation A is expected to work up to roughly 6 MHz)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_spi_top;

    import spi_pkg::*;

    // ---- Parameters ----------------------------------------------------------
    localparam int CLK_PER  = 20;        // 50 MHz system clock
    localparam int N_STRESS = 200;       // random transactions in test 12

    real sclk_mhz = 1.0;                 // set by +SCLK_MHZ=<value>
    real t_half;                         // half an SCLK period, in ns

    // ---- DUT signals ---------------------------------------------------------
    logic       CLOCK_50 = 1'b0;
    logic [3:0] KEY;
    logic [9:0] SW;
    logic [9:0] LEDR;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    logic       spi_sclk = 1'b0;   // Mode 0: idles low
    logic       spi_cs_n = 1'b1;   // idles high
    logic       spi_mosi = 1'b0;
    logic       spi_miso;

    int errors = 0;
    int checks = 0;

    // ---- DUT -----------------------------------------------------------------
    spi_top dut (.*);

    // ---- Clock ---------------------------------------------------------------
    always #(CLK_PER/2) CLOCK_50 = ~CLOCK_50;

    // ---- Reference model -----------------------------------------------------
    // What each register SHOULD read back. Updated by write_reg().
    logic [7:0] ref_regs [128];

    // The six RW registers, used by the random stress test.
    logic [6:0] rw_addrs [6];

    // =========================================================================
    // SPI master tasks (Mode 0, MSB first)
    //   - SCLK idles low
    //   - master sets MOSI while SCLK is low, then raises SCLK
    //   - master samples MISO on the rising edge
    // =========================================================================

    // One byte, MSB first; returns the byte received on MISO at the same time.
    task automatic spi_xfer_byte(input logic [7:0] tx, output logic [7:0] rx);
        for (int i = 7; i >= 0; i--) begin
            spi_mosi = tx[i];
            #(t_half);                // SCLK low: MOSI settles
            spi_sclk = 1'b1;          // rising edge: both sides sample
            rx[i]    = spi_miso;
            #(t_half);                // SCLK high
            spi_sclk = 1'b0;          // falling edge: slave shifts MISO
        end
    endtask

    task automatic cs_assert();
        spi_cs_n = 1'b0;
        #(t_half);                    // CS setup before the first SCLK edge
    endtask

    task automatic cs_release();
        #(t_half);                    // CS hold after the last SCLK edge
        spi_cs_n = 1'b1;
        #(2 * t_half);                // gap between frames (slave sees cs_rise)
    endtask

    // 16-bit write frame: {0, addr}, data
    task automatic spi_write(input logic [6:0] addr, input logic [7:0] data);
        logic [7:0] unused;
        cs_assert();
        spi_xfer_byte({1'b0, addr}, unused);
        spi_xfer_byte(data, unused);
        cs_release();
    endtask

    // 24-bit read frame: {1, addr}, dummy, data-in
    task automatic spi_read(input logic [6:0] addr, output logic [7:0] data);
        logic [7:0] unused;
        cs_assert();
        spi_xfer_byte({1'b1, addr}, unused);
        spi_xfer_byte(8'h00, unused);          // turnaround / dummy byte
        spi_xfer_byte(8'h00, data);            // read data arrives on MISO
        cs_release();
    endtask

    // Any number of bits (MSB of `bits` first) in one CS frame.
    // Used for the error tests: short and long frames.
    task automatic spi_raw_frame(input logic [31:0] bits, input int nbits);
        cs_assert();
        for (int i = nbits - 1; i >= 0; i--) begin
            spi_mosi = bits[i];
            #(t_half);
            spi_sclk = 1'b1;
            #(t_half);
            spi_sclk = 1'b0;
        end
        cs_release();
    endtask

    // =========================================================================
    // Reference-model helpers
    // =========================================================================

    // Write a register AND update the reference model to match the spec.
    task automatic write_reg(input logic [6:0] addr, input logic [7:0] data);
        spi_write(addr, data);
        case (addr)
            ADDR_SCRATCH, ADDR_LED_LO, ADDR_HEX10, ADDR_HEX32, ADDR_HEX54:
                ref_regs[addr] = data;
            ADDR_LED_HI:
                ref_regs[addr] = data & 8'h03;     // only 2 real bits
            default: ;                             // RO / STATUS / unmapped: no change
        endcase
    endtask

    // Clear both STATUS flags (write-1-to-clear).
    task automatic clear_status();
        spi_write(ADDR_STATUS, 8'h03);
    endtask

    // =========================================================================
    // Check helpers
    // =========================================================================

    task automatic check_value(input logic [31:0] got, input logic [31:0] expected,
                               input string what);
        checks++;
        if (got !== expected) begin
            $display("FAIL: %s  expected=%h got=%h  @%0t", what, expected, got, $time);
            errors++;
        end
    endtask

    task automatic check_read(input logic [6:0] addr, input logic [7:0] expected,
                              input string what);
        logic [7:0] got;
        spi_read(addr, got);
        checks++;
        if (got !== expected) begin
            $display("FAIL: %s  addr=%h expected=%h got=%h  @%0t",
                     what, addr, expected, got, $time);
            errors++;
        end
    endtask

    // Read a register and compare with the reference model.
    task automatic check_reg(input logic [6:0] addr, input string what);
        check_read(addr, ref_regs[addr], what);
    endtask

    // Expected active-low 7-segment pattern {g,f,e,d,c,b,a} for a hex digit.
    function automatic logic [6:0] seg7(input logic [3:0] v);
        case (v)
            4'h0: return 7'b1000000;   4'h1: return 7'b1111001;
            4'h2: return 7'b0100100;   4'h3: return 7'b0110000;
            4'h4: return 7'b0011001;   4'h5: return 7'b0010010;
            4'h6: return 7'b0000010;   4'h7: return 7'b1111000;
            4'h8: return 7'b0000000;   4'h9: return 7'b0010000;
            4'hA: return 7'b0001000;   4'hB: return 7'b0000011;
            4'hC: return 7'b1000110;   4'hD: return 7'b0100001;
            4'hE: return 7'b0000110;   default: return 7'b0001110;  // F
        endcase
    endfunction

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        logic [7:0] c0, c1, c2;
        logic [6:0] a;
        logic [7:0] d;

        // ---- SCLK frequency ----
        if ($value$plusargs("SCLK_MHZ=%f", sclk_mhz))
            $display("INFO: SCLK = %0.2f MHz (from +SCLK_MHZ)", sclk_mhz);
        else
            $display("INFO: SCLK = %0.2f MHz (default)", sclk_mhz);
        t_half = 500.0 / sclk_mhz;

        // ---- Reference model at reset ----
        foreach (ref_regs[i]) ref_regs[i] = 8'h00;
        ref_regs[ADDR_ID]      = ID_VALUE;
        ref_regs[ADDR_VERSION] = VERSION_VALUE;

        rw_addrs[0] = ADDR_SCRATCH;
        rw_addrs[1] = ADDR_LED_LO;
        rw_addrs[2] = ADDR_LED_HI;
        rw_addrs[3] = ADDR_HEX10;
        rw_addrs[4] = ADDR_HEX32;
        rw_addrs[5] = ADDR_HEX54;

        // ---- Reset: KEY[0] low (active low), other buttons released ----
        KEY = 4'b1110;
        SW  = 10'h000;
        repeat (5) @(posedge CLOCK_50);
        KEY = 4'b1111;
        repeat (10) @(posedge CLOCK_50);   // reset synchronizer releases after 2 clocks

        // =====================================================================
        // Bring-up order (same as on real hardware)
        // =====================================================================

        // ---- Test 1: fixed registers ----
        check_read(ADDR_ID,      ID_VALUE,      "test 1: ID");
        check_read(ADDR_VERSION, VERSION_VALUE, "test 1: VERSION");

        // ---- Test 2: SCRATCH write -> readback ----
        write_reg(ADDR_SCRATCH, 8'h5A);
        check_reg(ADDR_SCRATCH, "test 2: SCRATCH = 5A");
        write_reg(ADDR_SCRATCH, 8'hA5);
        check_reg(ADDR_SCRATCH, "test 2: SCRATCH = A5");

        // ---- Test 3: LED registers -> LEDR pins ----
        write_reg(ADDR_LED_LO, 8'hC3);
        write_reg(ADDR_LED_HI, 8'hFF);                 // only bits 1:0 are kept
        check_value(LEDR, 10'h3C3, "test 3: LEDR pins");
        check_reg(ADDR_LED_LO, "test 3: LED_LO readback");
        check_reg(ADDR_LED_HI, "test 3: LED_HI reads 03 (upper bits 0)");

        // ---- Test 4: HEX registers -> HEX0..HEX5 pins (active low) ----
        write_reg(ADDR_HEX10, 8'h21);                  // HEX1=2, HEX0=1
        write_reg(ADDR_HEX32, 8'h43);                  // HEX3=4, HEX2=3
        write_reg(ADDR_HEX54, 8'hF5);                  // HEX5=F, HEX4=5
        check_value(HEX0, seg7(4'h1), "test 4: HEX0 shows 1");
        check_value(HEX1, seg7(4'h2), "test 4: HEX1 shows 2");
        check_value(HEX2, seg7(4'h3), "test 4: HEX2 shows 3");
        check_value(HEX3, seg7(4'h4), "test 4: HEX3 shows 4");
        check_value(HEX4, seg7(4'h5), "test 4: HEX4 shows 5");
        check_value(HEX5, seg7(4'hF), "test 4: HEX5 shows F");

        // ---- Test 5: switches -> SW_LO / SW_HI ----
        SW = 10'h2A5;
        repeat (5) @(posedge CLOCK_50);                // let the synchronizer settle
        check_read(ADDR_SW_LO, 8'hA5, "test 5: SW_LO");
        check_read(ADDR_SW_HI, 8'h02, "test 5: SW_HI (upper bits 0)");

        // =====================================================================
        // Rules from the spec
        // =====================================================================

        // ---- Test 6: write to an RO register is ignored, no error ----
        spi_write(ADDR_ID, 8'h00);
        check_read(ADDR_ID,     ID_VALUE, "test 6: ID unchanged after write");
        check_read(ADDR_STATUS, 8'h00,    "test 6: no error for RO write");

        // ---- Test 7: unmapped address ----
        check_read(7'h20, 8'h00, "test 7: unmapped read returns 0");
        check_read(ADDR_STATUS, 8'h02, "test 7: ADDR_ERR set by unmapped read");
        clear_status();
        spi_write(7'h7F, 8'hEE);
        check_read(ADDR_STATUS, 8'h02, "test 7: ADDR_ERR set by unmapped write");
        check_reg(ADDR_SCRATCH, "test 7: unmapped write changed nothing");
        clear_status();

        // ---- Test 8: short frame (12 bits) -> no write, FRAME_ERR ----
        spi_raw_frame({20'h0, 1'b0, ADDR_SCRATCH, 4'hF}, 12);
        check_reg(ADDR_SCRATCH, "test 8: short frame did not write");
        check_read(ADDR_STATUS, 8'h01, "test 8: FRAME_ERR set");
        clear_status();

        // ---- Test 9: long frame (20 bits) -> no write, FRAME_ERR ----
        spi_raw_frame({12'h0, 1'b0, ADDR_SCRATCH, 8'hFF, 4'h0}, 20);
        check_reg(ADDR_SCRATCH, "test 9: long frame did not write");
        check_read(ADDR_STATUS, 8'h01, "test 9: FRAME_ERR set");
        clear_status();

        // ---- Test 9b: read command with only 16 bits -> FRAME_ERR ----
        spi_raw_frame({16'h0, 1'b1, ADDR_SCRATCH, 8'h00}, 16);
        check_read(ADDR_STATUS, 8'h01, "test 9b: 16-bit read frame is an error");
        clear_status();

        // ---- Test 10: STATUS write-1-to-clear, bit by bit ----
        spi_raw_frame({20'h0, 12'h000}, 12);            // sets FRAME_ERR
        check_read(7'h30, 8'h00, "test 10: setup unmapped read");  // sets ADDR_ERR
        check_read(ADDR_STATUS, 8'h03, "test 10: both flags set");
        spi_write(ADDR_STATUS, 8'h01);                  // clear FRAME_ERR only
        check_read(ADDR_STATUS, 8'h02, "test 10: W1C bit 0 only");
        spi_write(ADDR_STATUS, 8'h00);                  // writing 0 clears nothing
        check_read(ADDR_STATUS, 8'h02, "test 10: writing 0 changes nothing");
        spi_write(ADDR_STATUS, 8'h02);                  // clear ADDR_ERR
        check_read(ADDR_STATUS, 8'h00, "test 10: W1C bit 1");

        // ---- Test 11: TXN_COUNT counts valid frames only ----
        // A read returns the count BEFORE its own frame completes, then counts itself.
        spi_read(ADDR_TXN_COUNT, c0);
        write_reg(ADDR_SCRATCH, 8'h11);
        write_reg(ADDR_SCRATCH, 8'h22);
        write_reg(ADDR_SCRATCH, 8'h33);
        spi_read(ADDR_TXN_COUNT, c1);
        check_value(c1, 8'(c0 + 8'd4), "test 11: 1 read + 3 writes counted");
        spi_raw_frame({20'h0, 12'hFFF}, 12);            // bad frame: not counted
        spi_read(ADDR_TXN_COUNT, c2);
        check_value(c2, 8'(c1 + 8'd1), "test 11: bad frame not counted");
        clear_status();

        // =====================================================================
        // Stress
        // =====================================================================

        // ---- Test 12: random writes/reads across all RW registers ----
        for (int n = 0; n < N_STRESS; n++) begin
            a = rw_addrs[$urandom_range(5, 0)];
            d = 8'($urandom);
            write_reg(a, d);
            check_reg(a, "test 12: random readback");
        end
        check_read(ADDR_STATUS, 8'h00, "test 12: no errors after stress");
        check_reg(ADDR_ID, "test 12: ID still correct after stress");

        // ---- Summary ----
        $display("INFO: %0d checks", checks);
        if (errors == 0) $display("PASS: tb_spi_top");
        else             $display("FAIL: tb_spi_top - %0d error(s)", errors);
        $finish;
    end

    // ---- Watchdog: stop if something hangs ------------------------------------
    initial begin
        #200ms;
        $display("FAIL: tb_spi_top - timeout");
        $finish;
    end

endmodule
