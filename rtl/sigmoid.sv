`include "npu.vh"

module sigmoid # (
	parameter DW = 32,
	parameter IF = 19,
	parameter OF = 19,
	parameter SAMPLES = 512,
	parameter AW = $clog2(SAMPLES),
	parameter RTL_DIR = `RTL_DIR,
	parameter TARGET_FPGA = `TARGET_FPGA
) (
	input  clk,
	input  rst,
	input  [DW-1:0] x,
	output [DW-1:0] result
);

reg [AW-1:0] index;
reg [DW-1:0] abs_x;
reg is_neg, is_neg_reg, is_big;
reg [DW-1:0] res;
wire [DW-1:0] lookup;

always @ (posedge clk) begin
	if(rst) begin
		abs_x <= 0;
		is_neg <= 0;
		is_big <= 0;
		res <= 0;
		index <= 0;
		//lookup <= 0;
	end else begin
		//Cycle 1: Get abs x
		if(x[DW-1]) begin
			abs_x <= -x;
			is_neg <= 1'b1;
		end else begin
			abs_x <= x;
			is_neg <= 1'b0;
		end
		
		//Cycle 2: Get index & do comparisons
		if(abs_x > 4194304) begin
			is_big <= 1'b1;
		end else begin
			is_big <= 1'b0;
		end
		index <= AW'(abs_x[DW-6:DW-16] + abs_x[DW-17]); 
		//lookup <= sigmoid_LUT[index];
		is_neg_reg <= is_neg;
		
		//Cycle 3: Choose output
		case({is_neg_reg, is_big})
			2'b01: res <= {{(DW-OF-1){1'b0}}, 1'b1, {(OF){1'b0}}};
			2'b11: res <= {(DW){1'b0}};
			2'b00: res <= lookup;
			2'b10: res <= {{(DW-OF-1){1'b0}}, 1'b1, {(OF){1'b0}}} - lookup;
			default: res <= 0;
		endcase
	end
end

/*reg [AW-1:0] index_2;
reg [DW-1:0] abs_x_2;
reg is_neg_2, is_neg_reg_2, is_big_2;
reg [DW-1:0] res_2;
wire [DW-1:0] lookup_2;

always @ (posedge clk) begin
	if(rst) begin
		abs_x_2 <= 0;
		is_neg_2 <= 0;
		is_big_2 <= 0;
		res_2 <= 0;
		index_2 <= 0;
		//lookup <= 0;
	end else begin
		//Cycle 1: Get abs x
		if(x_2[DW-1]) begin
			abs_x_2 <= -x_2;
			is_neg_2 <= 1'b1;
		end else begin
			abs_x_2 <= x_2;
			is_neg_2 <= 1'b0;
		end
		
		//Cycle 2: Get index & do comparisons
		if(abs_x_2 > 4194304) begin
			is_big_2 <= 1'b1;
		end else begin
			is_big_2 <= 1'b0;
		end
		index_2 <= abs_x_2[DW-6:DW-16] + abs_x_2[DW-17]; 
		//lookup <= sigmoid_LUT[index];
		is_neg_reg_2 <= is_neg_2;
		
		//Cycle 3: Choose output
		case({is_neg_reg_2, is_big_2})
			2'b01: res_2 <= {{(DW-OF-1){1'b0}}, 1'b1, {(OF){1'b0}}};
			2'b11: res_2 <= {(DW){1'b0}};
			2'b00: res_2 <= lookup_2;
			2'b10: res_2 <= {{(DW-OF-1){1'b0}}, 1'b1, {(OF){1'b0}}} - lookup_2;
			default: res_2 <= 0;
		endcase
	end
end*/

assign result = res;
/*assign result_2 = res_2;

altera_syncram  altera_syncram_component (
                .address_a (index),
                .address_b (index_2),
                .clock0 (clk),
                .data_a ({(DW){1'b1}}),
                .data_b ({(DW){1'b1}}),
                .wren_a (1'b0),
                .wren_b (1'b0),
                .q_a (lookup),
                .q_b (lookup_2),
                .aclr0 (),
                .aclr1 (),
                .address2_a (1'b1),
                .address2_b (1'b1),
                .addressstall_a (1'b0),
                .addressstall_b (1'b0),
                .byteena_a (1'b1),
                .byteena_b (1'b1),
                .clock1 (1'b1),
                .clocken0 (1'b1),
                .clocken1 (1'b1),
                .clocken2 (1'b1),
                .clocken3 (1'b1),
                .eccencbypass (1'b0),
                .eccencparity (8'b0),
                .eccstatus (),
                .rden_a (1'b1),
                .rden_b (1'b1),
                .sclr (1'b0)
);
defparam
	altera_syncram_component.address_reg_b  = "CLOCK0",
	altera_syncram_component.clock_enable_input_a  = "BYPASS",
	altera_syncram_component.clock_enable_input_b  = "BYPASS",
	altera_syncram_component.clock_enable_output_a  = "BYPASS",
	altera_syncram_component.clock_enable_output_b  = "BYPASS",
	altera_syncram_component.indata_reg_b  = "CLOCK0",
	altera_syncram_component.init_file = "sigmoid.mif",
	altera_syncram_component.intended_device_family  = "Stratix 10",
	altera_syncram_component.lpm_type  = "altera_syncram",
	altera_syncram_component.numwords_a  = SAMPLES,
	altera_syncram_component.numwords_b  = SAMPLES,
	altera_syncram_component.operation_mode  = "BIDIR_DUAL_PORT",
	altera_syncram_component.outdata_aclr_a  = "NONE",
	altera_syncram_component.outdata_aclr_b  = "NONE",
	altera_syncram_component.outdata_sclr_a  = "NONE",
	altera_syncram_component.outdata_sclr_b  = "NONE",
	altera_syncram_component.outdata_reg_a  = "CLOCK0",
	altera_syncram_component.outdata_reg_b  = "CLOCK0",
	altera_syncram_component.enable_force_to_zero  = "TRUE",
	altera_syncram_component.power_up_uninitialized  = "FALSE",
	altera_syncram_component.ram_block_type  = "M20K",
	altera_syncram_component.widthad_a  = AW,
	altera_syncram_component.widthad_b  = AW,
	altera_syncram_component.width_a  = DW,
	altera_syncram_component.width_b  = DW,
	altera_syncram_component.width_byteena_a  = 1,
	altera_syncram_component.width_byteena_b  = 1;*/

altera_syncram  altera_syncram_component (
	 .address_a (index),
	 .clock0 (clk),
	 .q_a (lookup),
	 .aclr0 (1'b0),
	 .aclr1 (1'b0),
	 .address2_a (1'b1),
	 .address2_b (1'b1),
	 .address_b (1'b1),
	 .addressstall_a (1'b0),
	 .addressstall_b (1'b0),
	 .byteena_a (1'b1),
	 .byteena_b (1'b1),
	 .clock1 (1'b1),
	 .clocken0 (1'b1),
	 .clocken1 (1'b1),
	 .clocken2 (1'b1),
	 .clocken3 (1'b1),
	 .data_a ({(DW){1'b1}}),
	 .data_b (1'b1),
	 .eccencbypass (1'b0),
	 .eccencparity (8'b0),
	 .eccstatus ( ),
	 .q_b ( ),
	 .rden_a (1'b1),
	 .rden_b (1'b1),
	 .sclr (1'b0),
	 .wren_a (1'b0),
	 .wren_b (1'b0)
);
defparam
	altera_syncram_component.address_aclr_a  = "NONE",
	altera_syncram_component.clock_enable_input_a  = "BYPASS",
	altera_syncram_component.clock_enable_output_a  = "BYPASS",
	altera_syncram_component.init_file = {RTL_DIR, "sigmoid.mif"},
	altera_syncram_component.intended_device_family  = TARGET_FPGA,
	altera_syncram_component.lpm_hint  = "ENABLE_RUNTIME_MOD=NO",
	altera_syncram_component.lpm_type  = "altera_syncram",
	altera_syncram_component.numwords_a  = SAMPLES,
	altera_syncram_component.operation_mode  = "ROM",
	altera_syncram_component.outdata_aclr_a  = "NONE",
	altera_syncram_component.outdata_sclr_a  = "NONE",
	altera_syncram_component.outdata_reg_a  = "CLOCK0",
	altera_syncram_component.ram_block_type  = "M20K",
	altera_syncram_component.enable_force_to_zero  = "FALSE",
	altera_syncram_component.widthad_a  = AW,
	altera_syncram_component.width_a  = DW,
	altera_syncram_component.width_byteena_a  = 1;
	
endmodule
