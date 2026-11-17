// -----------------------------------------------------------------------------
// tb_spi_master.sv  -  Phase 3: SPI master model, checked by a bus monitor
//
// No slave here: this testbench checks that the master tasks produce correct
// frames. A monitor watches the bus like a logic analyser and records every
// MOSI bit sampled on an SCLK rising edge while CS_N is low.
//
// The same tasks are used in tb_spi_top.sv to drive the real design.
//
// Frame format (SPI Mode 0, MSB first, CS_N active low):
//   Write (16 bits): {0, ADDR[6:0]}  DATA[7:0]
//   Read  (24 bits): {1, ADDR[6:0]}  dummy[7:0]  -> DATA[7:0] on MISO in byte 2
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_spi_master;

    // ---- Parameters ----------------------------------------------------------
    localparam real SCLK_MHZ = 1.0;
    localparam real T_HALF   = 500.0 / SCLK_MHZ;     // half SCLK period, ns

    // ---- SPI bus -------------------------------------------------------------
    logic sclk = 1'b0;    // idles low (Mode 0)
    logic cs_n = 1'b1;    // idles high
    logic mosi = 1'b0;
    logic miso;

    // No slave: MISO is driven by a fixed pattern so spi_read has something
    // known to capture. The "slave" puts PATTERN on MISO during byte 2.
    localparam logic [7:0] PATTERN = 8'hC6;
    logic [7:0] miso_shift = PATTERN;
    assign miso = miso_shift[7];

    int errors = 0;

    // ---- Bus monitor -------------------------------------------------------
    logic [31:0] mon_bits;
    int          mon_count;

    always @(negedge cs_n) begin       // frame start
        mon_bits  = '0;
        mon_count = 0;
    end

    always @(posedge sclk) begin       // sample like a slave would
        if (!cs_n) begin
            mon_bits = {mon_bits[30:0], mosi};
            mon_count++;
        end
    end

    // Model a slave's MISO during byte 2: shift on falling edges 17..23.
    always @(negedge sclk) begin
        if (!cs_n && mon_count > 16) miso_shift = {miso_shift[6:0], 1'b0};
    end
    always @(posedge cs_n) miso_shift = PATTERN;   // reload between frames

    // ---- Master tasks --------------------------------------------------------

    // Send one byte MSB first and capture the byte received on MISO at the same time.
    task automatic spi_xfer_byte(input logic [7:0] tx, output logic [7:0] rx);
        for (int i = 7; i >= 0; i--) begin
            mosi = tx[i];
            #(T_HALF);          // SCLK low: MOSI settles
            sclk = 1'b1;        // rising edge: sample
            rx[i] = miso;
            #(T_HALF);
            sclk = 1'b0;        // falling edge
        end
    endtask

    // One complete write frame (16 bits).
    task automatic spi_write(input logic [6:0] addr, input logic [7:0] data);
        logic [7:0] unused;
        cs_n = 1'b0;
        #(T_HALF);
        spi_xfer_byte({1'b0, addr}, unused);
        spi_xfer_byte(data, unused);
        #(T_HALF);
        cs_n = 1'b1;
        #(2 * T_HALF);
    endtask

    // One complete read frame (24 bits).
    task automatic spi_read(input logic [6:0] addr, output logic [7:0] data);
        logic [7:0] unused;
        cs_n = 1'b0;
        #(T_HALF);
        spi_xfer_byte({1'b1, addr}, unused);
        spi_xfer_byte(8'h00, unused);      // dummy / turnaround
        spi_xfer_byte(8'h00, data);        // capture MISO
        #(T_HALF);
        cs_n = 1'b1;
        #(2 * T_HALF);
    endtask

    // Compare helper
    task automatic check(input logic [31:0] got, input logic [31:0] expected,
                         input string what);
        if (got !== expected) begin
            $display("FAIL: %s  expected=%h got=%h  @%0t", what, expected, got, $time);
            errors++;
        end
    endtask

    // ---- Stimulus ------------------------------------------------------------
    initial begin
        logic [7:0] rd;

        #(4 * T_HALF);

        // ---- Frame 1: write 0x3C to 0x05 ----
        spi_write(7'h05, 8'h3C);
        check(mon_count, 16,         "write: 16 SCLK rising edges");
        check(mon_bits,  32'h0000_053C, "write: MOSI bits = {0,05} 3C");

        // ---- Frame 2: read 0x0A ----
        spi_read(7'h0A, rd);
        check(mon_count, 24,         "read: 24 SCLK rising edges");
        check(mon_bits,  32'h008A_0000, "read: MOSI bits = {1,0A} 00 00");
        check(rd,        PATTERN,    "read: MISO byte captured MSB first");

        // ---- Frame 3: CS and SCLK idle levels between frames ----
        check(cs_n, 1'b1, "idle: CS_N high");
        check(sclk, 1'b0, "idle: SCLK low (Mode 0)");

        if (errors == 0) $display("PASS: tb_spi_master");
        else             $display("FAIL: tb_spi_master - %0d error(s)", errors);
        $finish;
    end

    // ---- Waveforms: only with +WAVES (./run_tests.sh waves tb_spi_master) ----
    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("build/tb_spi_master.vcd");
            $dumpvars(0, tb_spi_master);
        end
    end

endmodule
