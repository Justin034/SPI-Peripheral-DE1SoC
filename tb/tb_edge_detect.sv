// -----------------------------------------------------------------------------
// tb_edge_detect.sv  -  self-checking testbench for edge_detect (Phase 2.3)
//
// Two instances:
//   dut      - RESET_VAL = 0, like SCLK (idles low in Mode 0)
//   dut_cs   - RESET_VAL = 1, like CS_N (idles high) - checks that no false
//              edge appears just after reset
//
// sig changes #1 after a rising clock edge, the same way sync_2ff outputs do.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_edge_detect;

    localparam int CLK_PER = 20;   // 50 MHz

    logic clk = 0;
    logic rst_n;
    logic sig;
    logic rise;
    logic fall;

    // Second instance (idle-high signal)
    logic sig_cs;
    logic rise_cs;
    logic fall_cs;

    int errors     = 0;
    int rise_count = 0;
    int fall_count = 0;
    int cs_pulses  = 0;

    edge_detect #(.RESET_VAL(1'b0)) dut (.*);

    edge_detect #(.RESET_VAL(1'b1)) dut_cs (
        .clk(clk), .rst_n(rst_n), .sig(sig_cs), .rise(rise_cs), .fall(fall_cs)
    );

    always #(CLK_PER/2) clk = ~clk;

    // ---- Monitors (run in parallel with the stimulus) ------------------------
    // Count pulses on every clock edge - lets you check "exactly one pulse per edge".
    always @(posedge clk) begin
        if (rst_n) begin
            if (rise) rise_count++;
            if (fall) fall_count++;
            if (rise_cs || fall_cs) cs_pulses++;

            // Test 5 runs the whole time: rise and fall must never be high together
            if (rise && fall) begin
                $display("FAIL: test 5: rise and fall high in the same cycle  @%0t", $time);
                errors++;
            end
        end
    end

    // ---- Helpers -------------------------------------------------------------
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    // Change sig just after a rising edge (as a synchronized signal would).
    task automatic set_sig(input logic v);
        tick();
        sig = v;
    endtask

    task automatic check_int(input int got, input int expected, input string what);
        if (got !== expected) begin
            $display("FAIL: %s  expected=%0d got=%0d  @%0t", what, expected, got, $time);
            errors++;
        end
    endtask

    // ---- Stimulus ------------------------------------------------------------
    initial begin
        int r0, f0;
        localparam int N = 10;

        rst_n = 0; sig = 0; sig_cs = 1;
        repeat (3) tick();
        rst_n = 1;

        // ---- Test 1: no pulses right after reset (both instances) ----
        repeat (5) tick();
        check_int(rise_count, 0, "test 1: no rise after reset");
        check_int(fall_count, 0, "test 1: no fall after reset");
        check_int(cs_pulses,  0, "test 1: no false edge on idle-high signal");

        // ---- Test 2: one rising edge -> exactly one rise pulse ----
        r0 = rise_count;
        f0 = fall_count;
        set_sig(1'b1);
        repeat (5) tick();                       // hold high for several clocks
        check_int(rise_count - r0, 1, "test 2: one rise pulse");
        check_int(fall_count - f0, 0, "test 2: no fall pulse");

        // ---- Test 3: one falling edge -> exactly one fall pulse ----
        r0 = rise_count;
        f0 = fall_count;
        set_sig(1'b0);
        repeat (5) tick();
        check_int(fall_count - f0, 1, "test 3: one fall pulse");
        check_int(rise_count - r0, 0, "test 3: no rise pulse");

        // ---- Test 4: slow "SCLK" - 4 clocks high, 4 low, N times ----
        r0 = rise_count;
        f0 = fall_count;
        repeat (N) begin
            set_sig(1'b1);
            repeat (3) tick();
            set_sig(1'b0);
            repeat (3) tick();
        end
        repeat (3) tick();
        check_int(rise_count - r0, N, "test 4: N rise pulses");
        check_int(fall_count - f0, N, "test 4: N fall pulses");

        // ---- Test 4b: fastest legal toggle - 1 clock high, 1 clock low ----
        r0 = rise_count;
        f0 = fall_count;
        repeat (N) begin
            set_sig(1'b1);
            set_sig(1'b0);
        end
        repeat (3) tick();
        check_int(rise_count - r0, N, "test 4b: N rise pulses at max rate");
        check_int(fall_count - f0, N, "test 4b: N fall pulses at max rate");

        // Test 5 (rise && fall never together) is checked by the monitor above.

        // ---- Summary ----
        if (errors == 0) $display("PASS: tb_edge_detect");
        else             $display("FAIL: tb_edge_detect - %0d error(s)", errors);
        $finish;
    end

endmodule
