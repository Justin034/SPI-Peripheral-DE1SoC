// -----------------------------------------------------------------------------
// spi_slave.sv  -  SPI slave interface (implementation A: oversampled)
//
// Everything runs on the 50 MHz system clock. The SPI pins are synchronized,
// SCLK/CS_N edges are turned into one-cycle pulses, and an FSM decides what
// to do with each byte.
//
// Frame format (objective.md 5.1.1, SPI Mode 0, MSB first):
//   Write (16 bits): {0, ADDR[6:0]}  DATA[7:0]
//   Read  (24 bits): {1, ADDR[6:0]}  dummy[7:0]  -> DATA[7:0] on MISO
//
// Datapath:                       FSM:
//   sync_2ff    x3 pins             captures the command, loads MISO,
//   edge_detect x2 (SCLK, CS_N)     commits writes, flags errors
//   shift_reg   (MOSI receive)
//   bit_counter (bits per frame)
//   tx_shift_reg(MISO send)
//
// SCLK limit: SCLK high and low must each last at least 2 system clocks for the
// edge detector to see them, so SCLK <= 50 MHz / 4 = 12.5 MHz in theory.
// Plan on ~6 MHz or below for margin.
// -----------------------------------------------------------------------------
module spi_slave (
    input  logic       clk,
    input  logic       rst_n,

    // ---- SPI pins (asynchronous to clk) ----
    input  logic       spi_sclk,
    input  logic       spi_cs_n,
    input  logic       spi_mosi,
    output logic       spi_miso,

    // ---- Register-file interface (all synchronous to clk) ----
    output logic [6:0] addr,           // register address from the command byte
    output logic [7:0] wr_data,        // data byte of a write frame
    output logic       wr_en,          // 1-cycle pulse: commit the write
    output logic       rd_en,          // 1-cycle pulse: read addr (sets ADDR_ERR if unmapped)
    input  logic [7:0] rd_data,        // register value at addr (combinational)

    // ---- Status events (to reg_file) ----
    output logic       frame_err_set,  // 1-cycle pulse: frame had the wrong length
    output logic       txn_inc         // 1-cycle pulse: a valid frame completed
);

    // Package items are referenced as spi_pkg::NAME (no `import`) because
    // Yosys does not support the import keyword.

    // =========================================================================
    // Datapath
    // =========================================================================

    // ---- 1. Synchronize the three input pins --------------------------------
    // Packed as {cs_n, sclk, mosi}. Reset values match the idle bus:
    // CS_N high, SCLK low (Mode 0), MOSI don't-care (0).
    // All three go through the same synchronizer, so they keep their relative
    // timing: MOSI is stable when the synchronized SCLK rises.
    logic [2:0] pins_s;
    logic       cs_n_s, sclk_s, mosi_s;

    sync_2ff #(.WIDTH(3), .RESET_VAL(3'b100)) u_sync (
        .clk     (clk),
        .rst_n   (rst_n),
        .d_async ({spi_cs_n, spi_sclk, spi_mosi}),
        .q_sync  (pins_s)
    );

    assign cs_n_s = pins_s[2];
    assign sclk_s = pins_s[1];
    assign mosi_s = pins_s[0];

    // ---- 2. Edge detection ---------------------------------------------------
    logic sclk_rise, sclk_fall;
    logic cs_rise,   cs_fall;      // cs_fall = frame start, cs_rise = frame end

    edge_detect #(.RESET_VAL(1'b0)) u_sclk_edge (
        .clk(clk), .rst_n(rst_n), .sig(sclk_s), .rise(sclk_rise), .fall(sclk_fall)
    );

    edge_detect #(.RESET_VAL(1'b1)) u_cs_edge (
        .clk(clk), .rst_n(rst_n), .sig(cs_n_s), .rise(cs_rise), .fall(cs_fall)
    );

    // ---- 3. Receive shift register (MOSI) ------------------------------------
    // Samples MOSI on each SCLK rising edge, but only while CS_N is low.
    logic [7:0] rx_byte;

    shift_reg #(.WIDTH(8)) u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .shift_en   (sclk_rise && !cs_n_s),
        .din        (mosi_s),
        .q          (rx_byte),
        /* verilator lint_off PINCONNECTEMPTY */
        .serial_out ()                  // unused on the receive side (intentional)
        /* verilator lint_on PINCONNECTEMPTY */
    );

    // ---- 4. Bit counter ------------------------------------------------------
    // Cleared while CS_N is high (between frames), counts SCLK rising edges.
    // bit_count updates one clock AFTER each sclk_rise pulse, together with rx_byte.
    logic [4:0] bit_count;

    bit_counter #(.WIDTH(5)) u_cnt (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (cs_n_s),
        .inc   (sclk_rise),
        .count (bit_count)
    );

    // ---- 5. Transmit shift register (MISO) -----------------------------------
    logic tx_load;     // FSM output: load rd_data
    logic tx_active;   // FSM output: allow SCLK falling edges to shift MISO

    tx_shift_reg #(.WIDTH(8)) u_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (tx_load),
        .load_data  (rd_data),
        .shift_en   (sclk_fall && tx_active),
        .serial_out (spi_miso)
    );

    // ---- 6. Command capture --------------------------------------------------
    logic rw;          // 1 = read, 0 = write
    logic cmd_capture; // FSM output: latch {rw, addr} from rx_byte

    // After 8 bits, rx_byte holds the command byte {RW, ADDR[6:0]}.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rw   <= 1'b0;
            addr <= '0;
        end
        else if (cmd_capture) begin
            {rw, addr} <= rx_byte;      // bit 7 -> rw, bits 6:0 -> addr
        end
    end

    // RW bit of the command byte, as its own signal so the FSM's always_comb
    // doesn't need a bit-select (Icarus warns about those).
    logic cmd_is_read;
    assign cmd_is_read = rx_byte[7];

    // When CS_N rises after a 16-bit write frame, the receive shift register
    // still holds the last 8 bits received = the data byte. No extra storage
    // needed; wr_data is only used when wr_en pulses.
    assign wr_data = rx_byte;

    // =========================================================================
    // FSM
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE,       // waiting for CS_N to fall
        CMD,        // receiving the command byte (bits 1-8)
        WR_DATA,    // receiving the write data byte (bits 9-16)
        RD_TURN,    // turnaround / dummy byte (bits 9-16) - fetch read data
        RD_DATA,    // shifting read data out on MISO (bits 17-24)
        DONE        // all bits received - wait for CS_N to rise
    } state_t;

    state_t state, next_state;

    // ---- State register ------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // ---- Next-state and output logic -----------------------------------------
    //
    //   IDLE    --cs_fall-------------------------------> CMD
    //   CMD     --count==8, rx_byte[7]==0 / cmd_capture--> WR_DATA
    //   CMD     --count==8, rx_byte[7]==1 / cmd_capture--> RD_TURN
    //   WR_DATA --count==16-----------------------------> DONE
    //   RD_TURN --count==16 / tx_load, rd_en------------> RD_DATA
    //   RD_DATA --count==24-----------------------------> DONE
    //   ANY     --cs_rise / check length----------------> IDLE
    //
    // MISO timing (the trap): bit 7 of the read data must be on MISO before
    // SCLK rising edge 17. The data is loaded right after rising edge 16
    // (count == 16), and shifting is only enabled once count > 16, so falling
    // edge 16 does NOT shift and bit 7 stays on MISO for rising edge 17.
    // Falling edges 17..23 then present bits 6..0 for rising edges 18..24.
    always_comb begin
        // Defaults: stay in the same state, all pulses low (no latches).
        next_state    = state;
        cmd_capture   = 1'b0;
        rd_en         = 1'b0;
        tx_load       = 1'b0;
        tx_active     = 1'b0;
        wr_en         = 1'b0;
        frame_err_set = 1'b0;
        txn_inc       = 1'b0;

        if (cs_rise) begin
            // ---- End of frame: CS_N went high. Always return to IDLE. ----
            // bit_count is still valid in this cycle (it clears on the next edge).
            next_state = IDLE;

            if (state != IDLE) begin
                if (!rw && bit_count == 5'(spi_pkg::WRITE_FRAME_BITS)) begin
                    wr_en   = 1'b1;          // commit the write NOW, not at bit 16
                    txn_inc = 1'b1;
                end
                else if (rw && bit_count == 5'(spi_pkg::READ_FRAME_BITS)) begin
                    txn_inc = 1'b1;          // read already happened; just count it
                end
                else begin
                    frame_err_set = 1'b1;    // too short, too long, or wrong type
                end
            end
        end
        else begin
            case (state)
                IDLE: begin
                    if (cs_fall) next_state = CMD;
                end

                CMD: begin
                    if (bit_count == 5'd8) begin
                        cmd_capture = 1'b1;
                        if (cmd_is_read) next_state = RD_TURN;
                        else             next_state = WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (bit_count == 5'd16) next_state = DONE;
                end

                RD_TURN: begin
                    // addr was captured in CMD, so rd_data is valid here.
                    if (bit_count == 5'd16) begin
                        tx_load    = 1'b1;
                        rd_en      = 1'b1;   // one pulse per read frame
                        next_state = RD_DATA;
                    end
                end

                RD_DATA: begin
                    tx_active = (bit_count > 5'd16);   // skip falling edge 16
                    if (bit_count == 5'd24) next_state = DONE;
                end

                DONE: begin
                    // Wait for cs_rise (handled above). Extra bits make
                    // bit_count != 16/24, which is flagged as FRAME_ERR then.
                end

                default: next_state = IDLE;
            endcase
        end
    end

endmodule
