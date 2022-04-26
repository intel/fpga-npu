`include "npu.vh"

module mvu_sched # (
    // data width
    parameter EW       = `EW,    // element width
    parameter ACCW     = `ACCW,  // element width
    parameter DOTW     = `DOTW,  // # elemtns in vector
    // # functional units
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
    parameter WB_LMTW  = `WB_LMTW
) (
    // input - MVU macro instruction
    input                i_mvu_minst_wr_en,
    output               o_mvu_minst_wr_rdy,
    input  [MIW_MVU-1:0] i_mvu_minst_wr_din, 

    // output - MVU micro instruction
    input                i_mvu_uinst_rd_en,
    output               o_mvu_uinst_rd_rdy,
    output [UIW_MVU-1:0] o_mvu_uinst_rd_dout,

    // clk & rst
    input              clk, rst
);

    // FIXME: consistent with definition in mvu_tile.v
    localparam [0:0] MINST_MVU_OP_NOP = 0;
    localparam [0:0] MINST_MVU_OP_MUL = 1;

    localparam [1:0] UINST_MVU_ACC_OP_SET = 0;
    localparam [1:0] UINST_MVU_ACC_OP_UPD = 1;
    localparam [1:0] UINST_MVU_ACC_OP_WB  = 2;
    localparam [1:0] UINST_MVU_ACC_OP_SET_AND_WB = 3;

    // instruction chain ififo
    wire               minst_ififo_wr_ok, minst_ififo_wr_en;
    wire               minst_ififo_rd_ok;
    reg                minst_ififo_rd_en;
    wire [MIW_MVU-1:0] minst_ififo_wr_data, minst_ififo_rd_data;
    fifo #(
        .ID(0), .DW(MIW_MVU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    minst_ififo (
        .wr_ok   (minst_ififo_wr_ok  ),
        .wr_en   (minst_ififo_wr_en  ),
        .wr_data (minst_ififo_wr_data),
        .rd_ok   (minst_ififo_rd_ok  ),
        .rd_en   (minst_ififo_rd_en  ),
        .rd_data (minst_ififo_rd_data),
        .clk  (clk), .rst (rst));
    // connect input & output
    assign o_mvu_minst_wr_rdy  = minst_ififo_wr_ok;
    assign minst_ififo_wr_en   = i_mvu_minst_wr_en;
    assign minst_ififo_wr_data = i_mvu_minst_wr_din;        

    // micro instruction ofifo
    wire               uinst_ofifo_wr_ok;
    reg                uinst_ofifo_wr_en;
    wire               uinst_ofifo_rd_ok;
    wire               uinst_ofifo_rd_en;
    reg  [UIW_MVU-1:0] uinst_ofifo_wr_data;
    wire [UIW_MVU-1:0] uinst_ofifo_rd_data;
    fifo #(
        .ID(0), .DW(UIW_MVU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    uinst_ofifo (
        .wr_ok   (uinst_ofifo_wr_ok  ),
        .wr_en   (uinst_ofifo_wr_en  ),
        .wr_data (uinst_ofifo_wr_data),
        .rd_ok   (uinst_ofifo_rd_ok  ),
        .rd_en   (uinst_ofifo_rd_en  ),
        .rd_data (uinst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_mvu_uinst_rd_rdy  = uinst_ofifo_rd_ok;
    assign o_mvu_uinst_rd_dout = uinst_ofifo_rd_data;
    assign uinst_ofifo_rd_en   = i_mvu_uinst_rd_en; 

    // state machine
    localparam MVU_SCHED_INIT  = 0;
    localparam MVU_SCHED_MUL   = 1;
    localparam MVU_LOOP    	 = 2;

    reg [1:0]        mvu_sched_state, mvu_sched_state_nxt;

    reg [VRFAW-1:0] batch_counter, batch_counter_nxt;
    reg [VRFAW-1:0] vrf_counter, vrf_counter_nxt;
    reg [VRFAW-1:0] pipeline_counter, pipeline_counter_nxt;
    reg [VRFAW-1:0] vrf_id_counter, vrf_id_counter_nxt;
    reg [VRFIDW-1:0] vrf_id, vrf_id_nxt;
    reg [MRFAW-1:0] mrf_chunk_offset, mrf_chunk_offset_nxt;
    reg [MRFAW-1:0] mrf_pipeline_offset, mrf_pipeline_offset_nxt;
    reg [MRFAW-1:0] mrf_addr, mrf_addr_nxt;
    reg [NTAGW-1:0]  mvu_tag, mvu_tag_nxt;
    reg reg_sel, reg_sel_nxt;
    reg [NSIZEW-1:0] remaining_words, remaining_words_nxt;
    reg [4:0] acc_size, acc_size_nxt;

    always @(*) begin
        mvu_sched_state_nxt = mvu_sched_state;

        mvu_tag_nxt          = mvu_tag;
        batch_counter_nxt    = batch_counter;
        vrf_counter_nxt      = vrf_counter;
        pipeline_counter_nxt = pipeline_counter;
        vrf_id_counter_nxt   = vrf_id_counter;
        vrf_id_nxt           = vrf_id;
        mrf_chunk_offset_nxt = mrf_chunk_offset;
        mrf_pipeline_offset_nxt = mrf_pipeline_offset;
        mrf_addr_nxt         = mrf_addr;
        reg_sel_nxt          = reg_sel;
        remaining_words_nxt  = remaining_words;
        acc_size_nxt         = acc_size;


        minst_ififo_rd_en   = 0;
        uinst_ofifo_wr_en   = 0;
        uinst_ofifo_wr_data = 0;

        case (mvu_sched_state) 
            MVU_SCHED_INIT: begin
                // fetch a macro instruction from the queue        
                if (minst_ififo_rd_ok) begin
                    batch_counter_nxt       = 0;
                    vrf_counter_nxt         = 0;
                    pipeline_counter_nxt    = 0;
                    vrf_id_counter_nxt      = 0;
                    vrf_id_nxt              = 0;
                    reg_sel_nxt             = reg_sel;
                    mrf_chunk_offset_nxt    = 0;
                    mrf_pipeline_offset_nxt = 0;
                    mvu_tag_nxt             = `mvu_minst_tag(minst_ififo_rd_data);
                    mrf_addr_nxt            = `mvu_minst_mrf_base(minst_ififo_rd_data);
                    remaining_words_nxt     = `mvu_minst_words_per_row(minst_ififo_rd_data);
                    acc_size_nxt            = NUM_DSP*DOT_PER_DSP;

                    // go to the next state
					if(minst_ififo_rd_data == {(MIW_MVU){1'b1}}) begin
						mvu_sched_state_nxt = MVU_SCHED_INIT;
                        minst_ififo_rd_en   = 1;
                    end else if(`mvu_minst_op(minst_ififo_rd_data) == MINST_MVU_OP_MUL) begin
                        mvu_sched_state_nxt = MVU_SCHED_MUL;
                    end else begin
                        mvu_sched_state_nxt = MVU_SCHED_INIT;
                        minst_ififo_rd_en   = 1;
                    end
                end
            end

            MVU_SCHED_MUL: begin
                if(batch_counter == 0) begin
                    `mvu_uinst_vrf_addr(uinst_ofifo_wr_data) = `mvu_minst_vrf_base0(minst_ififo_rd_data) + vrf_counter;
                end else if (batch_counter == 1) begin
                    `mvu_uinst_vrf_addr(uinst_ofifo_wr_data) = `mvu_minst_vrf_base1(minst_ififo_rd_data) + vrf_counter;
                end else begin
                    `mvu_uinst_vrf_addr(uinst_ofifo_wr_data) = `mvu_minst_vrf_base2(minst_ififo_rd_data) + vrf_counter;
                end

                `mvu_uinst_vrf_rd_id(uinst_ofifo_wr_data) = vrf_id;
                `mvu_uinst_reg_sel(uinst_ofifo_wr_data) = reg_sel;
                `mvu_uinst_mrf_addr(uinst_ofifo_wr_data) = mrf_addr;
                `mvu_uinst_acc_op(uinst_ofifo_wr_data) = (vrf_counter == `mvu_minst_vrf_size(minst_ififo_rd_data)-1)? 
                    UINST_MVU_ACC_OP_WB: ((vrf_counter == 0)? UINST_MVU_ACC_OP_SET: UINST_MVU_ACC_OP_UPD);
                `mvu_uinst_tag(uinst_ofifo_wr_data) = mvu_tag;

                if(pipeline_counter < (NUM_DSP*DOT_PER_DSP)) begin
                    `mvu_uinst_vrf_en(uinst_ofifo_wr_data) = 1'b1;
                end else begin
                    `mvu_uinst_vrf_en(uinst_ofifo_wr_data) = 1'b0;
                end

                if(remaining_words >= (2*NUM_DSP*DOT_PER_DSP)) begin
                    `mvu_uinst_acc_size(uinst_ofifo_wr_data) = NUM_DSP*DOT_PER_DSP;
                    acc_size_nxt = NUM_DSP*DOT_PER_DSP;
                end else begin
                    `mvu_uinst_acc_size(uinst_ofifo_wr_data) = remaining_words[4:0];
                    acc_size_nxt = remaining_words[4:0];
                end

                if(pipeline_counter < remaining_words) begin
                    `mvu_uinst_acc_op(uinst_ofifo_wr_data) = ((vrf_counter == 0) && (vrf_counter == `mvu_minst_vrf_size(minst_ififo_rd_data)-1))? 
                        UINST_MVU_ACC_OP_SET_AND_WB : (vrf_counter == `mvu_minst_vrf_size(minst_ififo_rd_data)-1)? 
                        UINST_MVU_ACC_OP_WB: ((vrf_counter == 0)? 
                        UINST_MVU_ACC_OP_SET: UINST_MVU_ACC_OP_UPD);
                end else begin
                    `mvu_uinst_acc_op(uinst_ofifo_wr_data) = UINST_MVU_ACC_OP_SET;
                end

                if (uinst_ofifo_wr_ok) begin
                    // Write uOP
                    uinst_ofifo_wr_en = 1;

                    // Update control counters
                    if(pipeline_counter < (NUM_DSP*DOT_PER_DSP)) begin
                        batch_counter_nxt = (batch_counter == 2)? 0: VRFAW'(batch_counter+1);
                        vrf_id_counter_nxt = (vrf_id_counter == DOT_PER_DSP-1)? 0: VRFAW'(vrf_id_counter+1);
                        vrf_id_nxt = (vrf_id == NUM_DSP-1 && vrf_id_counter == DOT_PER_DSP-1)? 0: 
                            (vrf_id_counter == DOT_PER_DSP-1)? VRFIDW'(vrf_id+1): vrf_id;
                    end

                    vrf_counter_nxt = (pipeline_counter == acc_size-1)? 
                        ((vrf_counter == `mvu_minst_vrf_size(minst_ififo_rd_data)-1)? 0: VRFAW'(vrf_counter+1)): vrf_counter;
                    pipeline_counter_nxt = (pipeline_counter == acc_size-1)? 0: VRFAW'(pipeline_counter+1);

                    reg_sel_nxt = ((pipeline_counter == acc_size-1) || (mrf_addr == `mvu_minst_mrf_base(minst_ififo_rd_data) + `mvu_minst_mrf_size(minst_ififo_rd_data) - 1))? 
                        ~reg_sel: reg_sel;

                    mrf_chunk_offset_nxt = ((vrf_counter == `mvu_minst_vrf_size(minst_ififo_rd_data)-1) && (pipeline_counter == acc_size-1))? 
                        MRFAW'(mrf_chunk_offset + (NUM_DSP*DOT_PER_DSP*`mvu_minst_vrf_size(minst_ififo_rd_data))): mrf_chunk_offset;
                    mrf_pipeline_offset_nxt = (pipeline_counter == acc_size-1)? 0: 
                         MRFAW'(mrf_pipeline_offset + `mvu_minst_vrf_size(minst_ififo_rd_data));
                    mrf_addr_nxt =  MRFAW'(`mvu_minst_mrf_base(minst_ififo_rd_data) + mrf_chunk_offset_nxt + mrf_pipeline_offset_nxt + vrf_counter_nxt);

                    remaining_words_nxt = (vrf_counter == `mvu_minst_vrf_size(minst_ififo_rd_data)-1 && (pipeline_counter == acc_size-1))?
                        ((remaining_words > NSIZEW'(2*NUM_DSP*DOT_PER_DSP-1))? remaining_words-NSIZEW'(NUM_DSP*DOT_PER_DSP): remaining_words):
                        remaining_words;

                    // Update FSM state
                    if (mrf_addr == `mvu_minst_mrf_base(minst_ififo_rd_data) + `mvu_minst_mrf_size(minst_ififo_rd_data) - 1) begin
                        mvu_sched_state_nxt = MVU_SCHED_INIT;
                        minst_ififo_rd_en   = 1;
                    end
               end

            end
        endcase
    end

	always @(posedge clk) begin
		if (rst) begin
			mvu_sched_state <= MVU_SCHED_INIT;
            reg_sel <= 0;
		end else begin
			mvu_sched_state <= mvu_sched_state_nxt;
            reg_sel <= reg_sel_nxt;
		end	
		mvu_tag              <= mvu_tag_nxt;
        batch_counter        <= batch_counter_nxt;
        vrf_counter          <= vrf_counter_nxt;
        pipeline_counter     <= pipeline_counter_nxt;
        vrf_id_counter       <= vrf_id_counter_nxt;
        vrf_id               <= vrf_id_nxt;
        mrf_chunk_offset     <= mrf_chunk_offset_nxt;
        mrf_pipeline_offset  <= mrf_pipeline_offset_nxt;
        mrf_addr             <= mrf_addr_nxt;
        remaining_words      <= remaining_words_nxt;
        acc_size             <= acc_size_nxt;
	end

`ifdef DISPLAY_MVU   
    always @(posedge clk) begin
        if (uinst_ofifo_wr_en) begin
            $display("[%0t][%s][MVU uOP] vrf_addr: %d, mrf_addr: %d, accum: %d, reg_sel: %d, vrf_sel: %d, tag: %d, acc_size: %d, vrf_en: %d", 
                $time, `__FILE__,
                `mvu_uinst_vrf_addr(uinst_ofifo_wr_data),
                `mvu_uinst_mrf_addr(uinst_ofifo_wr_data),
                `mvu_uinst_acc_op(uinst_ofifo_wr_data),
                `mvu_uinst_reg_sel(uinst_ofifo_wr_data),
                `mvu_uinst_vrf_rd_id(uinst_ofifo_wr_data),
                `mvu_uinst_tag(uinst_ofifo_wr_data),
                `mvu_uinst_acc_size(uinst_ofifo_wr_data),
                `mvu_uinst_vrf_en(uinst_ofifo_wr_data));
        end
    end
`endif

endmodule
