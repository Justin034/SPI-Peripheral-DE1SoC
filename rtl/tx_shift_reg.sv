// -----------------------------------------------------------------------------
// tx_shift_reg.sv  -  parallel-in / serial-out shift register for MISO
//
// Used during the read-data byte: the register value is loaded in parallel,
// then shifted out MSB first, one bit per SCLK falling edge.
// (Your shift_reg.sv is serial-in; this is its "send" counterpart.)
//
// Behaviour to implement:
//   - Synchronous to clk, reset to all zeros.
//   - load has priority: when load is high, q <= load_data.
//   - Otherwise, when shift_en is high, shift q left by one (fill LSB with 0).
//   - serial_out is always the current MSB of q (this drives MISO).
//
// TIMING TRAP (see the FSM notes in spi_slave.sv): the MSB must be on MISO
// before SCLK rising edge 17. If you load and then let falling edge 16 shift
// as normal, the MSB is lost and every read comes back shifted by one bit.
// -----------------------------------------------------------------------------
module tx_shift_reg #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             load,
    input  logic [WIDTH-1:0] load_data,
    input  logic             shift_en,
    output logic             serial_out
);

    logic [WIDTH-1:0] q;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            q <= '0;
        end
        else begin
            if(load) begin
                q <= load_data;
            end
            else if(shift_en) begin
                q <= {q[WIDTH-2:0], 1'b0};
            end

        end
    end

    assign serial_out = q[WIDTH-1];

endmodule
