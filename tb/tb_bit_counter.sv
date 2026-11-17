// -----------------------------------------------------------------------------
// tb_bit_counter.sv  -  self-checking testbench for bit_counter (Phase 2.4)
//
// Inputs are always changed #1 after a rising clock edge, and outputs are
// checked #1 after an edge, so the testbench never races the DUT.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_bit_counter;

    localparam int WIDTH   = 5;
    localparam int CLK_PER = 20;   // 50 MHz
    localparam int MAX     = (1 << WIDTH) - 1;   // 31 for WIDTH = 5

    logic             clk = 0;
    logic             rst_n;
    logic             clear;
    logic             inc;
    logic [WIDTH-1:0] count;

    int errors = 0;

    bit_counter #(.WIDTH(WIDTH)) dut (.*);

    always #(CLK_PER/2) clk = ~clk;

    // ---- Helpers -------------------------------------------------------------

    // Step to just after the next rising edge.
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    // n one-cycle inc pulses with 2 idle clocks between them,
    // like SCLK rising-edge pulses from edge_detect.
    task automatic pulse_inc(input int n);
        repeat (n) begin
            inc = 1'b1;
            tick();
            inc = 1'b0;
            repeat (2) tick();
        end
    endtask

    // One-cycle clear pulse (like CS_N going high between frames).
    task automatic pulse_clear();
        clear = 1'b1;
        tick();
        clear = 1'b0;
    endtask

    task automatic check(input int expected, input string what);
        if (count !== expected[WIDTH-1:0]) begin
            $display("FAIL: %s  expected=%0d got=%0d  @%0t", what, expected, count, $time);
            errors++;
        end
    endtask

    // ---- Stimulus ------------------------------------------------------------
    initial begin
        rst_n = 0; clear = 1; inc = 0;
        repeat (3) tick();
        rst_n = 1;
        tick();
        clear = 0;

        // ---- Test 1: 16 pulses -> 16 (a write frame) ----
        check(0, "test 1: starts at 0");
        pulse_inc(16);
        check(16, "test 1: 16 pulses");

        // ---- Test 2: clear for one cycle -> 0 ----
        pulse_clear();
        check(0, "test 2: clear");

        // ---- Test 3: 24 pulses -> 24 (a read frame) ----
        pulse_inc(24);
        check(24, "test 3: 24 pulses");
        pulse_clear();

        // ---- Test 4: 40 pulses -> saturates at MAX, does not wrap ----
        pulse_inc(40);
        check(MAX, "test 4: saturates at max");
        pulse_inc(1);
        check(MAX, "test 4: stays at max on further pulses");
        pulse_clear();

        // ---- Test 5: clear and inc together -> clear wins ----
        pulse_inc(5);
        check(5, "test 5: setup, 5 pulses");
        clear = 1'b1;
        inc   = 1'b1;
        tick();
        clear = 1'b0;
        inc   = 1'b0;
        check(0, "test 5: clear beats inc");

        // ---- Test 6: count holds when inc is low ----
        pulse_inc(7);
        repeat (10) tick();
        check(7, "test 6: holds with inc low");

        // ---- Test 7: asynchronous reset clears immediately (no clock edge) ----
        @(negedge clk);              // middle of a clock period
        rst_n = 1'b0;
        #1;
        check(0, "test 7: async reset");
        tick();
        rst_n = 1'b1;
        tick();

        // ---- Summary ----
        if (errors == 0) $display("PASS: tb_bit_counter");
        else             $display("FAIL: tb_bit_counter - %0d error(s)", errors);
        $finish;
    end

    // ---- Waveforms: only with +WAVES (./run_tests.sh waves tb_bit_counter) ---
    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("build/tb_bit_counter.vcd");
            $dumpvars(0, tb_bit_counter);
        end
    end

endmodule
