`include "npu.vh"

module mfu_sched # (
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
    // input - MFU macro instruction
    input                i_mfu_minst_wr_en,
    output               o_mfu_minst_wr_rdy,
    input  [MIW_MFU-1:0] i_mfu_minst_wr_din,

    // output - MFU micro instruction
    input                i_mfu_uinst_rd_en,
    output               o_mfu_uinst_rd_rdy,
    output [UIW_MFU-1:0] o_mfu_uinst_rd_dout,

    // clk & rst
    input              clk, rst
);
    localparam COUNTW = 2;
    localparam [0:0] MINST_MFU_OP_NOP  = 0;
    localparam [0:0] MINST_MFU_OP_FUNC = 1;

    // instruction chain ififo
    wire               minst_ififo_wr_ok, minst_ififo_wr_en;
    wire               minst_ififo_rd_ok;
    reg                minst_ififo_rd_en;
    wire [MIW_MFU-1:0] minst_ififo_wr_data, minst_ififo_rd_data;
    fifo #(
        .ID(0), .DW(MIW_MFU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    minst_ififo (
        .wr_ok   (minst_ififo_wr_ok  ),
        .wr_en   (minst_ififo_wr_en  ),
        .wr_data (minst_ififo_wr_data),
        .rd_ok   (minst_ififo_rd_ok  ),
        .rd_en   (minst_ififo_rd_en  ),
        .rd_data (minst_ififo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_mfu_minst_wr_rdy  = minst_ififo_wr_ok;
    assign minst_ififo_wr_en   = i_mfu_minst_wr_en;
    assign minst_ififo_wr_data = i_mfu_minst_wr_din;        

    // micro instruction ofifo
    wire               uinst_ofifo_wr_ok;
    reg                uinst_ofifo_wr_en;
    wire               uinst_ofifo_rd_ok;
    wire               uinst_ofifo_rd_en;
    reg  [UIW_MFU-1:0] uinst_ofifo_wr_data;
    wire [UIW_MFU-1:0] uinst_ofifo_rd_data;
    fifo #(
        .ID(0), .DW(UIW_MFU), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    uinst_ofifo (
        .wr_ok   (uinst_ofifo_wr_ok  ),
        .wr_en   (uinst_ofifo_wr_en  ),
        .wr_data (uinst_ofifo_wr_data),
        .rd_ok   (uinst_ofifo_rd_ok  ),
        .rd_en   (uinst_ofifo_rd_en  ),
        .rd_data (uinst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_mfu_uinst_rd_rdy  = uinst_ofifo_rd_ok;
    assign o_mfu_uinst_rd_dout = uinst_ofifo_rd_data;
    assign uinst_ofifo_rd_en   = i_mfu_uinst_rd_en; 

    localparam MFU_SCHED_INIT  = 0;
    localparam MFU_SCHED_ISSUE = 1;
	localparam MFU_SCHED_LOOP = 2;

    reg [1:0] mfu_sched_state, mfu_sched_state_nxt;

    reg [VRFAW-1:0]  mfu_vrf0_base0, mfu_vrf0_base0_nxt;
    reg [VRFAW-1:0]  mfu_vrf0_base1, mfu_vrf0_base1_nxt;
    reg [VRFAW-1:0]  mfu_vrf0_base2, mfu_vrf0_base2_nxt;
    reg [VRFAW-1:0]  mfu_vrf1_base0, mfu_vrf1_base0_nxt;
    reg [VRFAW-1:0]  mfu_vrf1_base1, mfu_vrf1_base1_nxt;
    reg [VRFAW-1:0]  mfu_vrf1_base2, mfu_vrf1_base2_nxt;
    reg [NSIZEW-1:0] mfu_size, mfu_size_nxt;
    reg [NTAGW-1:0]  mfu_tag, mfu_tag_nxt;
    reg [6:0]        mfu_op, mfu_op_nxt;
    reg [1:0]        mfu_batch, mfu_batch_nxt;

    reg [VRFAW-1:0] mfu_count, mfu_count_nxt;
    reg [COUNTW-1:0] mfu_batch_count, mfu_batch_count_nxt;

    always @(*) begin
        mfu_sched_state_nxt  = mfu_sched_state;

        mfu_vrf0_base0_nxt    = mfu_vrf0_base0;
        mfu_vrf0_base1_nxt    = mfu_vrf0_base1;
        mfu_vrf0_base2_nxt    = mfu_vrf0_base2;

        mfu_vrf1_base0_nxt    = mfu_vrf1_base0;
        mfu_vrf1_base1_nxt    = mfu_vrf1_base1;
        mfu_vrf1_base2_nxt    = mfu_vrf1_base2;

        mfu_size_nxt         = mfu_size;
        mfu_tag_nxt          = mfu_tag;
        mfu_op_nxt           = mfu_op;
        mfu_batch_nxt        = mfu_batch;

        mfu_count_nxt        = mfu_count;
        mfu_batch_count_nxt  = mfu_batch_count;

        minst_ififo_rd_en   = 0;

        uinst_ofifo_wr_en   = 0;
        uinst_ofifo_wr_data = 0;
       
        case (mfu_sched_state) 
            MFU_SCHED_INIT: begin
                // fetch a macro instruction from the queue
                mfu_vrf0_base0_nxt = `mfu_minst_vrf0_base0(minst_ififo_rd_data);
                mfu_vrf0_base1_nxt = `mfu_minst_vrf0_base1(minst_ififo_rd_data);
                mfu_vrf0_base2_nxt = `mfu_minst_vrf0_base2(minst_ififo_rd_data);

                mfu_vrf1_base0_nxt = `mfu_minst_vrf1_base0(minst_ififo_rd_data);
                mfu_vrf1_base1_nxt = `mfu_minst_vrf1_base1(minst_ififo_rd_data);
                mfu_vrf1_base2_nxt = `mfu_minst_vrf1_base2(minst_ififo_rd_data);

                mfu_size_nxt      = `mfu_minst_size(minst_ififo_rd_data);
                mfu_tag_nxt       = `mfu_minst_tag(minst_ififo_rd_data);
                mfu_op_nxt        = `mfu_minst_op(minst_ififo_rd_data);
                mfu_batch_nxt     = `mfu_minst_batch(minst_ififo_rd_data);

                if (minst_ififo_rd_ok) begin
                    // initialize all interfation counters
                    mfu_count_nxt       = 0;
                    mfu_batch_count_nxt = 0;
                    // go to the next state
                    minst_ififo_rd_en   = 1;
						  if(minst_ififo_rd_data == {(MIW_MFU){1'b1}}) begin
								mfu_sched_state_nxt = MFU_SCHED_INIT;
						  end else if(mfu_op_nxt[6] == MINST_MFU_OP_FUNC) begin
								mfu_sched_state_nxt = MFU_SCHED_ISSUE;
						  end else begin
								mfu_sched_state_nxt = MFU_SCHED_INIT;
						  end
                    /*mfu_sched_state_nxt =
                        (mfu_op_nxt[6] == MINST_MFU_OP_FUNC)?
                         MFU_SCHED_ISSUE : MFU_SCHED_INIT;*/
                end
            end
				
            MFU_SCHED_ISSUE: begin
                if(mfu_batch_count == 0) begin
                    `mfu_uinst_vrf0_addr(uinst_ofifo_wr_data) = mfu_vrf0_base0 + mfu_count;
                    `mfu_uinst_vrf1_addr(uinst_ofifo_wr_data) = mfu_vrf1_base0 + mfu_count;
                end else if (mfu_batch_count == 1) begin
                    `mfu_uinst_vrf0_addr(uinst_ofifo_wr_data) = mfu_vrf0_base1 + mfu_count;
                    `mfu_uinst_vrf1_addr(uinst_ofifo_wr_data) = mfu_vrf1_base1 + mfu_count;
                end else begin
                    `mfu_uinst_vrf0_addr(uinst_ofifo_wr_data) = mfu_vrf0_base2 + mfu_count;
                    `mfu_uinst_vrf1_addr(uinst_ofifo_wr_data) = mfu_vrf1_base2 + mfu_count;
                end
                `mfu_uinst_tag(uinst_ofifo_wr_data)       = mfu_tag;
                `mfu_uinst_func_op(uinst_ofifo_wr_data)   = mfu_op[5:0];

               if (uinst_ofifo_wr_ok) begin
                    // Write uOP
                    uinst_ofifo_wr_en = 1;

                    // Update control counters
                    mfu_count_nxt       = (mfu_batch_count == mfu_batch-1)? VRFAW'(mfu_count+1): mfu_count;
                    mfu_batch_count_nxt = (mfu_batch_count == mfu_batch-1)? 0: COUNTW'(mfu_batch_count+1);

                    // Update FSM state
                    if ((mfu_count == mfu_size-1) && (mfu_batch_count == mfu_batch-1)) begin
                        mfu_sched_state_nxt = MFU_SCHED_INIT;
                    end
               end
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            mfu_sched_state <= MFU_SCHED_INIT;
            mfu_count       <= 0;
            mfu_batch_count <= 0;
        end else begin
            mfu_sched_state <= mfu_sched_state_nxt;
            mfu_count       <= mfu_count_nxt;
            mfu_batch_count <= mfu_batch_count_nxt;
        end
        mfu_vrf0_base0  <= mfu_vrf0_base0_nxt;
        mfu_vrf0_base1  <= mfu_vrf0_base1_nxt;
        mfu_vrf0_base2  <= mfu_vrf0_base2_nxt;
        mfu_vrf1_base0  <= mfu_vrf1_base0_nxt;
        mfu_vrf1_base1  <= mfu_vrf1_base1_nxt;
        mfu_vrf1_base2  <= mfu_vrf1_base2_nxt;
        mfu_size       <= mfu_size_nxt;
        mfu_tag        <= mfu_tag_nxt;
        mfu_op         <= mfu_op_nxt;
        mfu_batch      <= mfu_batch_nxt;
    end

`ifdef DISPLAY_MFU
    always @(posedge clk) begin
        if (uinst_ofifo_wr_en) begin
            $display("[%0t][%s][MFU uOP] op: %d, vrf0_addr: %d, vrf1_addr: %d, tag: %d", 
                $time, `__FILE__,
                `mfu_uinst_func_op(uinst_ofifo_wr_data),
                `mfu_uinst_vrf0_addr(uinst_ofifo_wr_data), `mfu_uinst_vrf1_addr(uinst_ofifo_wr_data),
                `mfu_uinst_tag(uinst_ofifo_wr_data));
        end
    end
`endif

endmodule
