// -----------------------------------------------------------------------------
// spi_pkg.sv  -  shared constants for the SPI register-file peripheral
//
// One place for the register map (objective.md section 5.1.1), used by both the
// RTL and the testbench, so the two can never disagree.
//
// Compile this file FIRST - every file that says `import spi_pkg::*;` needs it.
// -----------------------------------------------------------------------------
package spi_pkg;

    // ---- Register addresses (7 bits) ----------------------------------------
    localparam logic [6:0] ADDR_ID        = 7'h00;  // RO
    localparam logic [6:0] ADDR_VERSION   = 7'h01;  // RO
    localparam logic [6:0] ADDR_STATUS    = 7'h02;  // RO / W1C
    localparam logic [6:0] ADDR_TXN_COUNT = 7'h03;  // RO
    localparam logic [6:0] ADDR_SCRATCH   = 7'h04;  // RW
    localparam logic [6:0] ADDR_LED_LO    = 7'h05;  // RW  LEDR[7:0]
    localparam logic [6:0] ADDR_LED_HI    = 7'h06;  // RW  LEDR[9:8] in bits 1:0
    localparam logic [6:0] ADDR_HEX10     = 7'h07;  // RW  HEX1:HEX0
    localparam logic [6:0] ADDR_HEX32     = 7'h08;  // RW  HEX3:HEX2
    localparam logic [6:0] ADDR_HEX54     = 7'h09;  // RW  HEX5:HEX4
    localparam logic [6:0] ADDR_SW_LO     = 7'h0A;  // RO  SW[7:0]
    localparam logic [6:0] ADDR_SW_HI     = 7'h0B;  // RO  SW[9:8] in bits 1:0

    localparam logic [6:0] ADDR_LAST      = ADDR_SW_HI;   // anything above is unmapped

    // ---- Fixed values -------------------------------------------------------
    localparam logic [7:0] ID_VALUE       = 8'hA5;
    localparam logic [7:0] VERSION_VALUE  = 8'h01;

    // ---- STATUS bit positions -----------------------------------------------
    localparam int STATUS_FRAME_ERR = 0;
    localparam int STATUS_ADDR_ERR  = 1;

    // ---- Frame lengths (bits) -----------------------------------------------
    localparam int WRITE_FRAME_BITS = 16;
    localparam int READ_FRAME_BITS  = 24;

endpackage
