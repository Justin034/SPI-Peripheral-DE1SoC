// -----------------------------------------------------------------------------
// tb_shift_reg.sv  -  self-checking testbench for shift_reg (Phase 2.1)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_shift_reg;

    localparam int WIDTH   = 8;
    localparam int CLK_PER = 20;           // 50 MHz, same as CLOCK_50

    // ---- DUT signals ---------------------------------------------------------
    logic             clk = 0;
    logic             rst_n;
    logic             shift_en;
    logic             din;
    logic [WIDTH-1:0] q;
    logic             serial_out;

    int errors = 0;

    // ---- DUT -----------------------------------------------------------------
    shift_reg #(.WIDTH(WIDTH)) dut (.*);

    // ---- Clock ---------------------------------------------------------------
    always #(CLK_PER/2) clk = ~clk;

    // ---- Helpers -------------------------------------------------------------
    task automatic check(input logic [WIDTH-1:0] expected, input string what);
        if (q !== expected) begin
            $display("FAIL: %s  expected=%h got=%h  @%0t", what, expected, q, $time);
            errors++;
        end
    endtask

    task automatic shift_in_byte(input logic [WIDTH-1:0] value);
        // loop i from WIDTH-1 down to 0
        //     din = bit i of value, shift_en = 1
        //     wait for a rising clock edge, then #1
        // after the loop: shift_en = 0

        for (int i = WIDTH-1; i >= 0; i--) begin
            din      = value[i];   // put the next bit on the input (MSB first)
            shift_en = 1;          // tell the DUT to shift on the next edge
            @(posedge clk);        // DUT captures din on this edge
            #1;                    // step past the edge before changing inputs (avoids a race)
        end
        shift_en = 0;              // stop shifting so q holds its value
    endtask

    // ---- Stimulus ------------------------------------------------------------
    initial begin
        logic [WIDTH-1:0] rege;    // declarations must come before any statements

        rst_n = 0; shift_en = 0; din = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;

        // ---- Test 1: q is 0 after reset ----
        check('0, "test 1: q is 0 after reset");

        @(posedge clk);

        // ---- Test 2: shift in 8'hA5, MSB first, check q == 8'hA5 ----
        // shift_in_byte feeds the 8 bits in over 8 clocks and leaves shift_en low.
        shift_in_byte(8'hA5);
        check(8'hA5, "test 2: shift in A5");

        // ---- Test 3: hold shift_en low for a few clocks, q must not change ----
        repeat(3) @(posedge clk);
        shift_en = 0;
        repeat(5) @(posedge clk);
        check(8'hA5, "test 3: q holds with shift_en low");

        repeat(3) @(posedge clk);

        // ---- Test 4: shift in several random bytes and check each ----
        repeat (5) begin
            rege = $urandom;
            shift_in_byte(rege);
            repeat(3) @(posedge clk);
            check(rege, "test 4: random byte");
        end

        // ---- Test 5: serial_out always equals the MSB of q ----
        shift_in_byte(8'h80);                       // MSB = 1
        if (serial_out !== 1'b1) begin
            $display("FAIL: test 5: serial_out should be 1 for q=80, got %b", serial_out);
            errors++;
        end
        shift_in_byte(8'h7F);                       // MSB = 0
        if (serial_out !== 1'b0) begin
            $display("FAIL: test 5: serial_out should be 0 for q=7F, got %b", serial_out);
            errors++;
        end
        if (serial_out !== q[WIDTH-1]) begin
            $display("FAIL: test 5: serial_out != q[MSB]");
            errors++;
        end

        // ---- Summary ----
        if (errors == 0) $display("PASS: tb_shift_reg");
        else             $display("FAIL: tb_shift_reg - %0d error(s)", errors);
        $finish;
    end

endmodule
