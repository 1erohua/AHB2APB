//------------------------------------------------------------------------------
// File                     : top_tb.v
// Author                   : TG
// Key Words                :
// Modification History     :
//      Date        By        Version        Change Description
//      2022-04-26  TG        1.0            original
//
// Editor                   : VSCode, Tab Size(4)
// Description              :
//
//------------------------------------------------------------------------------
`timescale 1ns / 1ps
`define VCS
`define amba_apb4
`define amba_apb3

module top_tb();
    //----------------------------------
    // Local Parameter Declarations
    //----------------------------------
    localparam                      AHB_CLK_PERIOD = 5; // Assuming AHB CLK to be 100MHz

    localparam                      SIZE_IN_BYTES = 2048;
    localparam                      ADDRWIDTH = 32;

    //----------------------------------
    // Variable Declarations
    //----------------------------------
    reg                             HCLK = 0;
    wire                            HWRITE;
    wire [1:0]                      HTRANS;
    wire [2:0]                      HSIZE;
    wire [2:0]                      HBURST;
    wire                            HREADYIN;
    wire [31:0]                     HADDR;
    wire [3:0]                      HPROT;
    wire [31:0]                     HWDATA;
    wire                            HREADYOUT;
    wire [1:0]                      HRESP;
    wire [31:0]                     HRDATA;
    reg                             HRESETn;
    wire                            HREADY;

    wire [ADDRWIDTH-1:0]            PADDR; // APB Address
    wire                            PENABLE; // APB Enable
    wire                            PWRITE; // APB Write
    wire [31:0]                     PWDATA; // APB write data
    wire                            PSEL; // APB Select
    wire                            PREADY;
    wire                            PSLVERR;         
    wire [2:0]                      PPROT;
    wire [3:0]                      PSTRB;
    wire [31:0]                     PRDATA;
    reg                             PCLK = 0;
    wire                             PCLKEN ;

    //----------------------------------
    // Start of Main Code
    //----------------------------------
    assign HREADY = HREADYOUT;

    //-----------------------------------------------------------------------
    // PCLK与PCLKEN
    //-----------------------------------------------------------------------
    always #AHB_CLK_PERIOD
        HCLK <= ~HCLK;
    always #(AHB_CLK_PERIOD)
        PCLK <= ~PCLK;
    
    assign PCLKEN = 1;
    //-----------------------------------------------------------------------
    // Generate HRESETn
    //-----------------------------------------------------------------------    
    initial begin
        HRESETn = 1'b0;
        repeat(5) @(posedge HCLK);
        HRESETn = 1'b1;
    end

    ahb_master #(
        .START_ADDR                 (32'h0),
        .DEPTH_IN_BYTES             (SIZE_IN_BYTES)
    )       
    u_ahb_master (     
        .HRESETn                    (HRESETn),
        .HCLK                       (HCLK),
        .HADDR                      (HADDR),
        .HPROT                      (HPROT),
        .HTRANS                     (HTRANS),
        .HWRITE                     (HWRITE),
        .HSIZE                      (HSIZE),
        .HBURST                     (HBURST),
        .HWDATA                     (HWDATA),
        .HRDATA                     (HRDATA),
        .HRESP                      (HRESP),
        .HREADY                     (HREADYOUT)
    );

    AHB_TO_APB #(
    .ADDRWIDTH ( ADDRWIDTH ),
    .WRITE_REG ( 1),
    .READ_REG ( 1))
    u_AHB_TO_APB (
    .HCLK                    ( HCLK                       ),
    .HRESETn                 ( HRESETn                    ),
    .PCLKEN                  ( PCLKEN                     ),
    .HWRITE                  ( HWRITE                     ),
    .HWDATA                  ( HWDATA     [31:0]          ),
    .HADDR                   ( HADDR      [ADDRWIDTH-1:0] ),
    .HSIZE                   ( HSIZE      [2:0]           ),
    .HPROT                   ( HPROT      [3:0]           ),
    .HSEL                    ( 1'b1),
    .HTRANS                  ( HTRANS     [1:0]           ),
    .HREADY                  ( HREADY                     ),
    .PRDATA                  ( PRDATA     [31:0]          ),
    .PSLVERR                 ( PSLVERR                    ),
    .PREADY                  ( PREADY                     ),

    .HRDATA                  ( HRDATA     [31:0]          ),
    .HRESP                   ( HRESP                      ),
    .HREADYOUT               ( HREADYOUT                  ),
    .PWRITE                  ( PWRITE                     ),
    .PADDR                   ( PADDR      [ADDRWIDTH-1:0] ),
    .PWDATA                  ( PWDATA     [31:0]          ),
    .PSTRB                   ( PSTRB      [3:0]           ),
    .PENABLE                 ( PENABLE                    ),
    .PSEL                    ( PSEL                       ),
    .PPROT                   ( PPROT      [2:0]           ));

    apb_mem #(
        .P_SLV_ID                   (0),
        .ADDRWIDTH                  (ADDRWIDTH),
        .P_SIZE_IN_BYTES            (SIZE_IN_BYTES),
        .P_DELAY                    (0)
    )
    u_apb_mem (
    `ifdef amba_apb3
        .PREADY                     (PREADY),
        .PSLVERR                    (PSLVERR),
    `endif
    `ifdef amba_apb4
        .PSTRB                      (PSTRB),
        .PPROT                      (PPROT),
    `endif
        .PRESETn                    (HRESETn),
        .PCLK                       (PCLK),
        .PSEL                       (PSEL),
        .PENABLE                    (PENABLE),
        .PADDR                      (PADDR),
        .PWRITE                     (PWRITE),
        .PRDATA                     (PRDATA),
        .PWDATA                     (PWDATA)
    );
    
`ifdef VCS
    initial begin
        $fsdbDumpfile("AHB_TO_APB.fsdb");
        $fsdbDumpvars;
    end
`endif

endmodule
