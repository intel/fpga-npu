`include "npu.vh"

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name DONT_MERGE_REGISTER ON" *) module loader # (
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
    parameter IW       = `UIW_LD,
    // others
    parameter QDEPTH   = `QDEPTH,  // queue depth
    parameter WB_LMT   = `WB_LMT,  // write-back limit
    parameter WB_LMTW  = `WB_LMTW,
    parameter SIM_FLAG = `SIM_FLAG,
    parameter INPUT_BUFFER_SIZE = `INPUT_BUFFER_SIZE,
    parameter OUTPUT_BUFFER_SIZE = `OUTPUT_BUFFER_SIZE
) (
	// vrf write
	output                 o_vrf_wr_en [0:NTILE+2], 
	output [2*NVRF-1:0]    o_vrf_wr_id [0:NTILE+2],  
	output [VRFAW-1:0]     o_vrf0_wr_addr [0:NTILE+2],
	output [VRFAW-1:0]     o_vrf1_wr_addr [0:NTILE+2],
	output [ACCW*DOTW-1:0] o_vrf_wr_data [0:NTILE+2],
	// input datapath
	input                  i_in_wr_en,
	output                 o_in_wr_rdy,
	input  [EW*DOTW-1:0]   i_in_wr_din,
	output [$clog2(INPUT_BUFFER_SIZE)-1:0] o_in_usedw,
	input                  i_data_rd_en,
	output                 o_data_rd_rdy,
	output [EW*DOTW:0] o_data_rd_dout,
	output [$clog2(OUTPUT_BUFFER_SIZE)-1:0] o_data_usedw,
	// pipeline datapath
	input                  i_data_wr_en,
	output                 o_data_wr_rdy,
	input  [ACCW*DOTW-1:0] i_data_wr_din,
	// instruction
	input                  i_inst_wr_en,
	output                 o_inst_wr_rdy,
	input  [2*NVRF-1:0]    i_vrf_wr_id,  
	input  [VRFAW-1:0]     i_vrf0_wr_addr,
	input  [VRFAW-1:0]     i_vrf1_wr_addr,
	input                  i_vrf_wr_src, // 0:in_fifo, 1:wb_fifo
	input                  i_vrf_wr_last,
	input                  i_interrupt,
	input				   i_report_to_host,
	// from ld
	output                 o_tag_update_en [0:NTILE+2],

	//diagnostic signals
	input [2:0]		   diag_mode,
	output 		   o_data_wr_ok,
	input 		   i_mvu_data_wr_en,
	input [ACCW*NDPE-1:0]  i_mvu_data, 
	input 		   i_mfu0_data_wr_en,
	input [ACCW*DOTW-1:0]  i_mfu0_data, 

	input 		   i_mfu1_data_wr_en,
	input [ACCW*DOTW-1:0]  i_mfu1_data, 
	// o_done
	output o_start,
	// debug counters
	output [31:0]			o_debug_ld_ififo_counter,
	output [31:0]			o_debug_ld_wbfifo_counter,
	output [31:0]			o_debug_ld_instfifo_counter,
	output [31:0]			o_debug_ld_ofifo_counter,
	output [31:0] o_result_count,
	// clk & rst
	input                  clk, rst
);

    localparam FROM_IN = 0;
    localparam FROM_WB = 1;
	
	localparam LD_PIPELINE = 5;
	 
	localparam TREE_LVLS = 3;
	localparam FORK_FACTOR_0 = 2;
	localparam FORK_FACTOR_1 = 3;
	localparam FORK_FACTOR_2 = 4;

	localparam EMIT_MVU 	= 3'd1;
	localparam EMIT_MFU_0	= 3'd2;
	localparam EMIT_MFU_1	= 3'd3;
	localparam EMIT_OUT_VEC = 3'd4;
	
    // in_ififo
    wire in_ififo_wr_ok, in_ififo_wr_en; 
    wire in_ififo_rd_ok, in_ififo_rd_en;
    wire [EW*DOTW-1:0] in_ififo_wr_data, in_ififo_rd_data;
    wire [$clog2(INPUT_BUFFER_SIZE)-1:0] in_ififo_usedw;
    fifo #(
        .ID(0), .DW(EW*DOTW), .AW($clog2(INPUT_BUFFER_SIZE)), .DEPTH(INPUT_BUFFER_SIZE)) 
    in_ififo (
        .wr_ok   (in_ififo_wr_ok  ),
        .wr_en   (in_ififo_wr_en  ),
        .wr_data (in_ififo_wr_data),
        .rd_ok   (in_ififo_rd_ok  ),
        .rd_en   (in_ififo_rd_en  ),
        .rd_data (in_ififo_rd_data),
        .usedw 	 (in_ififo_usedw  ),
        .clk  (clk), .rst (rst));
		
    // connect input & output
    assign o_in_wr_rdy      = in_ififo_wr_ok;
    assign o_in_usedw 		= in_ififo_usedw;
    assign in_ififo_wr_en   = i_in_wr_en;
    assign in_ififo_wr_data = i_in_wr_din;
	 
	 assign o_start = in_ififo_rd_ok;
	
    // wb_ififo
    wire wb_ififo_wr_ok, wb_ififo_wr_en; 
    wire wb_ififo_rd_ok, wb_ififo_rd_en;
    wire [ACCW*DOTW-1:0] wb_ififo_wr_data, wb_ififo_rd_data;
	
    fifo #(
        .ID(1), .DW(ACCW*DOTW), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    wb_ififo (
        .wr_ok   (wb_ififo_wr_ok  ),
        .wr_en   (wb_ififo_wr_en  ),
        .wr_data (wb_ififo_wr_data),
        .rd_ok   (wb_ififo_rd_ok  ),
        .rd_en   (wb_ififo_rd_en  ),
        .rd_data (wb_ififo_rd_data),
        .clk (clk), .rst (rst));
		
    // connect input & output
    assign o_data_wr_rdy    = wb_ififo_wr_ok;
    assign wb_ififo_wr_en   = i_data_wr_en;
    assign wb_ififo_wr_data = i_data_wr_din;

    // inst_ififo
    wire          inst_ififo_wr_ok, inst_ififo_wr_en;
    wire          inst_ififo_rd_ok, inst_ififo_rd_en;
    wire [IW-1:0] inst_ififo_wr_data, inst_ififo_rd_data;
    fifo #(
        .ID(2), .DW(IW), .AW($clog2(QDEPTH)), .DEPTH(QDEPTH)) 
    inst_ififo (
        .wr_ok   (inst_ififo_wr_ok  ),
        .wr_en   (inst_ififo_wr_en  ),
        .wr_data (inst_ififo_wr_data),
        .rd_ok   (inst_ififo_rd_ok  ),
        .rd_en   (inst_ififo_rd_en  ),
        .rd_data (inst_ififo_rd_data),
        .clk (clk), .rst (rst));
		
    // connect input & output
    assign o_inst_wr_rdy      = inst_ififo_wr_ok;
    assign inst_ififo_wr_en   = i_inst_wr_en;
    assign inst_ififo_wr_data = {i_vrf_wr_id,
        i_vrf0_wr_addr,i_vrf1_wr_addr,i_vrf_wr_src,i_vrf_wr_last,i_interrupt,i_report_to_host};        
    
	 // in_ififo read ctrl
    assign in_ififo_rd_en   = in_ififo_rd_ok &&    // in_ififo is not empty 
                              inst_ififo_rd_ok &&  // an instruction is ready 
                              (`ld_uinst_src_sel(inst_ififo_rd_data) == FROM_IN);
    // wb_ififo read ctrl
    assign wb_ififo_rd_en   = wb_ififo_rd_ok &&    // wb_ififo is not empty
                              inst_ififo_rd_ok &&  // an instruction is ready
                              (`ld_uinst_src_sel(inst_ififo_rd_data) == FROM_WB);

    // inst_ififo read ctrl
    assign inst_ififo_rd_en = 
            inst_ififo_rd_ok &&  // an instruction & data are ready 
            ((in_ififo_rd_ok && `ld_uinst_src_sel(inst_ififo_rd_data) == FROM_IN) ||
             (wb_ififo_rd_ok && `ld_uinst_src_sel(inst_ififo_rd_data) == FROM_WB));

    reg S2_v0 [FORK_FACTOR_0-1:0]; 
	reg S2_v1 [(FORK_FACTOR_0*FORK_FACTOR_1)-1:0]; 
	reg S2_v2 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0]; 

	reg [IW-1:0] S2_inst0 [FORK_FACTOR_0-1:0];
	reg [IW-1:0] S2_inst1 [(FORK_FACTOR_0*FORK_FACTOR_1)-1:0];
	reg [IW-1:0] S2_inst2 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0];

	reg [ACCW*DOTW-1:0] S2_vrf_wr_data0	[FORK_FACTOR_0-1:0];
	reg [ACCW*DOTW-1:0] S2_vrf_wr_data1	[(FORK_FACTOR_0*FORK_FACTOR_1)-1:0];
	reg [ACCW*DOTW-1:0] S2_vrf_wr_data2	[(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0];

	reg S2_done0 [FORK_FACTOR_0-1:0]; 
	reg S2_done1 [(FORK_FACTOR_0*FORK_FACTOR_1)-1:0]; 
	reg S2_done2 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0]; 
	
	integer p, k;
	always @(posedge clk) begin
		// TREE BROADCAST FROM LOADER TO TILE, MFUS AND EVRF
		if (rst) begin
			for(p = 0; p < FORK_FACTOR_0; p = p + 1) begin
				S2_done0[p]			<= 0;
				S2_v0[p] 			<= 0;
				S2_inst0[p] 		<= 0;
				S2_vrf_wr_data0[p] 	<= 0;
			end
			
			for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1; p = p + 1) begin
				S2_done1[p]			<= 0;
				S2_v1[p] 			<= 0;
				S2_inst1[p] 		<= 0;
			end
			
			for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2; p = p + 1) begin
				S2_done2[p]			<= 0;
				S2_v2[p] 			<= 0;
				S2_inst2[p] 		<= 0;
			end
		end else begin
			for(p = 0; p < FORK_FACTOR_0; p = p + 1) begin
				S2_done0[p]			<= (inst_ififo_rd_en)? (`ld_uinst_interrupt(inst_ififo_rd_data) && `ld_uinst_last(inst_ififo_rd_data)) : 1'b0;;
				S2_v0[p] 			<= inst_ififo_rd_en;
				S2_inst0[p] 		<= inst_ififo_rd_data;
				for(k = 0; k < DOTW; k = k + 1) begin
					S2_vrf_wr_data0[p][k*ACCW+:ACCW] <= (in_ififo_rd_en)? {{(ACCW-EW){in_ififo_rd_data[(k+1)*EW-1]}}, in_ififo_rd_data[k*EW+:EW]} : (wb_ififo_rd_en)? wb_ififo_rd_data[k*ACCW+:ACCW] : 0;
				end
			end
			
			for(p = 0; p < FORK_FACTOR_0; p = p + 1) begin
				for(k = 0; k < FORK_FACTOR_1; k = k + 1) begin
					S2_done1[(p*FORK_FACTOR_1)+k] 			<= S2_done0[p];
					S2_v1[(p*FORK_FACTOR_1)+k] 				<= S2_v0[p];
					S2_inst1[(p*FORK_FACTOR_1)+k] 			<= S2_inst0[p];
				end
			end
			
			for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1; p = p + 1) begin
				for(k = 0; k < FORK_FACTOR_2; k = k + 1) begin
					S2_done2[(p*FORK_FACTOR_1)+k] 			<= S2_done1[p];
					S2_v2[(p*FORK_FACTOR_2)+k] 				<= S2_v1[p];
					S2_inst2[(p*FORK_FACTOR_2)+k] 			<= S2_inst1[p];
				end
			end
		end	
		
		for(p = 0; p < FORK_FACTOR_0; p = p + 1) begin
			for(k = 0; k < FORK_FACTOR_1; k = k + 1) begin
				S2_vrf_wr_data1[(p*FORK_FACTOR_1)+k] 	<= S2_vrf_wr_data0[p];
			end
		end
		
		for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1; p = p + 1) begin
			for(k = 0; k < FORK_FACTOR_2; k = k + 1) begin
				S2_vrf_wr_data2[(p*FORK_FACTOR_2)+k] 	<= S2_vrf_wr_data1[p];
			end
		end
	end
	
	genvar i;
	generate
		for (i = 0; i < NTILE+3; i = i + 1) begin: dist_tree
			assign o_vrf_wr_en[i]     = S2_v2[i] && (`ld_uinst_vrf_id(S2_inst2[i]) != 0);
			assign o_vrf_wr_id[i]     = `ld_uinst_vrf_id(S2_inst2[i]);
			assign o_vrf0_wr_addr[i]  = `ld_uinst_vrf0_addr(S2_inst2[i]);
			assign o_vrf1_wr_addr[i]  = `ld_uinst_vrf1_addr(S2_inst2[i]);
			assign o_vrf_wr_data[i]   = S2_vrf_wr_data2[i];
			assign o_tag_update_en[i] = (S2_v2[i])? `ld_uinst_last(S2_inst2[i]) : 0;
		end
	endgenerate
	
    // [PAC] interrupt host thread and register interrupt signal
    /*reg done_reg;
    always @ (posedge clk) begin
        if (rst) begin
            done_reg <= 1'b0;
        end else begin
            done_reg <= (S2_v2[0])? (`ld_uinst_interrupt(S2_inst2[0]) && `ld_uinst_last(S2_inst2[0])) : 1'b0;
        end
    end
    assign o_done = done_reg;*/

    wire data_ofifo_wr_ok;
    reg data_ofifo_wr_en;
    wire data_ofifo_rd_ok, data_ofifo_rd_en;
    reg [EW*DOTW:0] data_ofifo_wr_data; 
    wire [EW*DOTW:0] data_ofifo_rd_data;
	 wire [$clog2(OUTPUT_BUFFER_SIZE)-1:0] data_ofifo_usedw;
    fifo #(
       .ID(3), .DW(EW*DOTW+1), .AW($clog2(OUTPUT_BUFFER_SIZE)), .DEPTH(OUTPUT_BUFFER_SIZE)) 
    data_ofifo (
      .wr_ok   (data_ofifo_wr_ok  ),
      .wr_en   (data_ofifo_wr_en  ),
      .wr_data (data_ofifo_wr_data),
      .rd_ok   (data_ofifo_rd_ok  ),
      .rd_en   (data_ofifo_rd_en  ),
      .rd_data (data_ofifo_rd_data),
	  .usedw 	(data_ofifo_usedw),
      .clk  (clk), .rst (rst));
	  
    // connect input & output
    assign o_data_wr_ok       = data_ofifo_wr_ok;
    assign o_data_rd_rdy      = data_ofifo_rd_ok;
    assign o_data_rd_dout     = data_ofifo_rd_data;
	assign o_data_usedw 	  = data_ofifo_usedw;
    assign data_ofifo_rd_en   = i_data_rd_en;
 
    /*always@(*)
    begin
	data_ofifo_wr_en = 'd0;
	data_ofifo_wr_data = 'd0;
	case(diag_mode)
		EMIT_OUT_VEC:
		begin
    			data_ofifo_wr_en   = data_ofifo_wr_ok && S2_v2[0] && `ld_uinst_report_to_host(S2_inst2[0]);
    			data_ofifo_wr_data = S2_vrf_wr_data2[0];
		end
		EMIT_MVU:
		begin
			data_ofifo_wr_en   =  i_mvu_data_wr_en;
			data_ofifo_wr_data =  i_mvu_data;
		end
		EMIT_MFU_0:
		begin
			data_ofifo_wr_en   =  i_mfu0_data_wr_en;
			data_ofifo_wr_data =  i_mfu0_data;
		end
		EMIT_MFU_1:
		begin
			data_ofifo_wr_en   =  i_mfu1_data_wr_en;
			data_ofifo_wr_data =  i_mfu1_data;
		end
		default:
		begin
			data_ofifo_wr_en   = 'd0; 
			data_ofifo_wr_data = 'd0; 
	
		end	
	endcase

    end*/
    assign data_ofifo_wr_en   = data_ofifo_wr_ok && S2_v2[0] && `ld_uinst_report_to_host(S2_inst2[0]);
    //assign data_ofifo_wr_data = S2_vrf_wr_data2[0];
	 
	 genvar e;
	 generate 
		for (e = 0; e < DOTW; e = e + 1) begin
			assign data_ofifo_wr_data[e*EW+:EW] = S2_vrf_wr_data2[0][e*ACCW+:EW];
		end
	 endgenerate
	 assign data_ofifo_wr_data[EW*DOTW] = S2_done2[0];

    reg [31:0] debug_ld_ififo_counter, debug_ld_instfifo_counter, debug_ld_wbfifo_counter, debug_ld_ofifo_counter;
	always @(posedge clk) begin
		if(rst) begin
			debug_ld_ififo_counter    <= 'd0;
			debug_ld_instfifo_counter <= 'd0;
			debug_ld_wbfifo_counter   <= 'd0; 
			debug_ld_ofifo_counter    <= 'd0;
		end else begin
			case({in_ififo_wr_en, in_ififo_rd_en && in_ififo_rd_ok})
				2'b00: debug_ld_ififo_counter <= debug_ld_ififo_counter;
				2'b01: debug_ld_ififo_counter <= debug_ld_ififo_counter - 'd1;
				2'b10: debug_ld_ififo_counter <= debug_ld_ififo_counter + 'd1;
				2'b11: debug_ld_ififo_counter <= debug_ld_ififo_counter;
			endcase
			
			case({wb_ififo_wr_en, wb_ififo_rd_en && wb_ififo_rd_ok})
				2'b00: debug_ld_wbfifo_counter <= debug_ld_wbfifo_counter;
				2'b01: debug_ld_wbfifo_counter <= debug_ld_wbfifo_counter - 'd1;
				2'b10: debug_ld_wbfifo_counter <= debug_ld_wbfifo_counter + 'd1;
				2'b11: debug_ld_wbfifo_counter <= debug_ld_wbfifo_counter;
			endcase

			case({inst_ififo_wr_en, inst_ififo_rd_en && inst_ififo_rd_ok})
				2'b00: debug_ld_instfifo_counter <= debug_ld_instfifo_counter;
				2'b01: debug_ld_instfifo_counter <= debug_ld_instfifo_counter - 'd1;
				2'b10: debug_ld_instfifo_counter <= debug_ld_instfifo_counter + 'd1;
				2'b11: debug_ld_instfifo_counter <= debug_ld_instfifo_counter;
			endcase

			case({data_ofifo_wr_en, data_ofifo_rd_en && data_ofifo_rd_ok})
				2'b00: debug_ld_ofifo_counter <= debug_ld_ofifo_counter;
				2'b01: debug_ld_ofifo_counter <= debug_ld_ofifo_counter - 'd1;
				2'b10: debug_ld_ofifo_counter <= debug_ld_ofifo_counter + 'd1;
				2'b11: debug_ld_ofifo_counter <= debug_ld_ofifo_counter;
			endcase
		end
	end
	
	assign o_debug_ld_ififo_counter = debug_ld_ififo_counter;
	assign o_debug_ld_wbfifo_counter = debug_ld_wbfifo_counter;
	assign o_debug_ld_instfifo_counter = debug_ld_instfifo_counter;
	assign o_debug_ld_ofifo_counter = debug_ld_ofifo_counter;
	
	reg [31:0] result_count;
	always@(posedge clk) begin
		if(rst)begin
			result_count <= 0;
		end else begin
			if(data_ofifo_wr_en)begin
				result_count <= result_count + 1'b1;
			end
		end
	end
	assign o_result_count = result_count;
	
    // Debug
    /*always @(posedge clk) begin
        if(S2_v2[0])
            $display("[%0t][%s][S2] data: %x, wr_en: %b",
            $time, `__FILE__, S2_vrf_wr_data2[0],
            `ld_uinst_report_to_host(S2_inst2[0]));
        if (inst_ififo_wr_en)
            $display("[%0t][%s][S1] vrf_id: %b, vrf0__addr: %x, vrf1_addr: %x, src_sel: %b, last: %b, intr: %b",
            $time, `__FILE__,
            `ld_uinst_vrf_id(inst_ififo_wr_data), 
            `ld_uinst_vrf0_addr(inst_ififo_wr_data),
            `ld_uinst_vrf1_addr(inst_ififo_wr_data), 
            `ld_uinst_src_sel(inst_ififo_wr_data),
            `ld_uinst_last(inst_ififo_wr_data),
            `ld_uinst_interrupt(inst_ififo_wr_data));
    end*/
    

endmodule
