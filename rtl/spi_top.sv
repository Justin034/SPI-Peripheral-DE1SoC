// -----------------------------------------------------------------------------
// spi_top.sv  -  DE1-SoC top level for the SPI register-file peripheral
//
// Port names follow the DE1-SoC System Builder / user manual so pin
// assignments can be copied from there. The four spi_* pins go to the GPIO_0
// header; choose the exact pins in Quartus Pin Planner and record them in the
// README (both boards are 3.3 V - connect a shared ground).
//
//   ESP32 (master)          DE1-SoC (this design)
//   SCLK  ------------->    spi_sclk
//   MOSI  ------------->    spi_mosi
//   MISO  <-------------    spi_miso
//   CS    ------------->    spi_cs_n
//   GND   --------------    GND
// -----------------------------------------------------------------------------
module spi_top (
    input  logic       CLOCK_50,
    input  logic [3:0] KEY,        // active low push buttons; KEY[0] = reset
    input  logic [9:0] SW,
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5,

    // ---- SPI (GPIO_0 header) ----
    input  logic       spi_sclk,
    input  logic       spi_cs_n,
    input  logic       spi_mosi,
    output logic       spi_miso
);

    logic clk;
    logic rst_n;

    assign clk = CLOCK_50;

    // ---- Reset synchronizer --------------------------------------------------
    // KEY[0] is an asynchronous push button (active low).
    //   - Pressing it resets everything IMMEDIATELY (asynchronous assert).
    //   - Releasing it only takes effect on a clock edge, after 2 flops
    //     (synchronous de-assert), so every flip-flop leaves reset on the same
    //     clock edge and none sees the release in the middle of a cycle.
    logic [1:0] rst_sync;

    always_ff @(posedge clk or negedge KEY[0]) begin
        if (!KEY[0]) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    end

    assign rst_n = rst_sync[1];

    // ---- Switch synchronizer ------------------------------------------------
    logic [9:0] sw_s;

    sync_2ff #(.WIDTH(10), .RESET_VAL('0)) u_sw_sync (
        .clk     (clk),
        .rst_n   (rst_n),
        .d_async (SW),
        .q_sync  (sw_s)
    );

    // ---- SPI slave <-> register file -----------------------------------------
    logic [6:0] addr;
    logic [7:0] wr_data, rd_data;
    logic       wr_en, rd_en;
    logic       frame_err_set, txn_inc;

    spi_slave u_spi (
        .clk           (clk),
        .rst_n         (rst_n),
        .spi_sclk      (spi_sclk),
        .spi_cs_n      (spi_cs_n),
        .spi_mosi      (spi_mosi),
        .spi_miso      (spi_miso),
        .addr          (addr),
        .wr_data       (wr_data),
        .wr_en         (wr_en),
        .rd_en         (rd_en),
        .rd_data       (rd_data),
        .frame_err_set (frame_err_set),
        .txn_inc       (txn_inc)
    );

    logic [23:0] hex_digits;

    reg_file u_regs (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr          (addr),
        .wr_data       (wr_data),
        .wr_en         (wr_en),
        .rd_en         (rd_en),
        .rd_data       (rd_data),
        .frame_err_set (frame_err_set),
        .txn_inc       (txn_inc),
        .sw            (sw_s),
        .ledr          (LEDR),
        .hex_digits    (hex_digits)
    );

    // ---- 7-segment decoders --------------------------------------------------
    hex7seg u_hex0 (.val(hex_digits[3:0]),   .seg_n(HEX0));
    hex7seg u_hex1 (.val(hex_digits[7:4]),   .seg_n(HEX1));
    hex7seg u_hex2 (.val(hex_digits[11:8]),  .seg_n(HEX2));
    hex7seg u_hex3 (.val(hex_digits[15:12]), .seg_n(HEX3));
    hex7seg u_hex4 (.val(hex_digits[19:16]), .seg_n(HEX4));
    hex7seg u_hex5 (.val(hex_digits[23:20]), .seg_n(HEX5));

endmodule
