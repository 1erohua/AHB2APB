//------------------------------------------------------------------------------
// File                     : apb_mem.v
// Author                   : TG
// Key Words                :
// Modification History     :
//      Date        By        Version        Change Description
//      2022-04-28  TG        1.0            original
//
// Editor                   : VSCode, Tab Size(4)
// Description              : Simplified memory with AMBA APB.
//
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

`define AMBA_APB3
`define AMBA_APB4

module apb_mem #(
    parameter                   P_SLV_ID = 0,
    parameter                   ADDRWIDTH = 32,
    parameter                   P_SIZE_IN_BYTES = 1024, // memory depth
    parameter                   P_DELAY = 0 // reponse delay
    // P_DELAY指的是延迟的周期数
    //count <= count + 1; //整个周期加一次
    //if (count >= P_DELAY)
)  
(

    //Functional
    //1. a simple memory store, with strobe
    //2. with periodic delays ready
    //3. optional amba3 and amba4 protocols

    
    //----------------------------------
    // IO Declarations
    //----------------------------------
`ifdef AMBA_APB3
    output wire                 PREADY,
    output wire                 PSLVERR,
`endif          

`ifdef AMBA_APB4            
    input  wire [2:0]           PPROT,
    input  wire [3:0]           PSTRB,
`endif          

    input  wire                 PRESETn,
    input  wire                 PCLK,
    input  wire                 PSEL,
    input  wire                 PENABLE,
    input  wire [ADDRWIDTH-1:0] PADDR,
    input  wire                 PWRITE,
    output reg  [31:0]          PRDATA = 32'h0,
    input  wire [31:0]          PWDATA
);

    //----------------------------------
    // Local Parameter Declarations
    //----------------------------------
    localparam                  DEPTH = (P_SIZE_IN_BYTES+3)/4;
    localparam                  AW = logb2(P_SIZE_IN_BYTES); //AW is log2N

    //----------------------------------
    // Variable Declarations
    //----------------------------------
`ifndef AMBA_APB3
    wire                        PREADY;
`else
    assign                      PSLVERR = 1'b0;
`endif

`ifndef AMBA_APB4               //if AMBA_APB4 is not defined, the default byte select pass is fully open
    wire [3:0]                  PSTRB = 4'hF;
`endif

    reg [7:0]                   mem0[0:DEPTH-1];
    reg [7:0]                   mem1[0:DEPTH-1];
    reg [7:0]                   mem2[0:DEPTH-1];
    reg [7:0]                   mem3[0:DEPTH-1];

    wire [AW-3:0]               TA = PADDR[AW-1:2];

    //----------------------------------
    // Start of Main Code
    //----------------------------------
    //--------------------------------------------------------------------------
    // write transfer
    //             ____      ____      ____
    // PCLK    ___|    |____|    |____|    |_
    //         ____ ___________________ _____
    // PADDR   ____X__A________________X_____
    //         ____ ___________________ _____
    // PWDATA  ____X__DW_______________X_____
    //              ___________________
    // PWRITE  ____|                   |_____
    //              ___________________
    // PSEL    ____|                   |_____
    //                        _________
    // PENABLE ______________|         |_____
    //--------------------------------------------------------------------------
    always @(posedge PCLK) 
    begin
        if (PRESETn & PSEL & PENABLE & PWRITE & PREADY) begin
            if (PSTRB[0]) 
                mem0[TA] <= PWDATA[ 7: 0];
            if (PSTRB[1]) 
                mem1[TA] <= PWDATA[15: 8];
            if (PSTRB[2]) 
                mem2[TA] <= PWDATA[23:16];
            if (PSTRB[3]) 
                mem3[TA] <= PWDATA[31:24];
        end
    end

    //--------------------------------------------------------------------------
    // read
    //             ____      ____      ____
    // PCLK    ___|    |____|    |____|    |_
    //         ____ ___________________ _____
    // PADDR   ____X__A________________X_____
    //         ____           _________ _____
    // PRDATA  ____XXXXXXXXXXX__DR_____X_____
    //         ____                     _____
    // PWRITE  ____|___________________|_____
    //              ___________________
    // PSEL    ____|                   |_____
    //                        _________
    // PENABLE ______________|         |_____
    //--------------------------------------------------------------------------
    always @(posedge PCLK)
    begin
        if (PRESETn & PSEL & ~PENABLE & ~PWRITE) begin
            //read operation are not controlled by the write selector signal
            PRDATA[ 7: 0] <= mem0[TA];
            PRDATA[15: 8] <= mem1[TA];
            PRDATA[23:16] <= mem2[TA];
            PRDATA[31:24] <= mem3[TA];
        end
    end
    

    //generate ready with delay
`ifdef AMBA_APB3
    localparam                  ST_IDLE = 'h0,
                                ST_CNT  = 'h1,
                                ST_WAIT = 'h2;

    reg [7:0]                   count;
    reg                         ready;

    reg [1:0]                   state=ST_IDLE;

    //PREADY是否有延迟
    //默认没有延迟
    assign PREADY = (P_DELAY == 0) ? 1'b1 : ready;

    always @(posedge PCLK or negedge PRESETn) 
    begin
        if (PRESETn == 1'b0) begin
            count <= 'h0;
            ready <= 'b1;
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE : begin
                    if (PSEL && (P_DELAY > 0)) begin
                        ready <= 1'b0;
                        count <= 'h1;
                        state <= ST_CNT;
                    end 
                    else begin
                        ready <= 1'b1;
                    end
                end // ST_IDLE
                // when P_DELAY is 1, ready is 0 for one cycle

                ST_CNT : begin
                    count <= count + 1;
                    if (count >= P_DELAY) begin
                        count <= 'h0;
                        ready <= 1'b1;
                        state <= ST_WAIT;
                    end
                end // ST_CNT

                ST_WAIT : begin
                    ready <= 1'b1;
                    state <= ST_IDLE;
                end // ST_WAIT
                
                default : begin
                    ready <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end // if
    end // always
`else
    assign PREADY = 1'b1;
`endif

    // Calculate log-base2
// calculate the exponent of 2 for a number
    function integer logb2;
        input [31:0]            value;
        reg   [31:0]            tmp;
    begin
        tmp = value - 1;        //1023
        //1111_1111_11
        for (logb2 = 0; tmp > 0; logb2 = logb2 + 1) 
            tmp = tmp >> 1;
    end
    endfunction
    //return name is funtion name 

    // synopsys translate_off
`ifdef RIGOR
    always @(posedge PCLK or negedge PRESETn) 
    begin
        if (PRESETn == 1'b0) begin
        end 
        else begin
            if (PSEL & PENABLE) begin
                if (TA >= DEPTH) 
                    $display($time,,"%m: ERROR: out-of-bound 0x%x", PADDR);
            end
        end
    end
`endif
    // synopsys translate_on

endmodule
