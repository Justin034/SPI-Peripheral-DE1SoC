// 4-bit value -> DE1-SoC 7-segment pattern. ACTIVE-LOW (0 = segment on).
// seg_n bit order {g,f,e,d,c,b,a}:      --a--
//                                      f     b
//                                       --g--
//                                      e     c
//                                       --d--
module hex7seg (
    input  logic [3:0] val,
    output logic [6:0] seg_n
);

    // Active-low: 0 = segment ON, 1 = segment OFF. Bit order {g,f,e,d,c,b,a}.
    always_comb begin
        case (val)
            //                  gfedcba        segments ON
            4'h0:    seg_n = 7'b1000000;   // 0: a b c d e f
            4'h1:    seg_n = 7'b1111001;   // 1: b c
            4'h2:    seg_n = 7'b0100100;   // 2: a b d e g
            4'h3:    seg_n = 7'b0110000;   // 3: a b c d g
            4'h4:    seg_n = 7'b0011001;   // 4: b c f g
            4'h5:    seg_n = 7'b0010010;   // 5: a c d f g
            4'h6:    seg_n = 7'b0000010;   // 6: a c d e f g
            4'h7:    seg_n = 7'b1111000;   // 7: a b c
            4'h8:    seg_n = 7'b0000000;   // 8: all
            4'h9:    seg_n = 7'b0010000;   // 9: a b c d f g
            4'hA:    seg_n = 7'b0001000;   // A: a b c e f g
            4'hB:    seg_n = 7'b0000011;   // b: c d e f g
            4'hC:    seg_n = 7'b1000110;   // C: a d e f
            4'hD:    seg_n = 7'b0100001;   // d: b c d e g
            4'hE:    seg_n = 7'b0000110;   // E: a d e f g
            4'hF:    seg_n = 7'b0001110;   // F: a e f g
            default: seg_n = 7'h7F;        // blank (all off) - also covers x/z in simulation
        endcase
    end

endmodule
