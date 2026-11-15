// -----------------------------------------------------------------------------
// reg_file.sv  -  8-bit register map (objective.md section 5.1.1)
//
// | Addr | Name      | Access | Notes                                        |
// |------|-----------|--------|----------------------------------------------|
// | 0x00 | ID        | RO     | ID_VALUE (0xA5)                              |
// | 0x01 | VERSION   | RO     | VERSION_VALUE                                |
// | 0x02 | STATUS    | RO/W1C | [0] FRAME_ERR, [1] ADDR_ERR, sticky          |
// | 0x03 | TXN_COUNT | RO     | valid frames, wraps at 255                   |
// | 0x04 | SCRATCH   | RW     | no hardware effect                           |
// | 0x05 | LED_LO    | RW     | LEDR[7:0]                                    |
// | 0x06 | LED_HI    | RW     | bits 1:0 -> LEDR[9:8], bits 7:2 read 0       |
// | 0x07 | HEX10     | RW     | [3:0] HEX0, [7:4] HEX1                       |
// | 0x08 | HEX32     | RW     | [3:0] HEX2, [7:4] HEX3                       |
// | 0x09 | HEX54     | RW     | [3:0] HEX4, [7:4] HEX5                       |
// | 0x0A | SW_LO     | RO     | SW[7:0]                                      |
// | 0x0B | SW_HI     | RO     | bits 1:0 = SW[9:8], bits 7:2 read 0          |
//
// Writes to RO registers are ignored (no error).
// Reads/writes to 0x0C-0x7F: read 0x00, write ignored, set STATUS.ADDR_ERR.
//
// spi_pkg::ADDR_* names are ADDRESSES (constants). The lower-case names
// below (scratch, led_lo, ...) are the STORAGE flip-flops.
//
// Package items are referenced as spi_pkg::NAME rather than with
// `import spi_pkg::*;` because Yosys does not support the import keyword.
// -----------------------------------------------------------------------------
module reg_file (
    input  logic        clk,
    input  logic        rst_n,

    // ---- From spi_slave ----
    input  logic [6:0]  addr,
    input  logic [7:0]  wr_data,
    input  logic        wr_en,          // 1-cycle write pulse
    input  logic        rd_en,          // 1-cycle read pulse (only used for ADDR_ERR)
    output logic [7:0]  rd_data,        // combinational read of addr
    input  logic        frame_err_set,  // 1-cycle pulse
    input  logic        txn_inc,        // 1-cycle pulse

    // ---- Board I/O ----
    input  logic [9:0]  sw,             // already synchronized in spi_top
    output logic [9:0]  ledr,
    output logic [23:0] hex_digits      // six 4-bit digits: [3:0]=HEX0 ... [23:20]=HEX5
);

    // ---- Storage -------------------------------------------------------------
    logic [7:0] scratch;
    logic [7:0] led_lo;
    logic [1:0] led_hi;        // only 2 bits are real
    logic [7:0] hex10, hex32, hex54;
    logic [1:0] status;        // [STATUS_FRAME_ERR], [STATUS_ADDR_ERR]
    logic [7:0] txn_count;

    logic       addr_valid;    // 1 when addr is a mapped register (0x00-0x0B)

    // Compare the incoming address against the last mapped address.
    assign addr_valid = (addr <= spi_pkg::ADDR_LAST);

    // ---- Writable registers ---------------------------------------------------
    // Address decides WHICH storage register gets wr_data.
    // RO and unmapped addresses fall into default: nothing is written.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scratch <= '0;
            led_lo  <= '0;
            led_hi  <= '0;
            hex10   <= '0;
            hex32   <= '0;
            hex54   <= '0;
        end
        else if (wr_en) begin
            case (addr)
                spi_pkg::ADDR_SCRATCH: scratch <= wr_data;
                spi_pkg::ADDR_LED_LO:  led_lo  <= wr_data;
                spi_pkg::ADDR_LED_HI:  led_hi  <= wr_data[1:0];   // only 2 real bits
                spi_pkg::ADDR_HEX10:   hex10   <= wr_data;
                spi_pkg::ADDR_HEX32:   hex32   <= wr_data;
                spi_pkg::ADDR_HEX54:   hex54   <= wr_data;
                default: ;                                         // RO / unmapped: ignore
            endcase
        end
    end

    // ---- STATUS (sticky flags, write-1-to-clear) -----------------------------
    // status_set : bits to set this cycle (error events)
    // status_clr : bits to clear this cycle (a write of 1s to STATUS)
    // Next value = (keep old bits, minus cleared ones) OR newly set ones.
    // OR-ing the sets last means SET WINS if both happen in the same cycle,
    // so an error can never be silently lost.
    logic [1:0] status_set;
    logic [1:0] status_clr;

    // Plain assigns (not always_comb) - Icarus doesn't support bit-selects
    // inside always_* blocks.
    assign status_set[spi_pkg::STATUS_FRAME_ERR] = frame_err_set;
    assign status_set[spi_pkg::STATUS_ADDR_ERR]  = (wr_en || rd_en) && !addr_valid;

    assign status_clr = (wr_en && addr == spi_pkg::ADDR_STATUS) ? wr_data[1:0] : 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) status <= '0;                                  // no errors after reset
        else        status <= (status & ~status_clr) | status_set; // sticky: holds until cleared
    end

    // ---- TXN_COUNT -----------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       txn_count <= '0;
        else if (txn_inc) txn_count <= txn_count + 1'b1;   // wraps 255 -> 0
    end

    // ---- Read mux (combinational) --------------------------------------------
    // Switch values split outside the always_comb (Icarus bit-select limitation).
    logic [7:0] sw_lo_val, sw_hi_val;
    assign sw_lo_val = sw[7:0];
    assign sw_hi_val = {6'b0, sw[9:8]};

    // Default first so every path assigns rd_data (no latch).
    always_comb begin
        rd_data = 8'h00;
        case (addr)
            spi_pkg::ADDR_ID:        rd_data = spi_pkg::ID_VALUE;
            spi_pkg::ADDR_VERSION:   rd_data = spi_pkg::VERSION_VALUE;
            spi_pkg::ADDR_STATUS:    rd_data = {6'b0, status};
            spi_pkg::ADDR_TXN_COUNT: rd_data = txn_count;
            spi_pkg::ADDR_SCRATCH:   rd_data = scratch;
            spi_pkg::ADDR_LED_LO:    rd_data = led_lo;
            spi_pkg::ADDR_LED_HI:    rd_data = {6'b0, led_hi};
            spi_pkg::ADDR_HEX10:     rd_data = hex10;
            spi_pkg::ADDR_HEX32:     rd_data = hex32;
            spi_pkg::ADDR_HEX54:     rd_data = hex54;
            spi_pkg::ADDR_SW_LO:     rd_data = sw_lo_val;
            spi_pkg::ADDR_SW_HI:     rd_data = sw_hi_val;
            default:                 rd_data = 8'h00;     // unmapped reads 0
        endcase
    end

    // ---- Outputs to the board -------------------------------------------------
    assign ledr       = {led_hi, led_lo};          // 2 + 8 = 10 bits
    assign hex_digits = {hex54, hex32, hex10};     // HEX5..HEX0, 4 bits each

endmodule
