module edge_detect #(
    parameter logic RESET_VAL = 1'b0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic sig,
    output logic rise,
    output logic fall
);

    logic sig_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sig_d <= RESET_VAL;
        end
        else begin
            sig_d <= sig;
        end
    end
            
    // Compare current vs previous value: three cases - rising, falling, no edge
    always_comb begin : edge_logic
        if (sig && !sig_d) begin          // was 0, now 1 -> rising edge
            rise = 1'b1;
            fall = 1'b0;
        end
        else if (!sig && sig_d) begin     // was 1, now 0 -> falling edge
            rise = 1'b0;
            fall = 1'b1;
        end
        else begin                        // unchanged -> no edge
            rise = 1'b0;
            fall = 1'b0;
        end
    end

endmodule
