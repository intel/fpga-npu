`include "npu.vh"

module ld_sched # (
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
    // input - LD macro instruction
    input               i_ld_minst_wr_en,
    output              o_ld_minst_wr_rdy,
    input  [MIW_LD-1:0] i_ld_minst_wr_din,

    // output - LD micro instruction
    input               i_ld_uinst_rd_en,
    output              o_ld_uinst_rd_rdy,
    output [UIW_LD-1:0] o_ld_uinst_rd_dout,

    // clk & rst
    input              clk, rst
);
    localparam [0:0] MINST_LD_OP_NOP  = 0;
    localparam [0:0] MINST_LD_OP_LD   = 1;

    // instruction chain ififo
    wire               minst_ififo_wr_ok, minst_ififo_wr_en;
    wire               minst_ififo_rd_ok;
    reg                minst_ififo_rd_en;
    wire [MIW_LD-1:0]  minst_ififo_wr_data, minst_ififo_rd_data;
    fifo #(
        .ID(0), .DW(MIW_LD), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    minst_ififo (
        .wr_ok   (minst_ififo_wr_ok  ),
        .wr_en   (minst_ififo_wr_en  ),
        .wr_data (minst_ififo_wr_data),
        .rd_ok   (minst_ififo_rd_ok  ),
        .rd_en   (minst_ififo_rd_en  ),
        .rd_data (minst_ififo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_ld_minst_wr_rdy   = minst_ififo_wr_ok;
    assign minst_ififo_wr_en   = i_ld_minst_wr_en;
    assign minst_ififo_wr_data = i_ld_minst_wr_din;        

    // micro instruction ofifo
    wire              uinst_ofifo_wr_ok;
    reg               uinst_ofifo_wr_en;
    wire              uinst_ofifo_rd_ok;
    wire              uinst_ofifo_rd_en;
    reg  [UIW_LD-1:0] uinst_ofifo_wr_data;
    wire [UIW_LD-1:0] uinst_ofifo_rd_data;
    fifo #(
        .ID(0), .DW(UIW_LD), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    uinst_ofifo (
        .wr_ok   (uinst_ofifo_wr_ok  ),
        .wr_en   (uinst_ofifo_wr_en  ),
        .wr_data (uinst_ofifo_wr_data),
        .rd_ok   (uinst_ofifo_rd_ok  ),
        .rd_en   (uinst_ofifo_rd_en  ),
        .rd_data (uinst_ofifo_rd_data),
        .clk (clk), .rst (rst));
    // connect input & output
    assign o_ld_uinst_rd_rdy  = uinst_ofifo_rd_ok;
    assign o_ld_uinst_rd_dout = uinst_ofifo_rd_data;
    assign uinst_ofifo_rd_en  = i_ld_uinst_rd_en; 

    localparam LD_SCHED_INIT  = 0;
    localparam LD_SCHED_ISSUE = 1;

    reg              ld_sched_state, ld_sched_state_nxt;

    reg [2*NVRF-1:0] ld_vrf_id, ld_vrf_id_nxt;

    reg [VRFAW-1:0]  ld_vrf0_base0, ld_vrf0_base0_nxt;
    reg [VRFAW-1:0]  ld_vrf0_base1, ld_vrf0_base1_nxt;
    reg [VRFAW-1:0]  ld_vrf0_base2, ld_vrf0_base2_nxt;

    reg [VRFAW-1:0]  ld_vrf1_base0, ld_vrf1_base0_nxt;
    reg [VRFAW-1:0]  ld_vrf1_base1, ld_vrf1_base1_nxt;
    reg [VRFAW-1:0]  ld_vrf1_base2, ld_vrf1_base2_nxt;

    reg [1:0] ld_batch, ld_batch_nxt;

    reg [NSIZEW-1:0] ld_size, ld_size_nxt;
    reg              ld_src_sel, ld_src_sel_nxt;
    reg              ld_interrupt, ld_interrupt_nxt;
    reg              ld_report_to_host, ld_report_to_host_nxt;

    reg [VRFAW-1:0] ld_count, ld_count_nxt;
    reg [VRFAW-1:0] ld_batch_count, ld_batch_count_nxt;

    always @(*) begin
        ld_sched_state_nxt  = ld_sched_state;

        ld_vrf_id_nxt       = ld_vrf_id;

        ld_vrf0_base0_nxt    = ld_vrf0_base0;
        ld_vrf0_base1_nxt    = ld_vrf0_base1;
        ld_vrf0_base2_nxt    = ld_vrf0_base2;

        ld_vrf1_base0_nxt    = ld_vrf1_base0;
        ld_vrf1_base1_nxt    = ld_vrf1_base1;
        ld_vrf1_base2_nxt    = ld_vrf1_base2;

        ld_size_nxt         = ld_size;
        ld_src_sel_nxt      = ld_src_sel;
        ld_interrupt_nxt    = ld_interrupt;
        ld_report_to_host_nxt = ld_report_to_host;
        ld_batch_nxt        = ld_batch;
        ld_count_nxt        = ld_count;
        ld_batch_count_nxt  = ld_batch_count;

        minst_ififo_rd_en   = 0;

        uinst_ofifo_wr_en   = 0;
        uinst_ofifo_wr_data = 0;
       
        case (ld_sched_state) 
            LD_SCHED_INIT: begin
                // fetch a macro instruction from the queue
                ld_vrf_id_nxt    = `ld_minst_vrf_id(minst_ififo_rd_data);

                ld_vrf0_base0_nxt = `ld_minst_vrf0_base0(minst_ififo_rd_data);
                ld_vrf0_base1_nxt = `ld_minst_vrf0_base1(minst_ififo_rd_data);
                ld_vrf0_base2_nxt = `ld_minst_vrf0_base2(minst_ififo_rd_data);

                ld_vrf1_base0_nxt = `ld_minst_vrf1_base0(minst_ififo_rd_data);
                ld_vrf1_base1_nxt = `ld_minst_vrf1_base1(minst_ififo_rd_data);
                ld_vrf1_base2_nxt = `ld_minst_vrf1_base2(minst_ififo_rd_data);

                ld_size_nxt      = `ld_minst_size(minst_ififo_rd_data);
                ld_src_sel_nxt   = `ld_minst_src_sel(minst_ififo_rd_data);
                ld_interrupt_nxt = `ld_minst_interrupt(minst_ififo_rd_data);
				ld_report_to_host_nxt = `ld_minst_report_to_host(minst_ififo_rd_data);
                ld_batch_nxt     = `ld_minst_batch(minst_ififo_rd_data);

                if (minst_ififo_rd_ok) begin
                    // initialize all interfation counters
                    ld_count_nxt       = 0;
                    ld_batch_count_nxt = 0;
                    // go to the next state
                    minst_ififo_rd_en   = 1;
                    if((`ld_minst_op(minst_ififo_rd_data) == MINST_LD_OP_NOP) || (minst_ififo_rd_data[MIW_LD-1:16] == {(MIW_LD-16){1'b1}})) begin
                    	ld_sched_state_nxt = LD_SCHED_INIT;
                    end else begin
                    	ld_sched_state_nxt = LD_SCHED_ISSUE;
                    end
                end
            end
            LD_SCHED_ISSUE: begin
                `ld_uinst_vrf_id(uinst_ofifo_wr_data)    = ld_vrf_id;
                if(ld_batch_count == 0) begin
                    `ld_uinst_vrf0_addr(uinst_ofifo_wr_data) = ld_vrf0_base0 + ld_count;
                    `ld_uinst_vrf1_addr(uinst_ofifo_wr_data) = ld_vrf1_base0 + ld_count;
                end else if (ld_batch_count == 1) begin
                    `ld_uinst_vrf0_addr(uinst_ofifo_wr_data) = ld_vrf0_base1 + ld_count;
                    `ld_uinst_vrf1_addr(uinst_ofifo_wr_data) = ld_vrf1_base1 + ld_count;
                end else begin
                    `ld_uinst_vrf0_addr(uinst_ofifo_wr_data) = ld_vrf0_base2 + ld_count;
                    `ld_uinst_vrf1_addr(uinst_ofifo_wr_data) = ld_vrf1_base2 + ld_count;
                end
                `ld_uinst_src_sel(uinst_ofifo_wr_data)   = ld_src_sel;
                `ld_uinst_last(uinst_ofifo_wr_data)      = 1'b0;
                `ld_uinst_interrupt(uinst_ofifo_wr_data) = 1'b0;
				`ld_uinst_report_to_host(uinst_ofifo_wr_data) = ld_report_to_host;

               if (uinst_ofifo_wr_ok) begin
                    // Write uOP
                    uinst_ofifo_wr_en = 1;

                    // Update control counters
                    ld_batch_count_nxt = (ld_batch_count == ld_batch-1)? 0: VRFAW'(ld_batch_count+1);
                    ld_count_nxt       = (ld_batch_count == ld_batch-1)? VRFAW'(ld_count+1): ld_count;

                    if ((ld_count == ld_size - 1) && (ld_batch_count == ld_batch-1)) begin
                        `ld_uinst_last(uinst_ofifo_wr_data) = 1'b1;
                        `ld_uinst_interrupt(uinst_ofifo_wr_data) = ld_interrupt;
                        ld_sched_state_nxt = LD_SCHED_INIT;
                    end
               end
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            ld_sched_state <= LD_SCHED_INIT;
        end
        else begin
            ld_sched_state <= ld_sched_state_nxt;
        end
        ld_vrf_id     <= ld_vrf_id_nxt;
        ld_vrf0_base0  <= ld_vrf0_base0_nxt;
        ld_vrf0_base1  <= ld_vrf0_base1_nxt;
        ld_vrf0_base2  <= ld_vrf0_base2_nxt;

        ld_vrf1_base0  <= ld_vrf1_base0_nxt;
        ld_vrf1_base1  <= ld_vrf1_base1_nxt;
        ld_vrf1_base2  <= ld_vrf1_base2_nxt;

        ld_size       <= ld_size_nxt;
        ld_src_sel    <= ld_src_sel_nxt;
        ld_interrupt  <= ld_interrupt_nxt;
	    ld_report_to_host  <= ld_report_to_host_nxt;
        ld_batch      <= ld_batch_nxt;
 
        ld_count       <= ld_count_nxt;
        ld_batch_count <= ld_batch_count_nxt;
    end

    
`ifdef DISPLAY_LD
    always @(posedge clk) begin
        if (uinst_ofifo_wr_en) begin
            $display("[%0t][LD uOP] vrf_id: %d, vrf0_addr: %d, vrf1_addr: %d, src: %d, last: %d, interrupt: %d, write_to_host: %d", 
            	$time,
		        `ld_uinst_vrf_id(uinst_ofifo_wr_data),
		        `ld_uinst_vrf0_addr(uinst_ofifo_wr_data), `ld_uinst_vrf1_addr(uinst_ofifo_wr_data),
		        `ld_uinst_src_sel(uinst_ofifo_wr_data),
		        `ld_uinst_last(uinst_ofifo_wr_data),
		        `ld_uinst_interrupt(uinst_ofifo_wr_data),
		        `ld_uinst_report_to_host(uinst_ofifo_wr_data));
        end
    end
`endif
    


endmodule
