// -----------------------------------------------------------------------------
// tb_sync_2ff.sv  -  self-checking testbench for sync_2ff (Phase 2.2)
//
// Simulation can't show real metastability. What you CAN check is the latency:
// a change on d_async should appear on q_sync after 2 clock edges, not sooner.
//
// Two instances:
//   dut      - WIDTH 1, RESET_VAL 0
//   dut_bus  - WIDTH 3, RESET_VAL 3'b100, exactly how spi_slave uses it
//              for {cs_n, sclk, mosi}
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_sync_2ff;

    localparam int CLK_PER = 20;   // 50 MHz

    logic clk = 0;
    logic rst_n;
    logic d_async;
    logic q_sync;

    logic [2:0] d_bus;
    logic [2:0] q_bus;

    int errors = 0;

    sync_2ff #(.WIDTH(1), .RESET_VAL(1'b0)) dut (.*);

    sync_2ff #(.WIDTH(3), .RESET_VAL(3'b100)) dut_bus (
        .clk(clk), .rst_n(rst_n), .d_async(d_bus), .q_sync(q_bus)
    );

    always #(CLK_PER/2) clk = ~clk;

    // ---- Helpers -------------------------------------------------------------
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic check(input logic [2:0] got, input logic [2:0] expected,
                         input string what);
        if (got !== expected) begin
            $display("FAIL: %s  expected=%b got=%b  @%0t", what, expected, got, $time);
            errors++;
        end
    endtask

    // Change d_async at an "asynchronous" moment (not on a clock edge), then
    // check the output is still old after 1 edge and new after 2 edges.
    task automatic check_latency(input logic new_val, input string what);
        logic old_val;
        old_val = q_sync;
        @(posedge clk);
        #3;                                   // between edges
        d_async = new_val;
        tick();
        check(q_sync, old_val, {what, ": still old after 1 edge"});
        tick();
        check(q_sync, new_val, {what, ": new after 2 edges"});
    endtask

    // ---- Stimulus ------------------------------------------------------------
    initial begin
        // Hold inputs at the OPPOSITE of the reset value during reset, to prove
        // the outputs come from RESET_VAL and not from the inputs.
        rst_n = 0; d_async = 1; d_bus = 3'b011;
        tick();   // one edge while in reset (avoids a time-0 race on the x->0 reset edge)

        // ---- Test 1: reset value ----
        check(q_sync, 1'b0,   "test 1: q_sync == RESET_VAL during reset");
        check(q_bus,  3'b100, "test 1: q_bus == RESET_VAL during reset");

        d_async = 0; d_bus = 3'b100;          // idle values before release
        repeat (3) tick();
        rst_n = 1;
        repeat (3) tick();
        check(q_sync, 1'b0,   "test 1: q_sync still 0 after release");
        check(q_bus,  3'b100, "test 1: q_bus still idle after release");

        // ---- Test 2: 0 -> 1 takes exactly 2 edges ----
        check_latency(1'b1, "test 2 (0->1)");

        // ---- Test 3: 1 -> 0 takes exactly 2 edges ----
        check_latency(1'b0, "test 3 (1->0)");

        // ---- Test 4: multi-bit instance - each bit passes through in 2 edges ----
        @(posedge clk);
        #3;
        d_bus = 3'b011;                       // CS_N low, SCLK high, MOSI high
        tick();
        check(q_bus, 3'b100, "test 4: bus still old after 1 edge");
        tick();
        check(q_bus, 3'b011, "test 4: bus new after 2 edges");

        // ---- Test 5: asynchronous reset mid-run ----
        @(negedge clk);
        rst_n = 0;
        #1;
        check(q_bus, 3'b100, "test 5: async reset returns to RESET_VAL");
        tick();
        rst_n = 1;
        tick();

        // ---- Summary ----
        if (errors == 0) $display("PASS: tb_sync_2ff");
        else             $display("FAIL: tb_sync_2ff - %0d error(s)", errors);
        $finish;
    end

endmodule
