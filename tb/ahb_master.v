//------------------------------------------------------------------------------
// File                     : ahb_master.v
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

`define SINGLE_TEST
`define BURST_TEST

module ahb_master #( 
    //----------------------------------
    // Paramter Declarations
    //----------------------------------
    parameter                           START_ADDR = 0,
    parameter                           DEPTH_IN_BYTES = 32'h100,
    parameter                           END_ADDR = START_ADDR+DEPTH_IN_BYTES-1
)
(
    //----------------------------------
    // IO Declarations
    //----------------------------------
    input wire                          HRESETn,        
    input wire                          HCLK,
    output reg [31:0]                   HADDR,
    output reg [1:0]                    HTRANS,
    output reg                          HWRITE,
    output reg [2:0]                    HSIZE,
    output reg [2:0]                    HBURST,
    output reg [3:0]            	HPROT,
    output reg [31:0]                   HWDATA,
    input wire [31:0]                   HRDATA,
    input wire [1:0]                    HRESP,
    input wire                          HREADY
);

    //----------------------------------
    // Variable Declarations
    //----------------------------------
    reg [31:0]                          data_burst[0:1023];

    //----------------------------------
    // Start of Main Code
    //----------------------------------
    initial begin
        HADDR = 0;
        HTRANS = 0;
        HPROT = 0;
        HWRITE = 0;
        HSIZE = 0;
        HBURST = 0;
        HWDATA = 0;
        while(HRESETn === 1'bx) @(posedge HCLK);
        while(HRESETn === 1'b1) @(posedge HCLK);
        while(HRESETn === 1'b0) @(posedge HCLK);

    `ifdef SINGLE_TEST
        repeat(3) @(posedge HCLK);              //wait three clock cycle
        memory_test(START_ADDR, END_ADDR, 1);
        memory_test(START_ADDR, END_ADDR, 2);
        memory_test(START_ADDR, END_ADDR, 4);   //(start_addr, end_addr, size)
    `endif

    `ifdef BURST_TEST
        repeat(5) @(posedge HCLK);              //wait five clock cycle
        memory_test_burst(START_ADDR, END_ADDR, 1);
        memory_test_burst(START_ADDR, END_ADDR, 2);
        memory_test_burst(START_ADDR, END_ADDR, 4);
        memory_test_burst(START_ADDR, END_ADDR, 6);
        memory_test_burst(START_ADDR, END_ADDR, 8);
        memory_test_burst(START_ADDR, END_ADDR, 10);
        memory_test_burst(START_ADDR, END_ADDR, 16);
        memory_test_burst(START_ADDR, END_ADDR, 32);
        memory_test_burst(START_ADDR, END_ADDR, 64);
        memory_test_burst(START_ADDR, END_ADDR, 128);
        memory_test_burst(START_ADDR, END_ADDR, 255);
        repeat(5) @(posedge HCLK);              //wait another five clock cycle
    `endif
        $finish(2);
    end
    
    //-----------------------------------------------------------------------
    // Single transfer test 
    //-----------------------------------------------------------------------
    task memory_test;
        input [31:0]                start; // start address
        input [31:0]                finish; // end address
        input [2:0]                 size; // data size: 1, 2, 4, work unit:byte
        
        integer                     i; 
        integer                     error;
        reg [31:0]                  data; 
        reg [31:0]                  gen;   //random seed 
        reg [31:0]                  got;   //out of ahb_read
        reg [31:0]                  reposit[START_ADDR:END_ADDR];
    begin
        $display("%m: read-after-write test with %d-byte access", size);
        error = 0;
        gen = $random(7);
        for (i = start; i < (finish-size+1); i = i + size) begin
            gen = $random & ~32'b0;
            data = align(i, gen, size);         //addr data size, selection of bytes according to addr[1:0]
            // size is to determine how many bytes to display, and addr[1:0] is which ones to display.
            // data是随机种子gen经过字节选通后处理的数据
            ahb_write(i, size, data);
            ahb_read(i, size, got);
            //got是读数据，但是要经过字节选通（与其说是字节选通不如说是字节掩码）
            got = align(i, got, size);
            if (got !== data) begin
                //!== 比 !=严格，前者能比较数据类型
                $display("[%10d] %m A:%x D:%x, but %x expected", $time, i, got, data);
                error = error + 1;
            end
        end
        if (error == 0)
            $display("[%10d] %m OK: from %x to %x", $time, start, finish);

        $display("%m read-all-after-write-all with %d-byte access", size);
        error = 0;
        gen = $random(1);
        for (i = start; i < (finish-size+1); i = i + size) begin
            gen = {$random} & ~32'b0;
            data = align(i, gen, size);     
            reposit[i] = data;
            ahb_write(i, size, data);
        end
        for (i = start; i < (finish-size+1); i = i + size) begin
            data = reposit[i];
            ahb_read(i, size, got);
            got = align(i, got, size);
            if (got !== data) begin
                $display("[%10d] %m A:%x D:%x, but %x expected", $time, i, got, data);
                error = error + 1;
            end
        end
        if (error == 0)
            $display("[%10d] %m OK: from %x to %x", $time, start, finish);
    end
    endtask
    
    //-----------------------------------------------------------------------
    // Burst transfer test 
    //-----------------------------------------------------------------------
    task memory_test_burst;
        input [31:0]                start; // start address
        input [31:0]                finish; // end address
        input [7:0]                 leng; // burst length
        
        integer                     i; 
        integer                     j; 
        integer                     k; 
        integer                     r; 
        integer                     error; 

        reg [31:0]                  data; 
        reg [31:0]                  gen;    //'gen' is a 32-bit register used to store the random number seed
        //'gen' is used to generate two sets of  random number
        reg [31:0]                  got;
        reg [31:0]                  reposit[0:1023];    
        integer                     seed;               
    begin
        $display("[%10d] %m: read-all-after-write-all burst test with %d-beat access", $time, leng);
        error = 0;
        seed  = 111;
        gen = $random(seed);
        k = 0;
        if (finish > (start+leng*4)) begin

            for (i = start; i < (finish-(leng*4)+1); i = i + leng*4) begin
                for (j = 0; j < leng; j = j + 1) begin
                    data_burst[j] = $random;        //data_burst is memory
                    reposit[j+k*leng] = data_burst[j];
                end
                @(posedge HCLK);
                ahb_write_burst(i, leng);
                k = k + 1;
            end

            gen = $random(seed);
            k = 0;
            for (i = start; i < (finish-(leng*4)+1); i = i + leng*4) begin
                @(posedge HCLK);
                ahb_read_burst(i, leng);
                for (j = 0; j < leng; j = j + 1) begin
                    if (data_burst[j] != reposit[j+k*leng]) begin
                        error = error+1;
                        $display("[%10d] %m A=%hh D=%hh, but %hh expected", $time, i+j*leng, data_burst[j], reposit[j+k*leng]);
                    end
                end
                k = k + 1;
                r = $random & 8'h0F;
                repeat(r) @(posedge HCLK);
            end
            if (error == 0)
                $display("%m %d-length burst read-after-write OK: from %hh to %hh",leng, start, finish);
        end 
        else begin
            $display("%m %d-length burst read-after-write from %hh to %hh ???",leng, start, finish);
        end
    end
    endtask
    
    //-----------------------------------------------------------------------
    // As AMBA AHB bus uses non-justified data bus scheme, data should be
    // aligned according to the address.
    //-----------------------------------------------------------------------
    function [31:0] align;
        input [ 1:0]                addr;
        input [31:0]                data;
        input [ 2:0]                size; // num of bytes
    begin
    `ifdef BIG_ENDIAN
        case (size)
            1 : 
                case (addr[1:0]) //one byte
                    0 : align = data & 32'hFF00_0000;
                    1 : align = data & 32'h00FF_0000;
                    2 : align = data & 32'h0000_FF00;
                    3 : align = data & 32'h0000_00FF;
                endcase                
                                       
            2 :                        
                case (addr[1])   //two bytes     
                    0 : align = data & 32'hFFFF_0000;
                    1 : align = data & 32'h0000_FFFF;
                endcase
                
            4 :                  //one word
                align = data&32'hFFFF_FFFF;
            default : 
                $display($time,,"%m ERROR %d-byte not supported for size", size);
        endcase
    `else
        case (size)
            1 : 
                case (addr[1:0])
                    0 : align = data & 32'h0000_00FF;
                    1 : align = data & 32'h0000_FF00;
                    2 : align = data & 32'h00FF_0000;
                    3 : align = data & 32'hFF00_0000;
                endcase
                
            2 : 
                case (addr[1])
                    0 : align = data & 32'h0000_FFFF;
                    1 : align = data & 32'hFFFF_0000;
                endcase
                
            4 : 
                align = data&32'hFFFF_FFFF;
            default : 
                $display($time,,"%m ERROR %d-byte not supported for size", size);
        endcase
    `endif
    end
    endfunction

//------------------------------------------------------------------------------
// File                     : ahb_transaction_tasks.v
// Author                   : TG
// Key Words                :
// Modification History     :
//      Date        By        Version        Change Description
//      2022-04-26  TG        1.0            original
//
// Editor                   : VSCode, Tab Size(4)
// Description              : AHB Transaction Tasks.
//
//------------------------------------------------------------------------------
`ifndef __AHB_TRANSACTION_TASKS_V__
`define __AHB_TRANSACTION_TASKS_V__

//-----------------------------------------------------------------------
// AHB Read Task
//-----------------------------------------------------------------------
task ahb_read;
    input [31:0]                address;
    input [2:0]                 size;
    output [31:0]               data;
begin
    @(posedge HCLK);
    HADDR <= #1 address;
    HPROT <= #1 4'b0001; // DATA
    HTRANS <= #1 2'b10; // NONSEQ;
    HBURST <= #1 3'b000; // SINGLE;
    HWRITE <= #1 1'b0; // READ;
    case (size)
        1 : HSIZE <= #1 3'b000; // BYTE;
        2 : HSIZE <= #1 3'b001; // HWORD;
        4 : HSIZE <= #1 3'b010; // WORD;
        default : 
            $display($time,, "ERROR: unsupported transfer size: %d-byte", size);
    endcase
    
    @(posedge HCLK);
    while (HREADY !== 1'b1) @(posedge HCLK);
    HTRANS <= #1 2'b0; // IDLE
    @(posedge HCLK);
    while (HREADY === 0) @(posedge HCLK);
    data = HRDATA; // must be blocking
    if (HRESP != 2'b00) 
        $display($time,, "ERROR: non OK response for read");
    @(posedge HCLK);
end
endtask

//-----------------------------------------------------------------------
// AHB Write Task
//-----------------------------------------------------------------------
task ahb_write;
    input [31:0]                address;
    input [2:0]                 size;
    input [31:0]                data;
begin
    @(posedge HCLK);
    HADDR <= #1 address;
    HPROT <= #1 4'b0001; // DATA
    HTRANS <= #1 2'b10; // NONSEQ
    HBURST <= #1 3'b000; // SINGLE
    HWRITE <= #1 1'b1; // WRITE
    case (size)
        1 : HSIZE <= #1 3'b000; // BYTE
        2 : HSIZE <= #1 3'b001; // HWORD
        4 : HSIZE <= #1 3'b010; // WORD
        default : 
            $display($time,, "ERROR: unsupported transfer size: %d-byte", size);
    endcase
    
    @(posedge HCLK);
    while (HREADY !== 1) @(posedge HCLK);
    HWDATA <= #1 data;
    HTRANS <= #1 2'b0; // IDLE
    @(posedge HCLK);
    while (HREADY === 0) @(posedge HCLK);
    if (HRESP != 2'b00) 
        $display($time,, "ERROR: non OK response write");
    @(posedge HCLK);
end
endtask

//-----------------------------------------------------------------------
// AHB Read Burst Task
//-----------------------------------------------------------------------
task ahb_read_burst;
    input [31:0]                addr;
    input [31:0]                leng;
    
    integer                     i; 
    integer                     ln; 
    integer                     k;
begin
    k = 0;
    @(posedge HCLK);
    HADDR <= #1 addr; 
    addr = addr + 4;
    HTRANS <= #1 2'b10; // NONSEQ 突发传输的首次传输
    //
    if (leng >= 16) begin 
        HBURST <= #1 3'b111; // INCR16
        ln = 16; 
    end
    else if (leng >= 8) begin 
        HBURST <= #1 3'b101; // INCR8
        ln = 8; 
    end
    else if (leng >= 4) begin 
        HBURST <= #1 3'b011; // INCR4
        ln = 4; 
    end 
    else begin 
        HBURST <= #1 3'b001; // INCR
        ln = leng; 
    end 

    HWRITE <= #1 1'b0; // READ
    HSIZE <= #1 3'b010; // WORD
    //
    //
    //
    @(posedge HCLK);
    while (HREADY == 1'b0) @(posedge HCLK);     //不能使用流水线啊
    while (leng > 0) begin
        for (i = 0; i < ln-1; i = i + 1) begin
            HADDR <= #1 addr; 
            addr = addr + 4;
            HTRANS <= #1 2'b11; // SEQ;
            @(posedge HCLK);

            while (HREADY == 1'b0) @(posedge HCLK);
            data_burst[k%1024] <= HRDATA;
            k = k + 1;

        end
        leng = leng - ln;
        if (leng == 0) begin
            HADDR <= #1 0;
            HTRANS <= #1 0;
            HBURST <= #1 0;
            HWRITE <= #1 0;
            HSIZE <= #1 0;
        end 
        else begin
            HADDR <= #1 addr; 
            addr = addr + 4;
            HTRANS <= #1 2'b10; // NONSEQ
            if (leng >= 16) begin 
                HBURST <= #1 3'b111; // INCR16
                ln = 16; 
            end 
            else if (leng >= 8) begin 
                HBURST <= #1 3'b101; // INCR8
                ln = 8; 
            end 
            else if (leng >= 4) begin 
                HBURST <= #1 3'b011; // INCR4
                ln = 4; 
            end 
            else begin 
                HBURST <= #1 3'b001; // INCR1 
                ln = leng; 
            end
            @(posedge HCLK);
            while (HREADY == 0) @(posedge HCLK);
            data_burst[k%1024] = HRDATA; // must be blocking
            k = k + 1;
        end
    end
    @(posedge HCLK);
    while (HREADY == 0) @(posedge HCLK);
    data_burst[k%1024] = HRDATA; // must be blocking
end
endtask

//-----------------------------------------------------------------------
// AHB Write Burst Task
// It takes suitable burst first and then incremental.
//-----------------------------------------------------------------------
task ahb_write_burst;
    input [31:0]                addr;
    input [31:0]                leng;
    integer                     i; 
    integer                     j; 
    integer                     ln;
begin
    j = 0;
    ln = 0;
    @(posedge HCLK);
    while (leng > 0) begin
        HADDR <= #1 addr; 
        addr = addr + 4;
        HTRANS <= #1 2'b10; // NONSEQ
        if (leng >= 16) begin 
            HBURST <= #1 3'b111; // INCR16
            ln = 16; 
        end
        else if (leng >= 8) begin 
            HBURST <= #1 3'b101; // INCR8
            ln = 8; 
        end
        else if (leng >= 4) begin 
            HBURST <= #1 3'b011; // INCR4
            ln = 4; 
        end
        else begin 
            HBURST <= #1 3'b001; // INCR
            ln = leng; 
        end
        HWRITE <= #1 1'b1; // WRITE
        HSIZE <= #1 3'b010; // WORD
        for (i = 0; i < ln-1; i = i + 1) begin
            @(posedge HCLK);
            while (HREADY == 1'b0) @(posedge HCLK);
            HWDATA <= #1 data_burst[(j+i)%1024];
            HADDR <= #1 addr; 
            addr = addr + 4;
            HTRANS <= #1 2'b11; // SEQ;
            while (HREADY == 1'b0) @(posedge HCLK);
        end
        @(posedge HCLK);
        while (HREADY == 0) @(posedge HCLK);
        HWDATA <= #1 data_burst[(j+i)%1024];
        if (ln == leng) begin
            HADDR <= #1 0;
            HTRANS <= #1 0;
            HBURST <= #1 0;
            HWRITE <= #1 0;
            HSIZE <= #1 0;
        end
        leng = leng - ln;
        j = j + ln;
    end
    @(posedge HCLK);
    while (HREADY == 0) @(posedge HCLK);
    if (HRESP != 2'b00) begin // OKAY
        $display($time,, "ERROR: non OK response write");
    end
`ifdef DEBUG
    $display($time,, "INFO: write(%x, %d, %x)", addr, size, data);
`endif
    HWDATA <= #1 0;
    @(posedge HCLK);
end
endtask

`endif
endmodule
