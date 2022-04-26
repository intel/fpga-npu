`include "npu.vh"

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name DONT_MERGE_REGISTER ON" *) module mfu # (
	parameter VRF0_ID = 1,
	parameter VRF1_ID = 2,
	parameter MFU_ID = "",
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
	parameter IW       = `UIW_MFU,
	// others
	parameter QDEPTH   = `QDEPTH,  // queue depth
	parameter CREDITW  = $clog2(QDEPTH),
	parameter WB_LMT   = `WB_LMT,  // write-back limit
	parameter WB_LMTW  = `WB_LMTW,
	parameter BRAM_RD_LATENCY = `BRAM_RD_LATENCY,
	parameter SIM_FLAG = `SIM_FLAG,
	parameter RTL_DIR = `RTL_DIR
) (
	// vrf write
	input  [VRFAW-1:0]  	i_vrf0_wr_addr, 
	input  [VRFAW-1:0]  	i_vrf1_wr_addr, 
	input  [ACCW*DOTW-1:0] 	i_vrf_wr_data, 
	input               	i_vrf_wr_en, 
	input  [2*NVRF-1:0] 	i_vrf_wr_id, // bit vector 
	// pipeline datapath
	input  [DOTW-1:0]       i_data_wr_en,
	output [DOTW-1:0]       o_data_wr_rdy,
	input  [ACCW*DOTW-1:0] 	i_data_wr_din,
	input  [DOTW-1:0]       i_data_rd_en, 
	output [DOTW-1:0]       o_data_rd_rdy, 
	output [ACCW*DOTW-1:0] 	o_data_rd_dout,
	// insturction 
	input               	i_inst_wr_en,
	output              	o_inst_wr_rdy,
	input  [VRFAW-1:0]  	i_vrf0_rd_addr, 
	input  [VRFAW-1:0]  	i_vrf1_rd_addr,
	input  [5:0] 			i_func_op,
	input  [NTAGW-1:0] 		i_tag,
	// from ld
	input               	i_tag_update_en,
	// clk & rst
	input               	clk, rst
);

	localparam [1:0]
	ACT_OP_NOP  = 0,
	ACT_OP_RELU = 1,
	ACT_OP_SIGM = 2,
	ACT_OP_TANH = 3;

	localparam [2:0]
	ADDSUB_OP_NOP     = 0,
	ADDSUB_OP_ADD     = 1,
	ADDSUB_OP_A_SUB_B = 2,
	ADDSUB_OP_B_SUB_A = 3,
	ADDSUB_OP_MAX     = 4;

	localparam 
	MUL_OP_NOP = 0,
	MUL_OP_MUL = 1;
	
	localparam 	ISSUE_CTRL_LATENCY = 2,
				INST_TO_ACT_LATENCY = 2,
				TANH_SIG_LATENCY = 1 + BRAM_RD_LATENCY,
				VRF0_TO_ADDERS_LATENCY = 3, // Must be > 2
				VRF1_TO_MULTS_LATENCY = 2,
				MULT_LATENCY = 6,
				MULT_TO_OFIFO_LATENCY = 2;
	

	/********************************/
	/** Hazard Detection Mechanism **/
	/********************************/
	reg [NTAGW-1:0] current_tag;
	reg r_tag_update_en;
	wire [IW-1:0] inst_ififo_wr_data, inst_ififo_rd_data;
	always @(posedge clk) begin
		if (rst) begin
			r_tag_update_en <= 1'b0;
			current_tag <= 'd0;
		end else begin
			r_tag_update_en <= i_tag_update_en;
			current_tag <= (r_tag_update_en)? NTAGW'(current_tag + 1'b1): current_tag;
		end
	end


	/***************************/
	/** MFU instruction queue **/
	/***************************/
	wire          inst_ififo_wr_ok, inst_ififo_wr_en;
	wire          inst_ififo_rd_ok, inst_ififo_rd_en;

	//FIFO instantiation
	inst_fifo #(
		.ID		(0), 
		.DW		(IW), 
		.AW		($clog2(QDEPTH)), 
		.DEPTH	(QDEPTH),
		.MODULE ("mfu")
	) inst_ififo (
		.wr_ok   (inst_ififo_wr_ok  ),
		.wr_en   (inst_ififo_wr_en  ),
		.wr_data (inst_ififo_wr_data),
		.rd_ok   (inst_ififo_rd_ok  ),
		.rd_en   (inst_ififo_rd_en  ),
		.rd_data (inst_ififo_rd_data),
		.clk     (clk), 
		.rst     (rst),
		.current_tag (current_tag)
	);

	// FIFO connections
	assign o_inst_wr_rdy      = inst_ififo_wr_ok;
	assign inst_ififo_wr_en   = i_inst_wr_en;
	assign inst_ififo_wr_data = {i_vrf0_rd_addr,i_vrf1_rd_addr,i_tag,i_func_op};
	
	
	/*********************/
    /**  MFU data queue **/
    /*********************/
    wire [DOTW-1:0] data_ififo_wr_ok, data_ififo_rd_ok;
    wire [DOTW-1:0] data_ififo_wr_en;
    wire data_ififo_rd_en;
    wire [ACCW*DOTW-1:0] data_ififo_wr_data, data_ififo_rd_data;
    wire data_rd_en [0:DOTW-1];
    wire [CREDITW-1:0] data_usedw [0:DOTW-1];

    // FIFO instantiation
    genvar ff;
    generate
        for(ff = 0; ff < DOTW; ff = ff + 1) begin: gen_mfu_ififos
            fifo #(
                .ID      (0), 
                .DW      (ACCW), 
                .AW      ($clog2(QDEPTH)), 
                .DEPTH   (QDEPTH)
            ) data_ififo (
                .wr_ok   (data_ififo_wr_ok[ff]),
                .wr_en   (data_ififo_wr_en[ff]),
                .wr_data (data_ififo_wr_data[ACCW*(ff+1)-1:ACCW*ff]),
                .rd_ok   (data_ififo_rd_ok[ff]),
                .rd_en   (data_rd_en[ff]),
                .rd_data (data_ififo_rd_data[ACCW*(ff+1)-1:ACCW*ff]),
                .clk     (clk), 
                .rst     (rst),
                .usedw 	 (data_usedw[ff])
            );
        end
    endgenerate
    
    // FIFO connections
    assign o_data_wr_rdy      = data_ififo_wr_ok;
    assign data_ififo_wr_en   = i_data_wr_en;
    assign data_ififo_wr_data = i_data_wr_din;


    /*******************/
	/** Issuing Logic **/
	/*******************/
	reg  [CREDITW-1:0] credit, in_flight;
    wire issue_ok;
    wire inst_rd_en;
    wire [IW-1:0] inst_rd_data;

    star_interconnect # (
        .END_POINTS(DOTW),
        .DATAW(1),
        .LATENCY(ISSUE_CTRL_LATENCY)
    ) issue_data_pipe (
        .clk(clk),
        .rst(rst),
        .i_star_in(data_ififo_rd_en),
        .o_star_out(data_rd_en)
    );

    pipeline_interconnect # (
        .DATAW(IW+1),
        .LATENCY(ISSUE_CTRL_LATENCY)
    ) issue_inst_pipe (
        .clk(clk),
        .rst(rst),
        .i_pipe_in({inst_ififo_rd_en, inst_ififo_rd_data}),
        .o_pipe_out({inst_rd_en, inst_rd_data})
    );

	always @ (posedge clk) begin
		if (rst) begin
			in_flight <= 'd0;
		end else begin
			case({data_ififo_rd_en, data_rd_en[0]})
				2'b01: in_flight <= CREDITW'(in_flight - 1'b1);
				2'b10: in_flight <= CREDITW'(in_flight + 1'b1);
				default: in_flight <= in_flight;
			endcase
		end
	end

	assign issue_ok = (credit < QDEPTH); //&& (current_tag >= `mfu_uinst_tag(inst_ififo_rd_data));
	assign inst_ififo_rd_en = inst_ififo_rd_ok && (data_usedw[0] > in_flight) && issue_ok;
	assign data_ififo_rd_en = inst_ififo_rd_ok && (data_usedw[0] > in_flight) && issue_ok;
	

	/************************************/
	/** Inst & data to Activation Unit **/
	/************************************/
	wire [IW-1:0] act_inst;
	wire [ACCW*DOTW-1:0] act_data;
	wire act_valid;

	pipeline_interconnect # (
		.DATAW 		(IW+(ACCW*DOTW)+1),
		.LATENCY 	(INST_TO_ACT_LATENCY)
	) inst_to_act_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({inst_rd_en, inst_rd_data, data_ififo_rd_data}),
		.o_pipe_out ({act_valid, act_inst, act_data})
	);


	/**********************/
	/** Activation Units **/
	/**********************/
	wire [ACCW*DOTW-1:0] sigmoid_out, tanh_out, relu_result, nop_result;

	// Instantiate activation units
	genvar act_unit_id;
	generate
		for (act_unit_id = 0; act_unit_id < DOTW; act_unit_id = act_unit_id + 1) begin : gen_act
			tanh # (
				.RTL_DIR(RTL_DIR)
			) tanh_core (
				.clk 	(clk),
				.rst 	(rst),
				.x 		(act_data[act_unit_id*ACCW+:ACCW]),
				.result (tanh_out[act_unit_id*ACCW+:ACCW])
			);
			
			sigmoid # (
				.RTL_DIR(RTL_DIR)
			) sigmoid_core (
				.clk 	(clk),
				.rst 	(rst),
				.x 		(act_data[act_unit_id*ACCW+:ACCW]),
				.result	(sigmoid_out[act_unit_id*ACCW+:ACCW])
			);
			assign relu_result[act_unit_id*ACCW+:ACCW] = (act_data[(act_unit_id+1)*ACCW-1])? 0 : act_data[act_unit_id*ACCW+:ACCW];
			assign nop_result[act_unit_id*ACCW+:ACCW] = act_data[act_unit_id*ACCW+:ACCW];
		end
	endgenerate

	// Align ReLU, NOP and instruction to outputs of Tanh and Sigmoid
	wire act_out_valid;
	wire [IW-1:0] act_out_inst, vrf0_rd_inst;
	wire [ACCW*DOTW-1:0] nop_out, relu_out;

	pipeline_interconnect # (
		.DATAW 		((2*ACCW*DOTW)+IW+1),
		.LATENCY 	(TANH_SIG_LATENCY)
	) act_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({act_valid, act_inst, relu_result, nop_result}),
		.o_pipe_out ({act_out_valid, act_out_inst, relu_out, nop_out})
	);

	pipeline_interconnect # (
		.DATAW 		(IW),
		.LATENCY 	(TANH_SIG_LATENCY-BRAM_RD_LATENCY)
	) vrf0_rdaddr_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({act_inst}),
		.o_pipe_out ({vrf0_rd_inst})
	);

	// Choosing activation output
	reg [ACCW*DOTW-1:0] activation_out;
	always @ (*) begin	
		case (`mfu_uinst_act_op(act_out_inst))
			ACT_OP_RELU: activation_out <= relu_out;
			ACT_OP_SIGM: activation_out <= sigmoid_out;
			ACT_OP_TANH: activation_out <= tanh_out;
			default: activation_out <= nop_out;
		endcase
	end


	/************************/
	/** Add/Subtract Units **/
	/************************/
	wire [ACCW*DOTW-1:0] vrf0_rd_data, vrf0_wr_data;
	wire vrf0_wr_en;
	wire [VRFAW-1:0] vrf0_wr_addr, vrf0_rd_addr;
	
	// VRF0 instantiation
	ram #(
		.ID 		(VRF0_ID), 
		.DW 		(ACCW*DOTW), 
		.AW 		(VRFAW), 
		.DEPTH 		(VRFD),
		.MODULE_ID 	("mfu-vrf")
	) vrf0 (
		.wr_en 		(vrf0_wr_en), 
		.wr_addr 	(vrf0_wr_addr),
		.wr_data 	(vrf0_wr_data),
		.rd_addr 	(vrf0_rd_addr),
		.rd_data 	(vrf0_rd_data),
		.clk 		(clk), 
		.rst 		(rst)
	);
	assign vrf0_wr_en 	= i_vrf_wr_en && (i_vrf_wr_id & (1<<(2*VRF0_ID)));
	assign vrf0_wr_addr = (i_vrf_wr_id[2*VRF0_ID+1] == 1'b0)? i_vrf0_wr_addr : i_vrf1_wr_addr;
	assign vrf0_wr_data = i_vrf_wr_data;
	assign vrf0_rd_addr = `mfu_uinst_vrf0_addr(vrf0_rd_inst);

	// Pipeline from VRF0 to add/subtract units
	wire add_sub_valid;
	wire [IW-1:0] add_sub_inst, vrf1_rd_inst;
	wire [ACCW*DOTW-1:0] add_sub_in_act, add_sub_in_vrf;
	pipeline_interconnect # (
		.DATAW 		(IW+1+(2*ACCW*DOTW)),
		.LATENCY 	(VRF0_TO_ADDERS_LATENCY)
	) vrf0_to_adders_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({act_out_valid, act_out_inst, activation_out, vrf0_rd_data}),
		.o_pipe_out ({add_sub_valid, add_sub_inst, add_sub_in_act, add_sub_in_vrf})
	);

	pipeline_interconnect # (
		.DATAW 		(IW),
		.LATENCY 	(VRF0_TO_ADDERS_LATENCY-BRAM_RD_LATENCY+1)
	) vrf1_rdaddr_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({act_out_inst}),
		.o_pipe_out ({vrf1_rd_inst})
	);

	// Perform operations and align instruction
	reg [ACCW*DOTW-1:0] add_res, sub_a_b_res, sub_b_a_res, max_res, nop_res;
	reg add_sub_out_valid;
	reg [IW-1:0] add_sub_out_inst;

	integer unit_id;
	always @ (posedge clk) begin
		if (rst) begin
			add_res <= 'd0;
			sub_a_b_res <= 'd0;
			sub_b_a_res <= 'd0;
			max_res <= 'd0;
			nop_res <= 'd0;
		end else begin
			for(unit_id = 0; unit_id < DOTW; unit_id = unit_id + 1) begin
				nop_res[unit_id*ACCW+:ACCW] 	<= add_sub_in_act[unit_id*ACCW+:ACCW];
				add_res[unit_id*ACCW+:ACCW] 	<= add_sub_in_act[unit_id*ACCW+:ACCW] + add_sub_in_vrf[unit_id*ACCW+:ACCW];
				sub_a_b_res[unit_id*ACCW+:ACCW] <= add_sub_in_act[unit_id*ACCW+:ACCW] - add_sub_in_vrf[unit_id*ACCW+:ACCW];
				sub_b_a_res[unit_id*ACCW+:ACCW] <= add_sub_in_vrf[unit_id*ACCW+:ACCW] - add_sub_in_act[unit_id*ACCW+:ACCW];
				max_res[unit_id*ACCW+:ACCW] 	<= (add_sub_in_act[unit_id*ACCW+:ACCW] > add_sub_in_vrf[unit_id*ACCW+:ACCW])?
					add_sub_in_act[unit_id*ACCW+:ACCW]: add_sub_in_vrf[unit_id*ACCW+:ACCW];
			end
			add_sub_out_valid <= add_sub_valid;
			add_sub_out_inst <= add_sub_inst;
		end
	end

	// Choosing add/sub output
	reg [ACCW*DOTW-1:0] add_sub_out_data;
	always @ (*) begin
		case (`mfu_uinst_add_op(add_sub_out_inst))
			ADDSUB_OP_ADD: 		add_sub_out_data <= add_res;
			ADDSUB_OP_A_SUB_B: 	add_sub_out_data <= sub_a_b_res;
			ADDSUB_OP_B_SUB_A: 	add_sub_out_data <= sub_b_a_res;
			ADDSUB_OP_MAX: 		add_sub_out_data <= max_res;
			default: 			add_sub_out_data <= nop_res;
		endcase
	end


	/**************************/
	/** Multiplication Units **/
	/**************************/
	wire [ACCW*DOTW-1:0] vrf1_rd_data, vrf1_wr_data;
	wire vrf1_wr_en;
	wire [VRFAW-1:0] vrf1_wr_addr, vrf1_rd_addr;
	
	// VRF1 instantiation
	ram #(
		.ID 		(VRF1_ID), 
		.DW 		(ACCW*DOTW), 
		.AW 		(VRFAW), 
		.DEPTH 		(VRFD),
		.MODULE_ID 	("mfu-vrf")
	) vrf1 (
		.wr_en 		(vrf1_wr_en), 
		.wr_addr 	(vrf1_wr_addr),
		.wr_data 	(vrf1_wr_data),
		.rd_addr 	(vrf1_rd_addr),
		.rd_data 	(vrf1_rd_data),
		.clk 		(clk), 
		.rst 		(rst)
	);
	assign vrf1_wr_en 	= i_vrf_wr_en && (i_vrf_wr_id & (1<<(2*VRF1_ID)));
	assign vrf1_wr_addr = (i_vrf_wr_id[2*VRF1_ID+1] == 1'b0)? i_vrf0_wr_addr : i_vrf1_wr_addr;
	assign vrf1_wr_data = i_vrf_wr_data;
	assign vrf1_rd_addr = `mfu_uinst_vrf1_addr(vrf1_rd_inst);

	// Pipeline from VRF1 to multipliers
	wire mult_valid, mult_out_valid;
	wire [IW-1:0] mult_inst, mult_out_inst;
	wire [ACCW*DOTW-1:0] mult_in_add, mult_in_vrf, mult_out_add;
	pipeline_interconnect # (
		.DATAW 		(IW+1+(2*ACCW*DOTW)),
		.LATENCY 	(VRF1_TO_MULTS_LATENCY)
	) vrf1_to_multipliers_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({add_sub_out_valid, add_sub_out_inst, add_sub_out_data, vrf1_rd_data}),
		.o_pipe_out ({mult_valid, mult_inst, mult_in_add, mult_in_vrf})
	);

	pipeline_interconnect # (
		.DATAW 		(IW+1+(ACCW*DOTW)),
		.LATENCY 	(MULT_LATENCY)
	) mult_pipe (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	({mult_valid, mult_inst, mult_in_add}),
		.o_pipe_out ({mult_out_valid, mult_out_inst, mult_out_add})
	);

	// Instantiate multipliers
	wire [ACCW*DOTW-1:0] sim_mult_res, mult_res;
	wire [2*ACCW*DOTW-1:0] untruncated_mult_res;
	genvar mult_id;
	generate
		for(mult_id = 0; mult_id < DOTW; mult_id = mult_id + 1) begin: gen_mult
			if(SIM_FLAG) begin
				assign sim_mult_res[mult_id*ACCW+:ACCW] = mult_in_add[mult_id*ACCW+:ACCW] * mult_in_vrf[mult_id*ACCW+:ACCW];
				pipeline_interconnect # (
					.DATAW 		(ACCW),
					.LATENCY 	(MULT_LATENCY)
				) sim_mult_pipe (
					.clk 		(clk),
					.rst 		(rst),
					.i_pipe_in 	(sim_mult_res[mult_id*ACCW+:ACCW]),
					.o_pipe_out (mult_res[mult_id*ACCW+:ACCW])
				);
			end else begin
				nx_axbs #(
					.SIZE_A 	(ACCW),
					.SIZE_B 	(ACCW)
				) prime_mult (
					.clk 		(clk),
					.din_a 		(mult_in_add[mult_id*ACCW+:ACCW]),
					.din_b 		(mult_in_vrf[mult_id*ACCW+:ACCW]),
					.dout 		(untruncated_mult_res[mult_id*2*ACCW+:2*ACCW])
				);
				assign mult_res[mult_id*ACCW+:ACCW] = untruncated_mult_res[mult_id*2*ACCW+:ACCW];
			end 
		end
	endgenerate

	// Choosing add/sub output
	reg [ACCW*DOTW-1:0] mult_out_data;
	always @ (*) begin
		case (`mfu_uinst_mul_op(mult_out_inst))
			MUL_OP_MUL: 	mult_out_data <= mult_res;
			default: 		mult_out_data <= mult_out_add;
		endcase
	end

	// Pipeline from multipliers to oFIFO
	wire ofifo_valid [0:DOTW-1];
	wire [ACCW*DOTW-1:0] ofifo_data;
	pipeline_interconnect # (
		.DATAW 		(ACCW*DOTW),
		.LATENCY 	(MULT_TO_OFIFO_LATENCY)
	) mult_to_ofifo_data (
		.clk 		(clk),
		.rst 		(rst),
		.i_pipe_in 	(mult_out_data),
		.o_pipe_out (ofifo_data)
	);

	star_interconnect # (
		.END_POINTS(DOTW),
		.DATAW(1),
		.LATENCY(MULT_TO_OFIFO_LATENCY)
	) mult_to_ofifo_valid (
		.clk(clk),
		.rst(rst),
		.i_star_in(mult_out_valid),
		.o_star_out(ofifo_valid)
	);


	/*****************/
	/** Output FIFO **/
	/*****************/
	wire [DOTW-1:0] data_ofifo_rd_ok;
	wire [DOTW-1:0] data_ofifo_rd_en;
	wire [ACCW*DOTW-1:0] data_ofifo_rd_data;
	
	genvar kk;
	generate
	for(kk = 0; kk < DOTW; kk = kk + 1) begin: generate_mfu_ofifos
		fifo #(
			.ID 		(2), 
			.DW 		(ACCW), 
			.AW 		($clog2(QDEPTH)), 
			.DEPTH 		(QDEPTH)
		) data_ofifo (
			.wr_en 		(ofifo_valid[kk]),
			.wr_data 	(ofifo_data[ACCW*(kk+1)-1:ACCW*kk]),
			.rd_ok 		(data_ofifo_rd_ok[kk]),
			.rd_en 		(data_ofifo_rd_en[kk]),
			.rd_data 	(data_ofifo_rd_data[ACCW*(kk+1)-1:ACCW*kk]),
			.clk 		(clk), 
			.rst 		(rst)
		);
	end
	endgenerate

	assign o_data_rd_rdy      = data_ofifo_rd_ok;
	assign o_data_rd_dout     = data_ofifo_rd_data;
	assign data_ofifo_rd_en   = i_data_rd_en;	
	

	/******************/
	/** Credit Logic **/
	/******************/
	always @ (posedge clk) begin
		if (rst) begin
			credit <= 0;
		end else begin
			case({inst_ififo_rd_en && (`mfu_uinst_tag(inst_ififo_rd_data) != {(NTAGW){1'b1}}), ofifo_valid[0]})
				2'b01: credit <= (CREDITW+1)'(credit - 1'b1);
				2'b10: credit <= (CREDITW+1)'(credit + 1'b1);
				default: credit <= credit;
			endcase
		end
	end


`ifdef DISPLAY_MFU
    always @(posedge clk) begin
        if(r_tag_update_en) begin
        	$display("[%0t][MFU TAG] tag_update: %d", $time, current_tag+1);
        end

        if(data_ififo_rd_en) begin
        	$display("[%0t][MFU-IN] data_ififo: %d", $time, data_ififo_rd_data);
        end

        if(act_out_valid) begin
        	$display("[%0t][MFU-ACT] act_out: %d", $time, activation_out);
        end

        if(add_sub_out_valid) begin
        	$display("[%0t][MFU-ADD] add_out: %d", $time, add_sub_out_data);
        end

        if(ofifo_valid[0]) begin
        	$display("[%0t][MFU-MULT] mult_out: %d", $time, ofifo_data);
        end
    end
`endif
endmodule
