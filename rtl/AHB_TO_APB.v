module AHB_TO_APB#(
    parameter   ADDRWIDTH = 16,
    parameter   WRITE_REG = 1,
    parameter   READ_REG = 1
)
(
    //系统信号
    input                       HCLK,
    input                       HRESETn,
    input                       PCLKEN,     //PCLK enable signal

    //AHB总线信号
    //和数据本身紧密相关的数据地址控制信息信号
    input                       HWRITE,
    input       [31:0]          HWDATA,
    input       [ADDRWIDTH-1:0] HADDR,
    output      [31:0]          HRDATA,
    input       [2:0]           HSIZE,          //输入进来，被用来给PSTRB加工的
    input       [3:0]           HPROT,          //输入进来为PPROT加工          

    //控制整个流程的重要信号
    input                       HSEL,
    input       [1:0]           HTRANS,
    
    //握手反馈信号
    input                       HREADY,         //其实就是HreadyIN，代表总线上没有人占用                
    output      [1:0]           HRESP,          //
    output                      HREADYOUT,

    //APB总线信号
    output                      PWRITE,
    output      [ADDRWIDTH-1:0] PADDR,
    output      [31:0]          PWDATA,
    input       [31:0]          PRDATA,
    output      [3:0]           PSTRB,


    output                      PENABLE,
    output                      PSEL,
    input                       PSLVERR,
    output      [2:0]           PPROT,
    input                       PREADY          //slave的准备状态, 是从机用来反压主机的，APB_slave的响应信号
);
    //PREADY是从机输出给主机的，告知主机当前从机是否空闲
    //HREADY是主机告诉从机的，代表总线是否空闲
    //HREADYOUT是从机输出给主机（或者选择器）的，告知主机（或者选择器）当前从机是否空闲
    //HRESP也是从机告诉主机,传输是否有错

    //传输7状态
    `define         IDLE        3'b000          
    `define         WAIT        3'b001          //传输等待状态，等待输入数据寄存1拍； 写寄存状态
    `define         TRAN1       3'b010          //传输建立状态，此状态设置PSEL为1
    `define         TRAN2       3'b011          //传输状态, 在该状态完成传输，PENABLE设置为1
    `define         ENDOK       3'b100          //读寄存状态
    //
    //AHB总线的错误处理需要两个状态处理
    //因为当AHB接收到HRESP为ERROR时，下一个要传输的地址已经被广播到总线上的各个地方（因为这时候HREADY还是低电平）
    //因而需要再多一个周期，重新设置状态
    `define         ERROR1      3'b101          
    `define         ERROR2      3'b110
    //不合法，不应该出现的状态
    `define         ILLEGAL     3'b111
    wire    wdata_reg_cfg = (WRITE_REG==1) ? 1 :0;
    wire    rdata_reg_cfg = (READ_REG==1) ? 1 :0;

    //状态机
    reg         [2:0]           nstate;        
    reg         [2:0]           cstate;

    //APB_Bridge_Select
    wire    apb_sel = HSEL & HTRANS[1] & HREADY ; //选中、带传输、AHB总线空闲，才能发起一次传输  
    wire    apb_tran_done = PREADY & (cstate == 3'b011); //APB传输完成，空闲下来了
    //ENDOK是读寄存状态，其实不是传输完成状态
    //PSLVERR会在TRAN2阶段的时候返回，当PSLVERR拉高时，将进入错误状态（持续两个周期），此时HRESP将拉高（反映ERROR）
    
    //***************************************
    //******对从AHB获得的信号进行处理********
    //***************************************
    reg                         hwrite_reg;
    reg         [ADDRWIDTH-1:0] haddr_reg;

    reg         [2:0]           pprot_reg;
    wire        [2:0]           pprot_next;
    assign pprot_next[0] = HPROT[1];        //PPROT最低为是特权模式，对应HPROT的[1]是特权模式
    assign pprot_next[1] = 1'b0;            //安全访问与不安全访问，默认0
    assign pprot_next[2] = !HPROT[0];       //数据访问还是指令访问       

    reg         [3:0]           pstrb_reg;
    wire        [3:0]           pstrb_next;

    //HSIZE[1] 代表位宽是32,此时全部选中
    //HSIZE[0] 代表位宽是16,由HADDR[1]选择是上两位还是下两位
    //~HSIZE[0] 代表位宽是8， 由具体HADDR值选中是哪一位
    //                       写状态    32位情况    16位情况                 8位情况
    assign  pstrb_next[0]  = HWRITE & (HSIZE[1] | (HSIZE[0]&~HADDR[1]) | (~HSIZE[0]&(HADDR[1:0]==2'b00)));
    assign  pstrb_next[1]  = HWRITE & (HSIZE[1] | (HSIZE[0]&~HADDR[1]) | (~HSIZE[0]&(HADDR[1:0]==2'b01)));
    assign  pstrb_next[2]  = HWRITE & (HSIZE[1] | (HSIZE[0]& HADDR[1]) | (~HSIZE[0]&(HADDR[1:0]==2'b10)));
    assign  pstrb_next[3]  = HWRITE & (HSIZE[1] | (HSIZE[0]& HADDR[1]) | (~HSIZE[0]&(HADDR[1:0]==2'b11)));
    
    //首先不管怎么样，地址和控制信号都要打拍采样
    always @(posedge HCLK or negedge HRESETn) begin
        if(!HRESETn) begin
            hwrite_reg <= 0;
            haddr_reg <= 0;
            pstrb_reg <= 0;
            pprot_reg <= 0;
        end
        else if(apb_sel) begin
            hwrite_reg <= HWRITE;
            haddr_reg <= HADDR;
            pstrb_reg <= pstrb_next;
            pprot_reg <= pprot_next;
        end
    end

    //***************写数据寄存***************
    //这段代码我仍然认为是源码中的神中神
    reg     sample_wdata_reg;
    wire    sample_wdata_set = apb_sel & HWRITE & wdata_reg_cfg ;
    wire    sample_wdata_clr = sample_wdata_reg & PCLKEN ; 

    always @(posedge HCLK or negedge HRESETn) begin
        if(!HRESETn)
            sample_wdata_reg <= 0;
        else if(sample_wdata_set | sample_wdata_clr)
            sample_wdata_reg <= sample_wdata_set;
    end

    reg     [31:0]          hwdata_reg;
    always @(posedge HCLK or negedge HRESETn) begin
        if(!HRESETn)
            hwdata_reg <= 0;
        else if(sample_wdata_reg & wdata_reg_cfg & PCLKEN)
            hwdata_reg <= HWDATA;
    end
    //****************************************
    
    //***************读数据寄存***************
    reg     [31:0]          prdata_reg;
    always @(posedge HCLK or negedge HRESETn) begin
        if(!HRESETn)
            prdata_reg <= 0;
        else if(apb_tran_done & rdata_reg_cfg & PCLKEN)
            prdata_reg <= PRDATA;
    end 
    //****************************************
    
    //***************************************
    //*********对状态机进行指示**************
    //***************************************
    always @(posedge HCLK or negedge HRESETn) begin
        if(!HRESETn) 
            cstate <= `IDLE;
        else    
            cstate <= nstate;
    end
    
    always @(cstate or PCLKEN or apb_sel or HWRITE or wdata_reg_cfg or rdata_reg_cfg or PSLVERR or PREADY )begin
        case (cstate)
            `IDLE: begin
                //IDLE有两种跳转，一个是没有写寄存，跳到TRAN1，一个是有写寄存，跳到WAIT
                
                if(PCLKEN & apb_sel & ~(wdata_reg_cfg & HWRITE))
                    nstate = `TRAN1 ;  //如果不是写状态，跳过WAIT；如果没有设置写状态寄存，同样跳过WAIT 
                else if(apb_sel)
                    nstate = `WAIT;    //设置了写状态寄存，将跳转到WAIT
                                       //WAIT状态下, 地址与控制将寄存，然后在TRAN状态下，写数据会寄存
                                       //如果没有写状态寄存，地址与控制将在TRAN状态下寄存，写数据直接由HWDATA输出
                else 
                    nstate = `IDLE;
            end

            `WAIT: begin
                if(PCLKEN)
                    nstate = `TRAN1;   //TRAN1时会拉高PSEL，这时候需要经过PENABLE才能切换到TRAN1
                                       //因为这里涉及到了APB域的问题了，所以要在PENABLE有效的情况下才能切换
                else
                    nstate = `WAIT;
            end

            `TRAN1: begin
                if(PCLKEN)
                    nstate = `TRAN2;   //与上面同理，这里同样涉及到了APB域的事情了，所以必须要在PCLKEN的那个时候切换
                else
                    nstate = `TRAN1;    
            end

            `TRAN2: begin
                //到TRAN2的时候，数据会完成传输，这时候有五种情况
                //1. 传输错误，跳转到ERROR1
                //2. 传输成功且无读数据寄存,且有传输，跳转到WAIT或TRAN1
                //3. 传输成功且无读数据寄存,且无传输，跳转到IDLE
                //4. 传输成功且有读数据寄存，跳转到ENDOK

                //要从TRAN2跳转出来，必须要在PCLKEN使能阶段，并且PREADY拉高。
                //PREADY拉高代表APB已经完成传输了，同时也是APB从设备已经空闲
                if(PSLVERR & PREADY & PCLKEN) //PREADY代表APB从设备已经空闲，同时也意味着，传输完成
                    nstate = `ERROR1;

                else if((!PSLVERR) & PREADY & PCLKEN) begin
                    if(rdata_reg_cfg)       //有读数据寄存
                        nstate = `ENDOK;
                    else if(apb_sel) begin        //无读数据寄存但有数据要传输
                        if(wdata_reg_cfg == 1)
                            nstate = `WAIT;       //如果有写寄存要求，跳转到`WAIT
                        else 
                            nstate = `TRAN1;      //如果没有写寄存要求，那么跳转到`TRAN1
                    end
                    else 
                        nstate = `IDLE;     //无读数据寄存且无数据要传输 
                end

                else nstate = `TRAN2;
            end

            `ENDOK: begin
                //这里需要理解一件事，结束之后有三种跳转状态
                //1. 跳转到IDLE
                //2. 跳转到WAIT
                //3. 跳转到TRAN1
                if(apb_sel & PCLKEN & !(HWRITE & wdata_reg_cfg))         //这里的跳转条件与IDLE跳转到TRAN1的条件一样
                    nstate = `TRAN1;
                else if(apb_sel)
                    nstate = `WAIT;
                else 
                    nstate = `IDLE;
                //这里会直接跳转, 不会保持在这个状态
            end

            `ERROR1: begin
                nstate = `ERROR2;
            end

            `ERROR2: begin
                 if(apb_sel & PCLKEN & !(HWRITE & wdata_reg_cfg))         //这里的跳转条件与IDLE跳转到TRAN1的条件一样
                    nstate = `TRAN1;
                else if(apb_sel)
                    nstate = `WAIT;
                else 
                    nstate = `IDLE;               
            end
            //IDLE、ENDOK、ERROR2内部的代码是一样的跳转的条件
        endcase
    end


    //******************************
    //*****输出信号的处理与赋值*****
    //******************************

    assign HRDATA = rdata_reg_cfg ? prdata_reg : PRDATA; 
    assign PWDATA = wdata_reg_cfg ? hwdata_reg : HWDATA;
    assign PWRITE = hwrite_reg;
    assign PADDR = haddr_reg;
    assign PSTRB = pstrb_reg;
    assign PPROT = pprot_reg;
    assign HRESP[0] = ((cstate == `ERROR1) | (cstate == `ERROR2)) ? 1 : 0; 
    assign HRESP[1] = 0;

    assign HREADYOUT = (cstate == `IDLE)                       ? 1 :
                       ((cstate == `WAIT) | (cstate ==`TRAN1)) ? 0 :
                       (cstate == `TRAN2)                      ? (~rdata_reg_cfg & (~PSLVERR) & PREADY & PCLKEN) :
                       (cstate == `ENDOK)                      ? 1 :
                       (cstate == `ERROR1)                     ? 0 :
                       (cstate == `ERROR2)                     ? 1 : 1'bx;
    assign PENABLE = (cstate == `TRAN2) ; 
    assign PSEL= ((cstate == `TRAN1) | (cstate == `TRAN2));

endmodule


       








