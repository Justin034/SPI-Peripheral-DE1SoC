// Two-flip-flop synchronizer: brings an asynchronous input into the clk domain.
// WIDTH > 1 = WIDTH independent 1-bit synchronizers (e.g. switches). NOT safe
// for a multi-bit value whose bits must arrive together, such as a data byte.
module sync_2ff #(
    parameter int              WIDTH     = 1,
    parameter logic [WIDTH-1:0] RESET_VAL = '0
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] d_async,
    output logic [WIDTH-1:0] q_sync
);

    logic [WIDTH-1:0] stage1;

    always_ff @(negedge rst_n or posedge clk) begin
        if(!rst_n) begin
            q_sync <= RESET_VAL;
            stage1 <= RESET_VAL;
        end
        else begin
            stage1 <= d_async;
            q_sync <= stage1;
        end

    end

endmodule
