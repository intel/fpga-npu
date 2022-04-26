`include "npu.vh"

module mvu_tile # (	
	parameter EW       = `EW,
	parameter ACCW     = `ACCW,
	parameter DOTW     = `DOTW,
	parameter NTILE    = `NTILE,
	parameter NDPE     = `NDPE,
	parameter NMFU     = `NMFU,
	parameter NVRF     = `NVRF,
	parameter NMRF     = `NMRF,
	parameter VRFD     = `VRFD,
	parameter VRFAW    = `VRFAW,
	parameter MRFD     = `MRFD,
	parameter MRFAW    = `MRFAW,
	parameter MRFIDW   = `MRFIDW,
	parameter NSIZE    = `NSIZE,
	parameter NSIZEW   = `NSIZEW,
	parameter NTAG     = `NTAG,
	parameter NTAGW    = `NTAGW,
	parameter DOT_PER_DSP = `DOT_PER_DSP,
	parameter PRIME_DOTW = `PRIME_DOTW,
	parameter PDOTW = `PRIME_DOTW,
	parameter NUM_DSP  = `NUM_DSP,
	parameter NUM_ACCUM= `NUM_ACCUM,
	parameter ACCIDW	  = `ACCIDW,
	parameter VRFIDW   = `VRFIDW,
	parameter IW       = `UIW_MVU,
	parameter QDEPTH   = `QDEPTH,
	parameter WB_LMT   = `WB_LMT,
	parameter WB_LMTW  = `WB_LMTW,
	parameter MULT_LATENCY = `MULT_LATENCY,
	parameter DPE_PIPELINE = `DPE_PIPELINE,
	parameter SIM_FLAG = `SIM_FLAG,
	parameter HARD_TILE = 1,
	parameter DPES_THRESHOLD = `DPES_THRESHOLD,
	parameter PRECISION = `PRECISION,
	parameter BRAM_RD_LATENCY = `BRAM_RD_LATENCY,
	parameter MVU_TILE_ID = 0,
	parameter VRF0_ID = MVU_TILE_ID,
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter NUM_CHUNKS = NDPE/DOTW
) (
	input clk,
	input rst,
	// MRF Write Interface
	input [MRFAW-1:0] i_mrf_wr_addr [0:NDPE-1], 
	input [EW*DOTW-1:0] i_mrf_wr_data [0:NDPE-1], 
	input [MRFIDW-1:0] i_mrf_wr_en [0:NDPE-1],
	// Two VRF Write Interfaces
	input [VRFAW-1:0] i_vrf0_wr_addr, 
	input [VRFAW-1:0] i_vrf1_wr_addr, 
	input [EW*DOTW-1:0] i_vrf_wr_data, 
	input i_vrf_wr_en, 
	input [2*NVRF-1:0] i_vrf_wr_id, 
	input [VRFAW-1:0] i_vrf0_wr_addr1, 
	input [VRFAW-1:0] i_vrf1_wr_addr1, 
	input [EW*DOTW-1:0] i_vrf_wr_data1, 
	input i_vrf_wr_en1, 
	input [2*NVRF-1:0] i_vrf_wr_id1, 
	// Instruction Interface
	input [IW-1:0] i_inst,
	input i_inst_valid,
	// Tile Chain
	input  [3*ACCW*NDPE-1:0] i_from_prev_tile,
	output [3*ACCW*NDPE-1:0] o_to_next_tile,
	input  [3*ACCW*NDPE-1:0] i_from_prev_tile1,
	output [3*ACCW*NDPE-1:0] o_to_next_tile1,
	output o_valid,
	output [1:0] o_accum_op,
	output [ACCIDW-1:0] o_accum_sel
);
	
	localparam [1:0]
	ACC_OP_SET = 0,
	ACC_OP_UPD = 1,
	ACC_OP_WB  = 2,
	ACC_OP_NOP = 3;

	/*********************************/
	/** Reset Distribution to tiles **/
	/*********************************/
	localparam RESET_ENDPOINTS = NDPE;
	localparam RESET_DELAY = 8;

	wire delayed_rst [0:RESET_ENDPOINTS-1];

	star_interconnect # (
		.END_POINTS(RESET_ENDPOINTS),
		.DATAW(1),
		.LATENCY(RESET_DELAY)
	) rst_distribution (
		.clk(clk),
		.rst(1'b0),
		.i_star_in(rst),
		.o_star_out(delayed_rst)
	);
	
	localparam TREE_LVLS = 5;
	localparam 
	FORK_FACTOR_0 = 2,
	FORK_FACTOR_1 = 2,
	FORK_FACTOR_2 = 2,
	FORK_FACTOR_3 = 3,
	FORK_FACTOR_4 = 3;
	
	localparam
	S1_PIPELINE_ADDR_MRF = TREE_LVLS,
	S1_PIPELINE_DATA_MRF = BRAM_RD_LATENCY, 
	S1_PIPELINE_ADDR_VRF = BRAM_RD_LATENCY,	
	S1_PIPELINE_DATA_VRF = TREE_LVLS,
	MRF_ADDR_DELAY = (NUM_DSP+1)*DOT_PER_DSP-1,
	S2_PIPELINE 	= 1,
	S3_PIPELINE 	= 3,				
	WB_PIPELINE 	= S1_PIPELINE_ADDR_MRF + S1_PIPELINE_DATA_MRF + MRF_ADDR_DELAY + S2_PIPELINE + S3_PIPELINE;

	integer p, k;
	
	reg [IW-1:0] S2_inst	[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1:0];
	reg          S2_v		[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1:0];
	reg [IW-1:0] S2_inst_pp	[MRF_ADDR_DELAY-1:0];
	reg          S2_v_pp	[MRF_ADDR_DELAY-1:0];

	reg [MRFAW-1:0] S2_mrf_addr0 [FORK_FACTOR_0-1:0];
	reg [MRFAW-1:0] S2_mrf_addr1 [(FORK_FACTOR_0*FORK_FACTOR_1)-1:0];
	reg [MRFAW-1:0] S2_mrf_addr2 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0];
	reg [MRFAW-1:0] S2_mrf_addr3 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3)-1:0];
	reg [MRFAW-1:0] S2_mrf_addr4 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3*FORK_FACTOR_4)-1:0];
	reg [MRFAW-1:0] S2_mrf_addr_delay [0:MRF_ADDR_DELAY-1];
	
	reg [EW*PDOTW-1:0] S2_vrf_data0 [FORK_FACTOR_0-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data1 [(FORK_FACTOR_0*FORK_FACTOR_1)-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data2 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data3 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3)-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data4 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3*FORK_FACTOR_4)-1:0];
	
	wire [EW*PDOTW-1:0] vrf_rd_data;

	reg [EW*PDOTW-1:0] S2_vrf_data0_1 [FORK_FACTOR_0-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data1_1 [(FORK_FACTOR_0*FORK_FACTOR_1)-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data2_1 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2)-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data3_1 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3)-1:0];
	reg [EW*PDOTW-1:0] S2_vrf_data4_1 [(FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3*FORK_FACTOR_4)-1:0];
	
	wire [EW*PDOTW-1:0] vrf_rd_data1;
	
	always @ (posedge clk) begin
		S2_v[0]    <= i_inst_valid;          
		S2_inst[0] <= i_inst;

		S2_v_pp[0]    <= S2_v[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1];          
		S2_inst_pp[0] <= S2_inst[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1];
		
		S2_mrf_addr_delay[0] <= `mvu_uinst_mrf_addr(i_inst);
		for (p = 1; p < MRF_ADDR_DELAY; p = p + 1) begin
			S2_mrf_addr_delay[p] <= S2_mrf_addr_delay[p-1];
			S2_v_pp[p]    <= S2_v_pp[p-1];          
			S2_inst_pp[p] <= S2_inst_pp[p-1];
		end
		
		for (p = 0; p < FORK_FACTOR_0; p = p + 1) begin
			S2_mrf_addr0[p] <= S2_mrf_addr_delay [MRF_ADDR_DELAY-1];
			S2_vrf_data0[p] <= vrf_rd_data;
			S2_vrf_data0_1[p] <= vrf_rd_data1;
		end
	
		for(p = 1; p < S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF; p = p + 1) begin
			S2_v[p] 	<= S2_v[p-1];
			S2_inst[p] 	<= S2_inst[p-1];
		end
		
		// TREE BROADCAST OF MRF ADDRESS AND VRF DATA
		for(p = 0; p < FORK_FACTOR_0; p = p + 1) begin
			for(k = 0; k < FORK_FACTOR_1; k = k + 1) begin
				S2_mrf_addr1[(p*FORK_FACTOR_1)+k] <= S2_mrf_addr0[p];
				S2_vrf_data1[(p*FORK_FACTOR_1)+k] <= S2_vrf_data0[p];
				S2_vrf_data1_1[(p*FORK_FACTOR_1)+k] <= S2_vrf_data0_1[p];
			end
		end
		
		for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1; p = p + 1) begin
			for(k = 0; k < FORK_FACTOR_2; k = k + 1) begin
				S2_mrf_addr2[(p*FORK_FACTOR_2)+k] <= S2_mrf_addr1[p];
				S2_vrf_data2[(p*FORK_FACTOR_2)+k] <= S2_vrf_data1[p];
				S2_vrf_data2_1[(p*FORK_FACTOR_2)+k] <= S2_vrf_data1_1[p];
			end
		end

		for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2; p = p + 1) begin
			for(k = 0; k < FORK_FACTOR_3; k = k + 1) begin
				S2_mrf_addr3[(p*FORK_FACTOR_3)+k] <= S2_mrf_addr2[p];
				S2_vrf_data3[(p*FORK_FACTOR_3)+k] <= S2_vrf_data2[p];
				S2_vrf_data3_1[(p*FORK_FACTOR_3)+k] <= S2_vrf_data2_1[p];
			end
		end
		
		for(p = 0; p < FORK_FACTOR_0*FORK_FACTOR_1*FORK_FACTOR_2*FORK_FACTOR_3; p = p + 1) begin
			for(k = 0; k < FORK_FACTOR_4; k = k + 1) begin
				S2_mrf_addr4[(p*FORK_FACTOR_4)+k] <= S2_mrf_addr3[p];
				S2_vrf_data4[(p*FORK_FACTOR_4)+k] <= S2_vrf_data3[p];
				S2_vrf_data4_1[(p*FORK_FACTOR_4)+k] <= S2_vrf_data3_1[p];
			end
		end
		
	end

	//===== Stage 2: Reading from VRF and MRF =====//
    wire vrf_wr_en   = i_vrf_wr_en && (i_vrf_wr_id & (1<<(2*VRF0_ID)));
    wire [VRFAW-1:0] vrf_wr_addr = (i_vrf_wr_id[2*VRF0_ID+1] == 1'b0)? i_vrf0_wr_addr : i_vrf1_wr_addr;

    wire vrf_wr_en1   = i_vrf_wr_en1 && (i_vrf_wr_id1 & (1<<(2*VRF0_ID)));
    wire [VRFAW-1:0] vrf_wr_addr1 = (i_vrf_wr_id1[2*VRF0_ID+1] == 1'b0)? i_vrf0_wr_addr1 : i_vrf1_wr_addr1;
	
	//Instantiate VRF memory with specified width and depth
    mvu_vrf #(
		.ID(VRF0_ID), 
		.DW(EW*DOTW), 
		.AW(VRFAW), 
		.DEPTH(VRFD),
		.MODULE_ID("mvu-vrf"),
		.MVU_TILE(MVU_TILE_ID)
	) vrf (
		.wr_en   (vrf_wr_en), 
		.wr_addr (vrf_wr_addr),
		.wr_data (i_vrf_wr_data),
		.rd_addr (`mvu_uinst_vrf_addr(i_inst)),
		.rd_data (vrf_rd_data),
		.rd_id	(`mvu_uinst_vrf_rd_id(i_inst)),
		.rd_en (i_inst_valid),
		.clk(clk), 
		.rst(rst)
	);

	mvu_vrf #(
		.ID(VRF0_ID), 
		.DW(EW*DOTW), 
		.AW(VRFAW), 
		.DEPTH(VRFD),
		.MODULE_ID("mvu-vrf"),
		.MVU_TILE(MVU_TILE_ID)
	) vrf1 (
		.wr_en   (vrf_wr_en1), 
		.wr_addr (vrf_wr_addr1),
		.wr_data (i_vrf_wr_data1),
		.rd_addr (`mvu_uinst_vrf_addr(i_inst)),
		.rd_data (vrf_rd_data1),
		.rd_id	(`mvu_uinst_vrf_rd_id(i_inst)),
		.rd_en (i_inst_valid),
		.clk(clk), 
		.rst(rst)
	);
	
	wire [NDPE*EW*DOTW-1:0] mrf_rd_data;
	genvar a;
	generate
	for(a = 0; a < NDPE; a = a + 1) begin : gen_mrfs
		dpe_mrf #(
			.ID((MVU_TILE_ID*NDPE)+a), 
			.DW(EW*DOTW), 
			.AW(MRFAW), 
			.DEPTH(MRFD),
			.MODULE_ID("mvu-mrf")
		) mrf (
			.wr_en   ((i_mrf_wr_en[a] == (MVU_TILE_ID*NDPE+a+1))),
			.wr_addr (i_mrf_wr_addr[a]),
			.wr_data (i_mrf_wr_data[a]),
			.rd_addr (S2_mrf_addr4[a]),
			.rd_data (mrf_rd_data[(a*EW*DOTW)+(EW*DOTW-1):(a*EW*DOTW)]),
			.clk(clk), 
			.rst(delayed_rst[a])
		);
	end
	endgenerate

   //===== Stage 3: DPEs =====//
	
	//Pipeline the instruction and control for the same number of stages as the DPE
	reg [IW-1:0] S3_dpe_inst[DPE_PIPELINE-1:0];
	reg          S3_dpe_v	[DPE_PIPELINE-1:0];
	always @ (posedge clk) begin
		S3_dpe_v[0] <= S2_v_pp[MRF_ADDR_DELAY-1];
		S3_dpe_inst[0] <= S2_inst_pp[MRF_ADDR_DELAY-1];

		for (p = 1; p < DPE_PIPELINE; p = p + 1) begin
			S3_dpe_v	[p] <= S3_dpe_v[p-1];
			S3_dpe_inst	[p] <= S3_dpe_inst[p-1];
		end
	end
	
	//Instantiate DPEs
	reg  [ACCW*NDPE-1:0] S4_dpe_dout0 [S3_PIPELINE:0];
	reg  [ACCW*NDPE-1:0] S4_dpe_dout1 [S3_PIPELINE:0];
	reg  [ACCW*NDPE-1:0] S4_dpe_dout2 [S3_PIPELINE:0];
	reg  [NDPE-1:0] dpe_res_valid;
	reg  [ACCW*NDPE-1:0] dpe_res0, dpe_res1, dpe_res2;

	reg  [ACCW*NDPE-1:0] S4_dpe_dout0_1 [S3_PIPELINE:0];
	reg  [ACCW*NDPE-1:0] S4_dpe_dout1_1 [S3_PIPELINE:0];
	reg  [ACCW*NDPE-1:0] S4_dpe_dout2_1 [S3_PIPELINE:0];
	reg  [NDPE-1:0] dpe_res_valid_1;
	reg  [ACCW*NDPE-1:0] dpe_res0_1, dpe_res1_1, dpe_res2_1;
	
	genvar i;
	generate
		for(i = 0; i < NDPE; i = i + 1) begin : gen_dot
			dpe #(
				.LANES(DOTW),
				.REDW(ACCW),
				.SIM_FLAG(SIM_FLAG),
				.TILE_ID(MVU_TILE_ID),
				.DPE_ID(i)
			) dpe0 (
				.clk(clk),
				.reset(delayed_rst[i]),
				.ena(S2_v[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1] && `mvu_uinst_vrf_en(S2_inst[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1])),
				.din_a(mrf_rd_data[(i*EW*DOTW)+(EW*DOTW-1):(i*EW*DOTW)]),
				.valid_a(S2_v_pp[MRF_ADDR_DELAY-1]),
				.din_b(S2_vrf_data4[i]),
				.reg_ctrl(`mvu_uinst_reg_sel(S2_inst[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1])),
				.load_sel(`mvu_uinst_reg_sel(S2_inst_pp[MRF_ADDR_DELAY-1])),
				.dout({dpe_res2[(i*ACCW)+(ACCW-1):(i*ACCW)],dpe_res1[(i*ACCW)+(ACCW-1):(i*ACCW)],dpe_res0[(i*ACCW)+(ACCW-1):(i*ACCW)]}),
				.val_res(dpe_res_valid[i])
			);

			dpe #(
				.LANES(DOTW),
				.REDW(ACCW),
				.SIM_FLAG(SIM_FLAG),
				.TILE_ID(MVU_TILE_ID),
				.DPE_ID(i)
			) dpe1 (
				.clk(clk),
				.reset(delayed_rst[i]),
				.ena(S2_v[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1] && `mvu_uinst_vrf_en(S2_inst[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1])),
				.din_a(mrf_rd_data[(i*EW*DOTW)+(EW*DOTW-1):(i*EW*DOTW)]),
				.valid_a(S2_v_pp[MRF_ADDR_DELAY-1]),
				.din_b(S2_vrf_data4_1[i]),
				.reg_ctrl(`mvu_uinst_reg_sel(S2_inst[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1])),
				.load_sel(`mvu_uinst_reg_sel(S2_inst_pp[MRF_ADDR_DELAY-1])),
				.dout({dpe_res2_1[(i*ACCW)+(ACCW-1):(i*ACCW)],dpe_res1_1[(i*ACCW)+(ACCW-1):(i*ACCW)],dpe_res0_1[(i*ACCW)+(ACCW-1):(i*ACCW)]}),
				.val_res(dpe_res_valid_1[i])
			);
		end
	endgenerate
	
	//Prepare instruction, data and control signal for Stage 4
	reg [IW-1:0] S4_inst_delay;
	reg [IW-1:0] S4_inst[S3_PIPELINE-1:0];
	reg			 S4_v	[S3_PIPELINE-1:0];
	
	always @ (posedge clk) begin
		S4_inst_delay <= S3_dpe_inst [DPE_PIPELINE-1];
		S4_inst[0] <= S4_inst_delay;
		S4_v[0] <= dpe_res_valid[0];
		S4_dpe_dout0[0] <= dpe_res0;
		S4_dpe_dout1[0] <= dpe_res1;
		S4_dpe_dout2[0] <= dpe_res2;

		S4_dpe_dout0_1[0] <= dpe_res0_1;
		S4_dpe_dout1_1[0] <= dpe_res1_1;
		S4_dpe_dout2_1[0] <= dpe_res2_1;
		
		for (p = 1; p < S3_PIPELINE; p = p + 1) begin
			S4_inst	[p] <= S4_inst	[p-1];
			S4_v	[p] <= S4_v		[p-1];
		end
		
		for (p = 1; p < S3_PIPELINE+1; p = p + 1) begin
			S4_dpe_dout0[p] <= S4_dpe_dout0[p-1];
			S4_dpe_dout1[p] <= S4_dpe_dout1[p-1];
			S4_dpe_dout2[p] <= S4_dpe_dout2[p-1];

			S4_dpe_dout0_1[p] <= S4_dpe_dout0_1[p-1];
			S4_dpe_dout1_1[p] <= S4_dpe_dout1_1[p-1];
			S4_dpe_dout2_1[p] <= S4_dpe_dout2_1[p-1];
		end
	end
	
	wire [3*ACCW*NDPE-1:0] dpe_res;
	assign dpe_res = {S4_dpe_dout0[S3_PIPELINE-1], S4_dpe_dout1[S3_PIPELINE-1], S4_dpe_dout2[S3_PIPELINE-1]};

	wire [3*ACCW*NDPE-1:0] dpe_res_1;
	assign dpe_res_1 = {S4_dpe_dout0_1[S3_PIPELINE-1], S4_dpe_dout1_1[S3_PIPELINE-1], S4_dpe_dout2_1[S3_PIPELINE-1]};

	reg [3*ACCW*NDPE-1:0] reduce;
	reg [3*ACCW*NDPE-1:0] reduce1;
	reg [1:0] accum_op;
	reg [ACCIDW-1:0] accum_sel;
	reg valid_out;
	always @ (posedge clk) begin
		if (delayed_rst[0]) begin
			accum_op <= 2'b00;
			accum_sel <= 'd0;
			valid_out <= 1'b0;
		end else begin
			accum_op <= `mvu_uinst_acc_op(S4_inst[S3_PIPELINE-1]);
			accum_sel <= `mvu_uinst_acc_size(S4_inst[S3_PIPELINE-1]);
			valid_out <= S4_v[S3_PIPELINE-1];
		end
		for(p = 0; p < NDPE*3; p = p + 1) begin
			reduce[p*ACCW+:ACCW] <= dpe_res[p*ACCW+:ACCW] + i_from_prev_tile[p*ACCW+:ACCW];
			reduce1[p*ACCW+:ACCW] <= dpe_res_1[p*ACCW+:ACCW] + i_from_prev_tile1[p*ACCW+:ACCW];
		end
	end

	assign o_to_next_tile = reduce;
	assign o_valid  = valid_out;
	assign o_accum_sel = accum_sel;
	assign o_accum_op = accum_op;

	assign o_to_next_tile1 = reduce1;
	

`ifdef DISPLAY_MVU_TILE
  always @(posedge clk) begin
    if (MVU_TILE_ID == 0 && S2_v[S1_PIPELINE_ADDR_MRF+S1_PIPELINE_DATA_MRF-1]) begin
      $display("[%0t][%s][MVU_T0] mrf_data[0]: %d, vrf_data[0]: %d", 
          $time, `__FILE__,
          $signed(mrf_rd_data[EW-1:0]),
          $signed(S2_vrf_data4[0][EW-1:0])
      );
    end

    if (MVU_TILE_ID == 0 && valid_out) begin
    	$display("[%0t][%s][MVU_TILE] tile_output: %x", 
          $time, `__FILE__,
          reduce
      );
    end
  end
`endif

endmodule
