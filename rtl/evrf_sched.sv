`include "npu.vh"

module evrf_sched # (
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
    // input - ext VRF macro instruction
    input                 i_evrf_minst_wr_en,
    output                o_evrf_minst_wr_rdy,
    input  [MIW_EVRF-1:0] i_evrf_minst_wr_din,

    // output - ext VRF micro instruction
    input                 i_evrf_uinst_rd_en,
    output                o_evrf_uinst_rd_rdy,
    output [UIW_EVRF-1:0] o_evrf_uinst_rd_dout, 

    // clk & rst
    input              clk, rst
);

    localparam [0:0] MINST_EVRF_OP_NOP = 0;
    localparam [0:0] MINST_EVRF_OP_MOV = 1;
	 

    // instruction chain ififo
    wire                minst_ififo_wr_ok, minst_ififo_wr_en;
    wire                minst_ififo_rd_ok;
    reg                 minst_ififo_rd_en;
    wire [MIW_EVRF-1:0] minst_ififo_wr_data, minst_ififo_rd_data;
    fifo #(
        .ID(0), .DW(MIW_EVRF), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    minst_ififo (
        .wr_ok   (minst_ififo_wr_ok  ),
        .wr_en   (minst_ififo_wr_en  ),
        .wr_data (minst_ififo_wr_data),
        .rd_ok   (minst_ififo_rd_ok  ),
        .rd_en   (minst_ififo_rd_en  ),
        .rd_data (minst_ififo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_evrf_minst_wr_rdy = minst_ififo_wr_ok;
    assign minst_ififo_wr_en   = i_evrf_minst_wr_en;
    assign minst_ififo_wr_data = i_evrf_minst_wr_din;

    // micro instruction ofifo
    wire                uinst_ofifo_wr_ok;
    reg                 uinst_ofifo_wr_en;
    wire                uinst_ofifo_rd_ok;
    wire                uinst_ofifo_rd_en;
    reg  [UIW_EVRF-1:0] uinst_ofifo_wr_data;
    wire [UIW_EVRF-1:0] uinst_ofifo_rd_data;
    fifo #(
        .ID(0), .DW(UIW_EVRF), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    uinst_ofifo (
        .wr_ok   (uinst_ofifo_wr_ok  ),
        .wr_en   (uinst_ofifo_wr_en  ),
        .wr_data (uinst_ofifo_wr_data),
        .rd_ok   (uinst_ofifo_rd_ok  ),
        .rd_en   (uinst_ofifo_rd_en  ),
        .rd_data (uinst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_evrf_uinst_rd_rdy  = uinst_ofifo_rd_ok;
    assign o_evrf_uinst_rd_dout = uinst_ofifo_rd_data;
    assign uinst_ofifo_rd_en   = i_evrf_uinst_rd_en; 

    localparam EVRF_SCHED_INIT  = 0;
    localparam EVRF_SCHED_ISSUE = 1;
	localparam EVRF_SCHED_LOOP = 2;
    localparam FROM_MVU = 0;
    localparam FROM_VRF = 1;
    localparam FLUSH_MVU = 2;
    localparam COUNTW = 2;

    reg [1:0] evrf_sched_state, evrf_sched_state_nxt;

    reg [VRFAW-1:0] evrf_addr_counter, evrf_addr_counter_nxt;
    reg [COUNTW-1:0] evrf_batch_counter, evrf_batch_counter_nxt;

    always @(*) begin
        evrf_sched_state_nxt  = evrf_sched_state;

        evrf_addr_counter_nxt  = evrf_addr_counter;
        evrf_batch_counter_nxt = evrf_batch_counter;

        minst_ififo_rd_en   = 0;
        uinst_ofifo_wr_en   = 0;
        uinst_ofifo_wr_data = 0;
       
        case (evrf_sched_state) 
            EVRF_SCHED_INIT: begin
                if (minst_ififo_rd_ok) begin
                    // initialize all interfation counters
                    evrf_addr_counter_nxt = 0;
                    evrf_batch_counter_nxt = 0;
                    // go to the next state
					if(minst_ififo_rd_data == {(MIW_EVRF){1'b1}}) begin
						evrf_sched_state_nxt = EVRF_SCHED_INIT;
                        minst_ififo_rd_en = 1;
                    end else if(`evrf_minst_op(minst_ififo_rd_data) == MINST_EVRF_OP_MOV) begin
                        evrf_sched_state_nxt = EVRF_SCHED_ISSUE;
                    end else begin
                        evrf_sched_state_nxt = EVRF_SCHED_INIT;
                        minst_ififo_rd_en = 1;
                    end
                end
            end

            EVRF_SCHED_ISSUE: begin
                if(evrf_batch_counter == 0) begin
                    `evrf_uinst_vrf_addr(uinst_ofifo_wr_data) = `evrf_minst_vrf_base0(minst_ififo_rd_data) + evrf_addr_counter;
                end else if (evrf_batch_counter == 1) begin 
                    `evrf_uinst_vrf_addr(uinst_ofifo_wr_data) = `evrf_minst_vrf_base1(minst_ififo_rd_data) + evrf_addr_counter;
                end else begin
                    `evrf_uinst_vrf_addr(uinst_ofifo_wr_data) = `evrf_minst_vrf_base2(minst_ififo_rd_data) + evrf_addr_counter;
                end

                if(evrf_batch_counter < `evrf_minst_batch(minst_ififo_rd_data)) begin
                    `evrf_uinst_src_sel(uinst_ofifo_wr_data)  = {1'b0, `evrf_minst_src_sel(minst_ififo_rd_data)}; 
                end else begin
                    `evrf_uinst_src_sel(uinst_ofifo_wr_data)  = FLUSH_MVU; 
                end

               `evrf_uinst_tag(uinst_ofifo_wr_data) = `evrf_minst_tag(minst_ififo_rd_data);

               if (uinst_ofifo_wr_ok) begin
                    // Write uOP
                    uinst_ofifo_wr_en  = 1;

                    // Update control counters
                    evrf_batch_counter_nxt = (evrf_batch_counter == 2 && `evrf_minst_src_sel(minst_ififo_rd_data) == FROM_MVU)? 
                        0: (evrf_batch_counter == `evrf_minst_batch(minst_ififo_rd_data)-1 && `evrf_minst_src_sel(minst_ififo_rd_data) == FROM_VRF)? 0: COUNTW'(evrf_batch_counter+1);
                    evrf_addr_counter_nxt = (evrf_batch_counter == 2  && `evrf_minst_src_sel(minst_ififo_rd_data) == FROM_MVU)? 
                        VRFAW'(evrf_addr_counter + 1): (evrf_batch_counter == `evrf_minst_batch(minst_ififo_rd_data)-1 && `evrf_minst_src_sel(minst_ififo_rd_data) == FROM_VRF)? 
                        VRFAW'(evrf_addr_counter + 1): evrf_addr_counter;

                    if ((evrf_addr_counter == `evrf_minst_vrf_size(minst_ififo_rd_data) - 1)
                        && ((evrf_batch_counter == 2 && `evrf_minst_src_sel(minst_ififo_rd_data) == FROM_MVU) || 
                        (evrf_batch_counter == `evrf_minst_batch(minst_ififo_rd_data)-1 && `evrf_minst_src_sel(minst_ififo_rd_data) == FROM_VRF))) begin
                        evrf_sched_state_nxt = EVRF_SCHED_INIT;
                        minst_ififo_rd_en = 1;
                    end
               end
            end
        endcase
    end
   
    always @(posedge clk) begin
        if (rst) begin
            evrf_sched_state <= EVRF_SCHED_INIT;
        end
        else begin
            evrf_sched_state <= evrf_sched_state_nxt;
        end

        evrf_addr_counter <= evrf_addr_counter_nxt;
        evrf_batch_counter <= evrf_batch_counter_nxt;
    end

	 `ifdef DISPLAY_EVRF
    always @(posedge clk) begin
        if (uinst_ofifo_wr_en) begin
            $display("[%0t][%s][EVRF uOP] src: %d, vrf_addr: %d, tag: %d", 
                $time, `__FILE__,
                `evrf_uinst_src_sel(uinst_ofifo_wr_data),
                `evrf_uinst_vrf_addr(uinst_ofifo_wr_data),
                `evrf_uinst_tag(uinst_ofifo_wr_data));
        end
    end
	 `endif

endmodule
