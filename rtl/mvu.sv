`include "npu.vh"

// This module implements a parameterizable vector adder reduction tree.
module add_reduction #(
	parameter EW    = 16,         // bit width of an element
	parameter DOTW  = 400,        // # elements
	parameter NTILE = 6           // # vectors
) (
	input [NTILE*EW*DOTW-1:0] din,
	input  valid_in,
	output reg [EW*DOTW-1:0] dout,
	output reg valid_out,
	input clk, rst
);

	reg [(NTILE/2)*EW*DOTW-1:0] sum;
	reg valid;

	genvar i, j;
	generate
		if (NTILE == 1) begin

			always @(posedge clk) begin
				dout <= din;
				if (rst) valid_out <= 0;
				else valid_out <= valid_in;
			end

		end else if (NTILE == 2) begin

			for (j = 0; j < DOTW; j = j + 1) begin : gen_elements_w_two_vectors
				always @(posedge clk) begin
				 	dout[j*EW+:EW] <= din[j*EW+:EW] + din[EW*DOTW+j*EW+:EW];
				end
			end
			always @(posedge clk) begin
				if (rst) valid_out <= 0;
				else valid_out <= valid_in;
			end

		end else begin

			for (i = 0; i < NTILE/2; i = i + 1) begin : gen_vectors
				for (j = 0; j < DOTW; j = j + 1) begin : gen_elements_w_mul_vectors
					always @(posedge clk) begin
						sum[i*EW*DOTW+j*EW+:EW] <= din[(2*i)*EW*DOTW+j*EW+:EW] + din[(2*i+1)*EW*DOTW+j*EW+:EW];
					end
				end
			end
			always @(posedge clk) begin
				if (rst) valid <= 0;
				else valid <= valid_in;
			end
			add_reduction #(
				.EW(EW), 
				.DOTW(DOTW), 
				.NTILE(NTILE/2)
			) add_reduction (
				.din(sum), 
				.dout(dout), 
				.valid_in(valid), 
				.valid_out(valid_out), 
				.clk(clk), 
				.rst(rst)
			);

		end
	endgenerate

endmodule

// This module implements the NPU's Matrix Vector Unit (MVU)
(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name DONT_MERGE_REGISTER ON" *) module mvu # (
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
	parameter MRFIDW   = `MRFIDW,
	// instructions
	parameter NSIZE    = `NSIZE,
	parameter NSIZEW   = `NSIZEW,
	parameter NTAG     = `NTAG,
	parameter NTAGW    = `NTAGW,
	parameter PRIME_DOTW = `PRIME_DOTW,
	parameter DOT_PER_DSP = `DOT_PER_DSP,
	parameter NUM_DSP  = `NUM_DSP,
	parameter NUM_ACCUM= `NUM_ACCUM,
	parameter ACCIDW	  = `ACCIDW,
	parameter VRFIDW   = `VRFIDW,
	parameter IW       = `UIW_MVU,
	// others
	parameter QDEPTH   = `QDEPTH,  // queue depth
	parameter CREDITW  = $clog2(QDEPTH),
	parameter WB_LMT   = `WB_LMT,  // write-back limit
	parameter WB_LMTW  = `WB_LMTW,
	parameter TILES_THRESHOLD = `TILES_THRESHOLD,
	parameter DPES_THRESHOLD = `DPES_THRESHOLD,
	parameter SIM_FLAG = `SIM_FLAG,
	parameter TARGET_FPGA = `TARGET_FPGA
) (
	// mrf write
	input [MRFIDW-1:0] i_mrf_wr_en,   // bit vector
	input [MRFAW-1:0] i_mrf_wr_addr,
	input [EW*DOTW-1:0] i_mrf_wr_data,
	// vrf write
	input [VRFAW-1:0]      i_vrf0_wr_addr [0:NTILE-1], 
	input [VRFAW-1:0]      i_vrf1_wr_addr [0:NTILE-1], 
	input [ACCW*DOTW-1:0]  i_vrf_wr_data [0:NTILE-1], 
	input                  i_vrf_wr_en [0:NTILE-1], 
	input [2*NVRF-1:0]     i_vrf_wr_id [0:NTILE-1], // bit vector 

	input [VRFAW-1:0]      i_vrf0_wr_addr1 [0:NTILE-1], 
	input [VRFAW-1:0]      i_vrf1_wr_addr1 [0:NTILE-1], 
	input [ACCW*DOTW-1:0]  i_vrf_wr_data1 [0:NTILE-1], 
	input                  i_vrf_wr_en1 [0:NTILE-1], 
	input [2*NVRF-1:0]     i_vrf_wr_id1 [0:NTILE-1], // bit vector 
	// instruction
	input                  i_inst_wr_en,
	output                 o_inst_wr_rdy,
	input  [VRFAW-1:0]     i_vrf_rd_addr, 
	input  [VRFIDW-1:0]    i_vrf_rd_id,
	input                  i_reg_sel,
	input  [MRFAW-1:0]     i_mrf_rd_addr, 
	input  [1:0]           i_acc_op,
	input  [NTAGW-1:0]     i_tag,
	input  [4:0]           i_acc_size,
	input                  i_vrf_en,
	// pipeline datapath
	input  [DOTW-1:0]      i_data_rd_en, 
	output [DOTW-1:0]      o_data_rd_rdy, 
	output [ACCW*DOTW-1:0] o_data_rd_dout,

	input  [DOTW-1:0]      i_data_rd_en1, 
	output [DOTW-1:0]      o_data_rd_rdy1, 
	output [ACCW*DOTW-1:0] o_data_rd_dout1,
	// from ld
	input                  i_tag_update_en [0:NTILE-1],
	// clk & rst
	input                  clk, 
	input 				   rst
);

	localparam TILE_CHAIN_LATENCY = 1;
	localparam ACCUM_TO_OFIFO = 3;
	localparam TILE_TO_ACCUM = 3;
	localparam [1:0] ACC_OP_SET = 0, ACC_OP_UPD = 1, ACC_OP_WB = 2, ACC_OP_SET_AND_WB = 3;

	/*********************************/
	/** Reset Distribution to tiles **/
	/*********************************/
	localparam RESET_ENDPOINTS = NTILE;
	localparam RESET_DELAY = 7;

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
	
	/***************/
	/** MRF Chain **/
	/***************/
	reg [MRFAW-1:0] mrf_wr_addr_chain [0:NTILE*NDPE-1];
	reg [EW*DOTW-1:0] mrf_wr_data_chain [0:NTILE*NDPE-1];
	reg [MRFIDW-1:0] mrf_wr_en_chain [0:NTILE*NDPE-1];
	
	integer chain_id;
	always @ (posedge clk) begin
		mrf_wr_addr_chain[NTILE*NDPE-1] <= i_mrf_wr_addr;
		mrf_wr_data_chain[NTILE*NDPE-1] <= i_mrf_wr_data;
		mrf_wr_en_chain[NTILE*NDPE-1] <= i_mrf_wr_en;
		for (chain_id = 0; chain_id < NTILE*NDPE-1; chain_id = chain_id + 1) begin
			mrf_wr_addr_chain[chain_id] <= mrf_wr_addr_chain[chain_id+1];
			mrf_wr_data_chain[chain_id] <= mrf_wr_data_chain[chain_id+1];
			mrf_wr_en_chain[chain_id] <= mrf_wr_en_chain[chain_id+1];
		end
	end

	/**********************/
	/** Width Truncation **/
	/**********************/
	wire [EW*DOTW-1:0] i_vrf_wr_data_red [0:NTILE-1];
	wire [EW*DOTW-1:0] i_vrf_wr_data_red1 [0:NTILE-1];
	genvar c, t;
	generate
		for (c = 0; c < DOTW; c = c + 1) begin : vrf_wr_data_type_converter
			for (t = 0; t < NTILE; t = t + 1) begin : tile_loop
				assign i_vrf_wr_data_red[t][c*EW+:EW] = i_vrf_wr_data[t][c*ACCW+:EW];
				assign i_vrf_wr_data_red1[t][c*EW+:EW] = i_vrf_wr_data1[t][c*ACCW+:EW];
			end
		end
	endgenerate
	

	/********************************/
	/** Hazard Detection Mechanism **/
	/********************************/
	wire [IW-1:0] inst_ififo_wr_data, inst_ififo_rd_data;
	reg [NTAGW-1:0] current_tag;
	reg r_tag_update_en;
	always @(posedge clk) begin
		if (rst) begin
			r_tag_update_en <= 1'b0;
			current_tag     <= 'd0;	
		end else begin
			r_tag_update_en <= i_tag_update_en[0];
			current_tag     <= current_tag + r_tag_update_en;
		end
	end

	/***************************/
	/** MVU instruction queue **/
	/***************************/
	wire 					inst_ififo_wr_ok, inst_ififo_wr_en;
	wire 					inst_ififo_rd_ok, inst_ififo_rd_en;
	
	// FIFO instantiation
	fifo #(
		.DW(IW), 
		.DEPTH(QDEPTH)
	) mvu_inst_ififo (
		.wr_ok 		(inst_ififo_wr_ok  ),
		.wr_en 		(inst_ififo_wr_en  ),
		.wr_data 	(inst_ififo_wr_data),
		.rd_ok 		(inst_ififo_rd_ok  ),
		.rd_en 		(inst_ififo_rd_en  ),
		.rd_data 	(inst_ififo_rd_data),
		.clk 			(clk), 
		.rst 			(rst)
	);
	
	// FIFO connections
	assign o_inst_wr_rdy      = inst_ififo_wr_ok;
	assign inst_ififo_wr_en   = i_inst_wr_en;
	assign inst_ififo_wr_data = {i_vrf_rd_addr, i_vrf_rd_id, i_reg_sel, i_mrf_rd_addr, i_tag, i_acc_op, i_acc_size, i_vrf_en};

	// Issue instruction if: 
	// (1) FIFO is not empty, (2) there is enough space in receiving FIFO, (3) instruction tag is bigger than current tag
	reg [CREDITW:0] credit;
	assign inst_ififo_rd_en = inst_ififo_rd_ok && (credit < QDEPTH) && 
		(current_tag >= `mvu_uinst_tag(inst_ififo_rd_data));

	// Instruction distribution to tiles
	wire [IW:0] tile_inst [0:NTILE-1];
	daisy_chain_interconnect # (
		.DATAW(IW+1),
		.END_POINTS(NTILE),
		.LATENCY_PER_HOP(TILE_CHAIN_LATENCY+1)
	) inst_dc_interconnect (
		.clk(clk),
		.rst(rst),
		.i_daisy_chain_in({inst_ififo_rd_en, inst_ififo_rd_data}),
		.o_daisy_chain_out(tile_inst)
	);

	/*************************/
	/** Tiles instantiation **/
	/*************************/
	wire [3*ACCW*NDPE-1:0] tile_output_data [0:NTILE-1];
	wire [3*ACCW*NDPE-1:0] tile_input_data [0:NTILE-1];

	wire [3*ACCW*NDPE-1:0] tile_output_data1 [0:NTILE-1];
	wire [3*ACCW*NDPE-1:0] tile_input_data1 [0:NTILE-1];

	wire tile_output_valid [0:NTILE-1];
	wire [1:0] tile_output_accum_op [0:NTILE-1];
	wire [ACCIDW-1:0] tile_output_accum_sel [0:NTILE-1];
	genvar tile_id;
	generate
		for (tile_id = 0; tile_id < NTILE; tile_id = tile_id + 1) begin: gen_tile
			mvu_tile #(
				.MVU_TILE_ID 		 (tile_id),
				.VRF0_ID 				 (tile_id), 
				.HARD_TILE 			 (tile_id < TILES_THRESHOLD)
			) mvu_tile (
				.clk 						 (clk), 
				.rst 						 (delayed_rst[tile_id]),
				// MRF write from outside world
				.i_mrf_wr_addr   (mrf_wr_addr_chain[(tile_id*NDPE)+:NDPE]), 
				.i_mrf_wr_data   (mrf_wr_data_chain[(tile_id*NDPE)+:NDPE]), 
				.i_mrf_wr_en     (mrf_wr_en_chain[(tile_id*NDPE)+:NDPE]),
				// VRF write from loader
				.i_vrf0_wr_addr  (i_vrf0_wr_addr[tile_id]), 
				.i_vrf1_wr_addr  (i_vrf1_wr_addr[tile_id]), 
				.i_vrf_wr_data   (i_vrf_wr_data_red[tile_id]), 
				.i_vrf_wr_en     (i_vrf_wr_en[tile_id]),
				.i_vrf_wr_id     (i_vrf_wr_id[tile_id]),

				.i_vrf0_wr_addr1  (i_vrf0_wr_addr1[tile_id]), 
				.i_vrf1_wr_addr1  (i_vrf1_wr_addr1[tile_id]), 
				.i_vrf_wr_data1   (i_vrf_wr_data_red1[tile_id]), 
				.i_vrf_wr_en1     (i_vrf_wr_en1[tile_id]),
				.i_vrf_wr_id1     (i_vrf_wr_id1[tile_id]),
				// Instruction input
				.i_inst 		  (tile_inst[tile_id][IW-1:0]),
				.i_inst_valid 	  (tile_inst[tile_id][IW]),
				// Tile chain
				.i_from_prev_tile (tile_input_data[tile_id]),
				.o_to_next_tile   (tile_output_data[tile_id]),

				.i_from_prev_tile1 (tile_input_data1[tile_id]),
				.o_to_next_tile1   (tile_output_data1[tile_id]),
				// Tile output
				.o_valid 		  (tile_output_valid[tile_id]),
				.o_accum_op 	  (tile_output_accum_op[tile_id]),
				.o_accum_sel 	  (tile_output_accum_sel[tile_id])
			);

			if(tile_id == 0)  begin
				assign tile_input_data[tile_id] = {(3*ACCW*NDPE){1'b0}};
				assign tile_input_data1[tile_id] = {(3*ACCW*NDPE){1'b0}};
			end else begin
				pipeline_interconnect # (
					.DATAW(3*ACCW*NDPE),
					.LATENCY(TILE_CHAIN_LATENCY)
				) tile_chain_pipe (
					.clk(clk),
					.rst(rst),
					.i_pipe_in(tile_output_data[tile_id-1]),
					.o_pipe_out(tile_input_data[tile_id])
				);

				pipeline_interconnect # (
					.DATAW(3*ACCW*NDPE),
					.LATENCY(TILE_CHAIN_LATENCY)
				) tile_chain_pipe1 (
					.clk(clk),
					.rst(rst),
					.i_pipe_in(tile_output_data1[tile_id-1]),
					.o_pipe_out(tile_input_data1[tile_id])
				);
			end 
		end
	endgenerate

	wire [3*ACCW*NDPE-1:0] accum_input_data;
	wire [3*ACCW*NDPE-1:0] accum_input_data1;
	wire [3+ACCIDW-1:0] accum_input_ctrl [0:3*NDPE-1];

	pipeline_interconnect # (
		.DATAW(3*ACCW*NDPE),
		.LATENCY(TILE_TO_ACCUM)
	) tile_to_accum_data (
		.clk(clk),
		.rst(rst),
		.i_pipe_in(tile_output_data[NTILE-1]),
		.o_pipe_out(accum_input_data)
	);

	pipeline_interconnect # (
		.DATAW(3*ACCW*NDPE),
		.LATENCY(TILE_TO_ACCUM)
	) tile_to_accum_data1 (
		.clk(clk),
		.rst(rst),
		.i_pipe_in(tile_output_data1[NTILE-1]),
		.o_pipe_out(accum_input_data1)
	);

	star_interconnect # (
		.END_POINTS(3*NDPE),
		.DATAW(3+ACCIDW),
		.LATENCY(TILE_TO_ACCUM)
	) tile_to_accum_ctrl (
		.clk(clk),
		.rst(rst),
		.i_star_in({tile_output_valid[NTILE-1], tile_output_accum_op[NTILE-1], tile_output_accum_sel[NTILE-1]}),
		.o_star_out(accum_input_ctrl)
	);

	/******************/
	/** Accumulators **/
	/******************/
	wire [3*ACCW*NDPE-1:0] accum_output_data, data_ofifo_input_data;
	wire [3*ACCW*NDPE-1:0] accum_output_data1, data_ofifo_input_data1;
	wire [NDPE-1:0] accum_output_valid;
	wire [NDPE-1:0] accum_output_valid1;
	wire [NDPE-1:0] data_ofifo_input_valid;
	wire [NDPE-1:0] data_ofifo_input_valid1;

	bram_accum accum (
		.clk 					(clk),
		.rst 					(rst),
		.accum_ctrl 	(accum_input_ctrl),
		.accum_in 		(accum_input_data),
		.valid_out 		(accum_output_valid),
		.accum_out 		(accum_output_data)
	);

	bram_accum accum1 (
		.clk 					(clk),
		.rst 					(rst),
		.accum_ctrl 	(accum_input_ctrl),
		.accum_in 		(accum_input_data1),
		.valid_out 		(accum_output_valid1),
		.accum_out 		(accum_output_data1)
	);

	pipeline_interconnect # (
		.DATAW(3*ACCW*NDPE+NDPE),
		.LATENCY(ACCUM_TO_OFIFO)
	) accum_to_fifo_pipe (
		.clk(clk),
		.rst(rst),
		.i_pipe_in({accum_output_valid, accum_output_data}),
		.o_pipe_out({data_ofifo_input_valid, data_ofifo_input_data})
	);

	pipeline_interconnect # (
		.DATAW(3*ACCW*NDPE+NDPE),
		.LATENCY(ACCUM_TO_OFIFO)
	) accum_to_fifo_pipe1 (
		.clk(clk),
		.rst(rst),
		.i_pipe_in({accum_output_valid1, accum_output_data1}),
		.o_pipe_out({data_ofifo_input_valid1, data_ofifo_input_data1})
	);

	/**********************/
	/** Data Output FIFO **/
	/**********************/
	wire [NDPE-1:0] data_ofifo_rd_ok;
	wire [DOTW-1:0] data_ofifo_rd_en;
	wire [ACCW*DOTW-1:0] data_ofifo_rd_data;

	wire [NDPE-1:0] data_ofifo_rd_ok1;
	wire [DOTW-1:0] data_ofifo_rd_en1;
	wire [ACCW*DOTW-1:0] data_ofifo_rd_data1;

	genvar f;
	generate
		for(f = 0; f < NDPE; f = f + 1) begin: gen_ofifo
			asym_fifo #(
				.IDW 		(3*ACCW),
				.ODW 		(ACCW), 
				.DEPTH 		(QDEPTH)
			) mvu_data_ofifo (
				.clk 		(clk), 
				.rst 		(rst),
				.wr_en   	(data_ofifo_input_valid[f]),
				.wr_data 	({data_ofifo_input_data[(2*ACCW*NDPE)+f*ACCW+:ACCW], 
							  data_ofifo_input_data[(ACCW*NDPE)+f*ACCW+:ACCW], 
							  data_ofifo_input_data[f*ACCW+:ACCW]}),
				.rd_ok   	(data_ofifo_rd_ok[f]),
				.rd_en   	(data_ofifo_rd_en[f]),
				.rd_data 	(data_ofifo_rd_data[f*ACCW+:ACCW])
			);

			asym_fifo #(
				.IDW 		(3*ACCW),
				.ODW 		(ACCW), 
				.DEPTH 		(QDEPTH)
			) mvu_data_ofifo1 (
				.clk 		(clk), 
				.rst 		(rst),
				.wr_en   	(data_ofifo_input_valid1[f]),
				.wr_data 	({data_ofifo_input_data1[(2*ACCW*NDPE)+f*ACCW+:ACCW], 
							  data_ofifo_input_data1[(ACCW*NDPE)+f*ACCW+:ACCW], 
							  data_ofifo_input_data1[f*ACCW+:ACCW]}),
				.rd_ok   	(data_ofifo_rd_ok1[f]),
				.rd_en   	(data_ofifo_rd_en1[f]),
				.rd_data 	(data_ofifo_rd_data1[f*ACCW+:ACCW])
			);
		end
	endgenerate

	assign data_ofifo_rd_en 	= i_data_rd_en;
	assign o_data_rd_rdy 		= data_ofifo_rd_ok;
	assign o_data_rd_dout 		= data_ofifo_rd_data;

	assign data_ofifo_rd_en1 	= i_data_rd_en1;
	assign o_data_rd_rdy1 		= data_ofifo_rd_ok1;
	assign o_data_rd_dout1 		= data_ofifo_rd_data1;

	// Instruction issuing logic
	always @ (posedge clk) begin
		if (rst) begin
			credit <= 'd0;
		end else begin
			case({inst_ififo_rd_en && (`mvu_uinst_tag(inst_ififo_rd_data) != {(NTAGW){1'b1}}) && (`mvu_uinst_acc_op(inst_ififo_rd_data) >= ACC_OP_WB), data_ofifo_input_valid[0]})
				2'b01: credit <= (CREDITW+1)'(credit - 1'b1);
				2'b10: credit <= (CREDITW+1)'(credit + 1'b1);
				default: credit <= credit;
			endcase
		end
	end

`ifdef DISPLAY_MVU   
always @(posedge clk) begin
  if (data_ofifo_input_valid) begin
    $display("[%0t][MVU] mvu_output: %d, credit: %d", 
    	$time, 
    	$signed(data_ofifo_input_data[ACCW-1:0]),
    	credit);
  end

  if (inst_ififo_rd_en && (`mvu_uinst_acc_op(inst_ififo_rd_data) == ACC_OP_WB) && !data_ofifo_input_valid) begin
  	$display("[%0t][MVU] ofifo_credit: %d", $time, credit + 1);
  end else if (data_ofifo_input_valid && !(inst_ififo_rd_en && (`mvu_uinst_acc_op(inst_ififo_rd_data) == ACC_OP_WB))) begin
  	$display("[%0t][MVU] ofifo_credit: %d", $time, credit - 1);
  end

  if (r_tag_update_en) begin
  	$display("[%0t][MVU] tag: %d", $time, current_tag+1);
  end
end
`endif

endmodule