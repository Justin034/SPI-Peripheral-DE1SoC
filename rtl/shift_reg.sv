// -----------------------------------------------------------------------------
// shift_reg.sv  -  Phase 2.1
//
// Parameterized serial-in / parallel-out shift register, MSB first.
// Used to receive MOSI bits (and later, with a parallel load, to send MISO).
//
// Behaviour to implement:
//   - Synchronous to clk. rst_n is active-low reset; q resets to all zeros.
//   - When shift_en is high on a clk edge, shift q left by one and put din
//     into the LSB. (After WIDTH shifts, the first bit received is in the MSB.)
//   - When shift_en is low, q holds its value.
//   - serial_out is the current MSB of q.
//
// Remember: shift_en is an ENABLE, not a clock. Everything runs on clk.
// -----------------------------------------------------------------------------
module shift_reg #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             shift_en,
    input  logic             din,
    output logic [WIDTH-1:0] q,
    output logic             serial_out
);

    always_ff @(negedge rst_n or posedge clk) begin
        if(!rst_n) begin
            q <= '0;
        end
        else begin
            if(shift_en) begin
                q <= {q[WIDTH-2:0], din};   // drop MSB, append din at LSB
            end
        end
    end

    assign serial_out = q[WIDTH-1];


endmodule
