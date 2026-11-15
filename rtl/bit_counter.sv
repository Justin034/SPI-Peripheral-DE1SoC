// Counts SPI bits in one frame (inc = SCLK rising edge, clear = CS_N high).
// Saturates at all-ones instead of wrapping, so an over-long frame can never
// wrap back to a valid-looking 16 or 24 and slip past FRAME_ERR detection.
module bit_counter #(
    parameter int WIDTH = 5
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             clear,
    input  logic             inc,
    output logic [WIDTH-1:0] count
);

    always_ff @(negedge rst_n or posedge clk) begin
        if (!rst_n) begin
            count <= '0;                 // global reset: highest priority
        end
        else if (clear) begin
            count <= '0;                 // CS_N high between frames: restart count
        end
        else if (inc && count != '1) begin
            count <= count + 1'b1;       // count a bit, but saturate at all-ones (31)
        end
        // otherwise: hold (no else needed - flip-flops keep their value)
    end


endmodule
