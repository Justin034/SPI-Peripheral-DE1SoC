// -----------------------------------------------------------------------------
// tb_hex7seg.sv  -  self-checking testbench for hex7seg (Phase 2.5)
//
// hex7seg is combinational, so no clock is needed: set val, wait a moment,
// check seg_n.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_hex7seg;

    logic [3:0] val;
    logic [6:0] seg_n;

    int errors = 0;

    // Expected ACTIVE-LOW patterns (0 = segment ON), index = digit value.
    // Bit order {g,f,e,d,c,b,a}, matching seg_n[6:0] on the DE1-SoC.
    //
    //        --a--
    //       f     b
    //        --g--
    //       e     c
    //        --d--
    logic [6:0] expected [16];

    hex7seg dut (.*);

    initial begin
        //                gfedcba          segments ON
        expected[ 0] = 7'b1000000;  // 0: a b c d e f
        expected[ 1] = 7'b1111001;  // 1: b c
        expected[ 2] = 7'b0100100;  // 2: a b d e g
        expected[ 3] = 7'b0110000;  // 3: a b c d g
        expected[ 4] = 7'b0011001;  // 4: b c f g
        expected[ 5] = 7'b0010010;  // 5: a c d f g
        expected[ 6] = 7'b0000010;  // 6: a c d e f g
        expected[ 7] = 7'b1111000;  // 7: a b c
        expected[ 8] = 7'b0000000;  // 8: all
        expected[ 9] = 7'b0010000;  // 9: a b c d f g
        expected[10] = 7'b0001000;  // A: a b c e f g
        expected[11] = 7'b0000011;  // b: c d e f g
        expected[12] = 7'b1000110;  // C: a d e f
        expected[13] = 7'b0100001;  // d: b c d e g
        expected[14] = 7'b0000110;  // E: a d e f g
        expected[15] = 7'b0001110;  // F: a e f g

        // ---- Test: every input value ----
        for (int v = 0; v < 16; v++) begin
            val = 4'(v);
            #1;
            if (seg_n !== expected[v]) begin
                $display("FAIL: val=%h  expected=%b got=%b", val, expected[v], seg_n);
                errors++;
            end
        end

        // ---- Summary ----
        if (errors == 0) $display("PASS: tb_hex7seg");
        else             $display("FAIL: tb_hex7seg - %0d error(s)", errors);
        $finish;
    end

    // ---- Waveforms: only with +WAVES (./run_tests.sh waves tb_hex7seg) -------
    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("build/tb_hex7seg.vcd");
            $dumpvars(0, tb_hex7seg);
        end
    end

endmodule
