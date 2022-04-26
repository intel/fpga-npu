`include "npu.vh"


module top_sched # (
    // data width
    parameter EW       = `EW,    // element width
    parameter ACCW     = `ACCW,  // element width
    parameter DOTW     = `DOTW,  // # elemtns in vector
    // functional units
    parameter NTILE    = `NTILE, // # mvu tiles
    parameter NDPE     = `NDPE,  // # dpes
    parameter NMFU     = `NMFU,  // # mfus
    parameter NVRF     = `NVRF,  // # vrfs
    parameter NMRF     = `NMRF,  // # mrfs
    // VRF & MRF
    parameter VRFD     = `VRFD,  // VRF depth
    parameter VRFAW    = `VRFAW, // VRF address width
    parameter MRFD     = `MRFD,  // MRF depth
    parameter MRFAW    = `MRFAW, // MRF address width
    // instructions
    parameter NSIZE    = `NSIZE,
    parameter NSIZEW   = `NSIZEW,
    parameter NTAG     = `NTAG,
    parameter NTAGW    = `NTAGW,
    parameter DOT_PER_DSP = `DOT_PER_DSP,
    parameter PRIME_DOTW = `PRIME_DOTW,
    parameter NUM_DSP  = `NUM_DSP,
    parameter NUM_ACCUM= `NUM_ACCUM,
    parameter ACCIDW	  = `ACCIDW,
    parameter VRFIDW   = `VRFIDW,
    parameter MIW_MVU  = `MIW_MVU,
    parameter UIW_MVU  = `UIW_MVU,
    parameter MIW_EVRF = `MIW_EVRF,
    parameter UIW_EVRF = `UIW_EVRF,
    parameter MIW_MFU  = `MIW_MFU,
    parameter UIW_MFU  = `UIW_MFU,
    parameter MIW_LD   = `MIW_LD,
    parameter UIW_LD   = `UIW_LD,
    parameter MICW     = `MICW,
    // others
    parameter QDEPTH   = `QDEPTH,  // queue depth
    parameter WB_LMT   = `WB_LMT,  // write-back limit
    parameter WB_LMTW  = `WB_LMTW,
    parameter INST_DEPTH = `INST_DEPTH,
    parameter INST_ADDRW = `INST_ADDRW,
    parameter CACHELINE_SIZE = `CACHELINE_SIZE,
    parameter MDATA_SIZE = `MDATA_SIZE
) (
    // input - macro instruction chain
    input  i_minst_chain_wr_en,
    input  [INST_ADDRW-1:0] i_minst_chain_wr_addr, 
    input  [MICW-1:0] i_minst_chain_wr_din,   
    // output - MVU macro instruction
    input  i_mvu_minst_rd_en,
    output o_mvu_minst_rd_rdy,
    output [MIW_MVU-1:0] o_mvu_minst_rd_dout,
    // output - ext VRF macro instruction
    input  i_evrf_minst_rd_en,
    output o_evrf_minst_rd_rdy,
    output [MIW_EVRF-1:0] o_evrf_minst_rd_dout,
    // output - MFU0 macro instruction
    input  i_mfu0_minst_rd_en,
    output o_mfu0_minst_rd_rdy,
    output [MIW_MFU-1:0] o_mfu0_minst_rd_dout,
    // output - MFU1 macro instruction
    input  i_mfu1_minst_rd_en,
    output o_mfu1_minst_rd_rdy,
    output [MIW_MFU-1:0] o_mfu1_minst_rd_dout,    
    // output - LD macro instruction
    input  i_ld_minst_rd_en,
    output o_ld_minst_rd_rdy,
    output [MIW_LD-1:0] o_ld_minst_rd_dout,
    // start
    input  i_start,
    input  [INST_ADDRW-1:0] pc_start_offset,
    // clk & rst
    input  clk, 
    input  rst
);
    // Issue Control Signals
    reg r_start;
    reg issue_state, next_issue_state;
    reg halt;

    // Instruction RAM Signals
    reg  [INST_ADDRW-1:0] minst_chain_ram_rd_addr;
    reg  [INST_ADDRW-1:0] minst_chain_ram_rd_addr_nxt;
    wire [MICW-1:0] inst;
    reg  minst_chain_ram_rd_ok, r_minst_chain_ram_rd_ok, rr_minst_chain_ram_rd_ok, rrr_minst_chain_ram_rd_ok;
    reg  minst_chain_ram_rd_ok_nxt;
    integer inst_count, inst_count_nxt;
	
    // Adjust issue state based on start & halt signals
    always @(*) begin
        next_issue_state = issue_state;
        case (issue_state)
            1'b0: if (r_start) next_issue_state = 1'b1;
            1'b1: if (halt) next_issue_state = 1'b0;
            default: next_issue_state = 1'b0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            issue_state <= 1'b0;
        end else begin
            issue_state <= next_issue_state;
        end
    end
	
    // Instruction RAM
    inst_ram #(
        .MODULE_ID("top_sched"), 
        .ID(0), 
        .DW(MICW), 
        .AW(INST_ADDRW), 
        .DEPTH(INST_DEPTH)
    ) minst_chain_ram (
        .wr_en   (i_minst_chain_wr_en),
        .wr_addr (i_minst_chain_wr_addr),
        .wr_data (i_minst_chain_wr_din),
        .rd_addr (minst_chain_ram_rd_addr),
        .rd_data (inst),
        .clk (clk), 
        .rst (rst)
    );
	
	// Output FIFO Signals
    wire                mvu_minst_ofifo_wr_ok, mvu_minst_ofifo_wr_en;
    wire                mvu_minst_ofifo_rd_ok, mvu_minst_ofifo_rd_en;
    wire [MIW_MVU-1:0]  mvu_minst_ofifo_wr_data, mvu_minst_ofifo_rd_data;
    wire                evrf_minst_ofifo_wr_ok, evrf_minst_ofifo_wr_en;
    wire                evrf_minst_ofifo_rd_ok, evrf_minst_ofifo_rd_en;
    wire [MIW_EVRF-1:0] evrf_minst_ofifo_wr_data, evrf_minst_ofifo_rd_data;
    wire                mfu0_minst_ofifo_wr_ok, mfu0_minst_ofifo_wr_en;
    wire                mfu0_minst_ofifo_rd_ok, mfu0_minst_ofifo_rd_en;
    wire [MIW_MFU-1:0]  mfu0_minst_ofifo_wr_data, mfu0_minst_ofifo_rd_data;
    wire                mfu1_minst_ofifo_wr_ok, mfu1_minst_ofifo_wr_en;
    wire                mfu1_minst_ofifo_rd_ok, mfu1_minst_ofifo_rd_en;
    wire [MIW_MFU-1:0]  mfu1_minst_ofifo_wr_data, mfu1_minst_ofifo_rd_data;
	wire                ld_minst_ofifo_wr_ok, ld_minst_ofifo_wr_en;
    wire                ld_minst_ofifo_rd_ok, ld_minst_ofifo_rd_en;
    wire [MIW_LD-1:0]   ld_minst_ofifo_wr_data, ld_minst_ofifo_rd_data;
	
    // Extract MVU minst and loop counter to later use for stop condition
    wire [MIW_MVU-1:0] temp;
    assign temp = `mvu_minst(inst);
    
    // Advance instruction memory read address until stop condition
    always @(*) begin
        if (issue_state == 1'b1) begin
	       // Stop when you hit an instruction with MVU tag of all 1s
            if (`mvu_minst_tag(temp) == {(NTAGW){1'b1}}) begin
                minst_chain_ram_rd_addr_nxt = 0;
                minst_chain_ram_rd_ok_nxt = 1'b0;
                halt = 1'b1;
	       // Advance only if all FIFOs are ready to accept new input
            end else if (mvu_minst_ofifo_wr_ok && mfu0_minst_ofifo_wr_ok && 
             mfu1_minst_ofifo_wr_ok && evrf_minst_ofifo_wr_ok && ld_minst_ofifo_wr_ok) begin
                minst_chain_ram_rd_addr_nxt = INST_ADDRW'(minst_chain_ram_rd_addr + 1);
                minst_chain_ram_rd_ok_nxt = 1'b1;
                halt = 1'b0;
            end else begin
                minst_chain_ram_rd_addr_nxt = minst_chain_ram_rd_addr;
                minst_chain_ram_rd_ok_nxt = 1'b1;
                halt = 1'b0;
            end
	    end else begin
            minst_chain_ram_rd_addr_nxt = minst_chain_ram_rd_addr;
            minst_chain_ram_rd_ok_nxt = 1'b0;
            halt = 1'b1;
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            minst_chain_ram_rd_addr <= pc_start_offset;
            minst_chain_ram_rd_ok   <= 0;
            r_minst_chain_ram_rd_ok <= 0;
            rr_minst_chain_ram_rd_ok <= 0;
            rrr_minst_chain_ram_rd_ok <= 0;
	        r_start                 <= 0;
        end else begin
            minst_chain_ram_rd_addr <= minst_chain_ram_rd_addr_nxt;
            minst_chain_ram_rd_ok   <= minst_chain_ram_rd_ok_nxt;
            r_minst_chain_ram_rd_ok <= minst_chain_ram_rd_ok;
            rr_minst_chain_ram_rd_ok <= r_minst_chain_ram_rd_ok;
            rrr_minst_chain_ram_rd_ok <= rr_minst_chain_ram_rd_ok;
            r_start <= i_start;
        end
    end

    // MVU macro instruction ofifo
    fifo #(
        .ID(0), .DW(MIW_MVU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    mvu_minst_ofifo (
        .wr_ok   (mvu_minst_ofifo_wr_ok  ),
        .wr_en   (mvu_minst_ofifo_wr_en  ),
        .wr_data (mvu_minst_ofifo_wr_data),
        .rd_ok   (mvu_minst_ofifo_rd_ok  ),
        .rd_en   (mvu_minst_ofifo_rd_en  ),
        .rd_data (mvu_minst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_mvu_minst_rd_rdy      = mvu_minst_ofifo_rd_ok;
    assign o_mvu_minst_rd_dout     = mvu_minst_ofifo_rd_data;
    assign mvu_minst_ofifo_rd_en   = i_mvu_minst_rd_en;

    // ext VRF macro instruciton ofifo
    fifo #(
        .ID(0), .DW(MIW_EVRF), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    evrf_minst_ofifo (
        .wr_ok   (evrf_minst_ofifo_wr_ok  ),
        .wr_en   (evrf_minst_ofifo_wr_en  ),
        .wr_data (evrf_minst_ofifo_wr_data),
        .rd_ok   (evrf_minst_ofifo_rd_ok  ),
        .rd_en   (evrf_minst_ofifo_rd_en  ),
        .rd_data (evrf_minst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_evrf_minst_rd_rdy      = evrf_minst_ofifo_rd_ok;
    assign o_evrf_minst_rd_dout     = evrf_minst_ofifo_rd_data;
    assign evrf_minst_ofifo_rd_en   = i_evrf_minst_rd_en;

    // MFU0 macro instruciton ofifo
    fifo #(
        .ID(0), .DW(MIW_MFU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    mfu0_minst_ofifo (
        .wr_ok   (mfu0_minst_ofifo_wr_ok  ),
        .wr_en   (mfu0_minst_ofifo_wr_en  ),
        .wr_data (mfu0_minst_ofifo_wr_data),
        .rd_ok   (mfu0_minst_ofifo_rd_ok  ),
        .rd_en   (mfu0_minst_ofifo_rd_en  ),
        .rd_data (mfu0_minst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_mfu0_minst_rd_rdy      = mfu0_minst_ofifo_rd_ok;
    assign o_mfu0_minst_rd_dout     = mfu0_minst_ofifo_rd_data;
    assign mfu0_minst_ofifo_rd_en   = i_mfu0_minst_rd_en;

    // MFU1 macro instruciton ofifo
    fifo #(
        .ID(0), .DW(MIW_MFU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    mfu1_minst_ofifo (
        .wr_ok   (mfu1_minst_ofifo_wr_ok  ),
        .wr_en   (mfu1_minst_ofifo_wr_en  ),
        .wr_data (mfu1_minst_ofifo_wr_data),
        .rd_ok   (mfu1_minst_ofifo_rd_ok  ),
        .rd_en   (mfu1_minst_ofifo_rd_en  ),
        .rd_data (mfu1_minst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_mfu1_minst_rd_rdy      = mfu1_minst_ofifo_rd_ok;
    assign o_mfu1_minst_rd_dout     = mfu1_minst_ofifo_rd_data;
    assign mfu1_minst_ofifo_rd_en   = i_mfu1_minst_rd_en;

    // ld macro instruciton ofifo
    fifo #(
        .ID(0), .DW(MIW_LD), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    ld_minst_ofifo (
        .wr_ok   (ld_minst_ofifo_wr_ok  ),
        .wr_en   (ld_minst_ofifo_wr_en  ),
        .wr_data (ld_minst_ofifo_wr_data),
        .rd_ok   (ld_minst_ofifo_rd_ok  ),
        .rd_en   (ld_minst_ofifo_rd_en  ),
        .rd_data (ld_minst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_ld_minst_rd_rdy      = ld_minst_ofifo_rd_ok;
    assign o_ld_minst_rd_dout     = ld_minst_ofifo_rd_data;
    assign ld_minst_ofifo_rd_en   = i_ld_minst_rd_en;

    wire issue_ok = ~halt && r_minst_chain_ram_rd_ok && 
         mvu_minst_ofifo_wr_ok && mfu0_minst_ofifo_wr_ok && 
         mfu1_minst_ofifo_wr_ok && evrf_minst_ofifo_wr_ok && 
         ld_minst_ofifo_wr_ok; 
     
    assign mvu_minst_ofifo_wr_en    = issue_ok;
    assign mvu_minst_ofifo_wr_data  = `mvu_minst(inst); 
    assign evrf_minst_ofifo_wr_en   = issue_ok;
    assign evrf_minst_ofifo_wr_data = `evrf_minst(inst); 
    assign mfu0_minst_ofifo_wr_en   = issue_ok;
    assign mfu0_minst_ofifo_wr_data = `mfu0_minst(inst); 
    assign mfu1_minst_ofifo_wr_en   = issue_ok;
    assign mfu1_minst_ofifo_wr_data = `mfu1_minst(inst); 
    assign ld_minst_ofifo_wr_en     = issue_ok;
    assign ld_minst_ofifo_wr_data   = `ld_minst(inst); 

`ifdef DISPLAY_INST
    always @(posedge clk) begin
        if(i_minst_chain_wr_en) begin
            $display("[%0t][TOP SCHED] instruction: %d:%b", $time, i_minst_chain_wr_addr, i_minst_chain_wr_din);
        end

        if(issue_ok) begin
            $display("[%0t][%s] Dispatched MVU mOP: %b", $time, `__FILE__, mvu_minst_ofifo_wr_data);
            $display("|--- VRF addr0: %d, VRF addr1: %d, VRF addr2: %d", `mvu_minst_vrf_base0(mvu_minst_ofifo_wr_data), `mvu_minst_vrf_base1(mvu_minst_ofifo_wr_data), `mvu_minst_vrf_base2(mvu_minst_ofifo_wr_data));
            $display("|--- VRF size: %d", `mvu_minst_vrf_size(mvu_minst_ofifo_wr_data));
            $display("|--- MRF addr: %d", `mvu_minst_mrf_base(mvu_minst_ofifo_wr_data));
            $display("|--- MRF size: %d", `mvu_minst_mrf_size(mvu_minst_ofifo_wr_data));
            $display("|--- Words per row: %d", `mvu_minst_words_per_row(mvu_minst_ofifo_wr_data));
            $display("|--- Tag: %d", `mvu_minst_tag(mvu_minst_ofifo_wr_data));
            $display("|--- Operation: %d", `mvu_minst_op(mvu_minst_ofifo_wr_data));

            $display("[%0t][%s] Dispatched eVRF mOP:", $time, `__FILE__);
            $display("|--- VRF addr0: %d, VRF addr1: %d, VRF addr2: %d", `evrf_minst_vrf_base0(evrf_minst_ofifo_wr_data), `evrf_minst_vrf_base1(evrf_minst_ofifo_wr_data), `evrf_minst_vrf_base2(evrf_minst_ofifo_wr_data));
            $display("|--- VRF size: %d", `evrf_minst_vrf_size(evrf_minst_ofifo_wr_data));
            $display("|--- Src select: %d", `evrf_minst_src_sel(evrf_minst_ofifo_wr_data));
            $display("|--- Tag: %d", `evrf_minst_tag(evrf_minst_ofifo_wr_data));
            $display("|--- Operation: %d", `evrf_minst_op(evrf_minst_ofifo_wr_data));
            $display("|--- Batch: %d", `evrf_minst_batch(evrf_minst_ofifo_wr_data));

            $display("[%0t][%s] Dispatched MFU0 mOP:", $time, `__FILE__);
            $display("|--- VRF0 addr0: %d, VRF0 addr1: %d, VRF0 addr2: %d", `mfu_minst_vrf0_base0(mfu0_minst_ofifo_wr_data), `mfu_minst_vrf0_base1(mfu0_minst_ofifo_wr_data), `mfu_minst_vrf0_base2(mfu0_minst_ofifo_wr_data));
            $display("|--- VRF1 addr0: %d, VRF1 addr1: %d, VRF1 addr2: %d", `mfu_minst_vrf1_base0(mfu0_minst_ofifo_wr_data), `mfu_minst_vrf1_base1(mfu0_minst_ofifo_wr_data), `mfu_minst_vrf1_base2(mfu0_minst_ofifo_wr_data));
            $display("|--- VRF size: %d", `mfu_minst_size(mfu0_minst_ofifo_wr_data));
            $display("|--- Tag: %d", `mfu_minst_tag(mfu0_minst_ofifo_wr_data));
            $display("|--- Operation: %d", `mfu_minst_op(mfu0_minst_ofifo_wr_data));
            $display("|--- Batch: %d", `mfu_minst_batch(mfu0_minst_ofifo_wr_data));

            $display("[%0t][%s] Dispatched MFU1 mOP:", $time, `__FILE__);
            $display("|--- VRF0 addr0: %d, VRF0 addr1: %d, VRF0 addr2: %d", `mfu_minst_vrf0_base0(mfu1_minst_ofifo_wr_data), `mfu_minst_vrf0_base1(mfu1_minst_ofifo_wr_data), `mfu_minst_vrf0_base2(mfu1_minst_ofifo_wr_data));
            $display("|--- VRF1 addr0: %d, VRF1 addr1: %d, VRF1 addr2: %d", `mfu_minst_vrf1_base0(mfu1_minst_ofifo_wr_data), `mfu_minst_vrf1_base1(mfu1_minst_ofifo_wr_data), `mfu_minst_vrf1_base2(mfu1_minst_ofifo_wr_data));
            $display("|--- VRF size: %d", `mfu_minst_size(mfu1_minst_ofifo_wr_data));
            $display("|--- Tag: %d", `mfu_minst_tag(mfu1_minst_ofifo_wr_data));
            $display("|--- Operation: %d", `mfu_minst_op(mfu1_minst_ofifo_wr_data));
            $display("|--- Batch: %d", `mfu_minst_batch(mfu1_minst_ofifo_wr_data));

            $display("[%0t][%s] Dispatched LD mOP: %b", $time, `__FILE__, ld_minst_ofifo_wr_data);
            $display("|--- VRF ID: %d", `ld_minst_vrf_id(ld_minst_ofifo_wr_data));
            $display("|--- VRF0 addr0: %d, VRF0 addr1: %d, VRF0 addr2: %d", `ld_minst_vrf0_base0(ld_minst_ofifo_wr_data), `ld_minst_vrf0_base1(ld_minst_ofifo_wr_data), `ld_minst_vrf0_base2(ld_minst_ofifo_wr_data));
            $display("|--- VRF1 addr0: %d, VRF1 addr1: %d, VRF1 addr2: %d", `ld_minst_vrf1_base0(ld_minst_ofifo_wr_data), `ld_minst_vrf1_base1(ld_minst_ofifo_wr_data), `ld_minst_vrf1_base2(ld_minst_ofifo_wr_data));
            $display("|--- VRF size: %d", `ld_minst_size(ld_minst_ofifo_wr_data));
            $display("|--- Src select: %d", `ld_minst_src_sel(ld_minst_ofifo_wr_data));
            $display("|--- Operation: %d", `ld_minst_op(ld_minst_ofifo_wr_data));
            $display("|--- Batch: %d", `ld_minst_batch(ld_minst_ofifo_wr_data));
            $display("|--- Interrupt: %d", `ld_minst_interrupt(ld_minst_ofifo_wr_data));
            $display("|--- Write to host: %d", `ld_minst_report_to_host(ld_minst_ofifo_wr_data));
            $display("====================================================================");
        
        end
    end
`endif

endmodule
