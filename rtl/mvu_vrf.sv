`include "npu.vh"

module mvu_vrf # (
	parameter MODULE_ID = "",
	parameter OUTREG = "CLOCK0",
	parameter ID = 0,
	parameter DW = 32,
	parameter DEPTH = 512,
	parameter AW = 9,
	parameter RTL_DIR = `RTL_DIR,
	parameter TARGET_FPGA = `TARGET_FPGA,
	parameter EW = `EW,
	parameter DEVICE = (TARGET_FPGA == "S10-Prime")? "Stratix 10": TARGET_FPGA,
	parameter PRIME_DOTW = `PRIME_DOTW,
	parameter DOTW = `DOTW,
	parameter NUM_DSP = `NUM_DSP,
	parameter NUM_RAM = (TARGET_FPGA == "S10-Prime")? NUM_DSP: 1,
	parameter RW = DW / NUM_RAM,
	parameter VRFIDW = `VRFIDW,
	parameter MVU_TILE = 0
)(
	input            wr_en, 
	input  [AW-1:0]  wr_addr, 
	input  [AW-1:0]  rd_addr,
	input  [DW-1:0]  wr_data,
	input  [VRFIDW-1:0] rd_id,
	input rd_en,
	output [RW-1:0]  rd_data,
	input 			  clk, 
	input 			  rst
);

wire [RW-1:0] rdata [0:NUM_RAM-1];
reg [VRFIDW-1:0] id [0:1];
reg rd [0:1];

always @ (posedge clk) begin
	if(rst)begin
		id[0] <= 'd0;
		id[1] <= 'd0;
		rd[0] <= 0;
		rd[1] <= 0;
	end else begin
		id[0] <= rd_id;
		id[1] <= id[0];

		rd[0] <= rd_en;
		rd[1] <= rd[0];
	end
end

genvar i;
generate
for(i = 0; i < NUM_RAM; i = i + 1) begin: gen_mvu_vrf_ram
	altera_syncram  altera_syncram_component (
		.address_a 		(wr_addr),
		.address_b 		(rd_addr),
		.clock0 			(clk),
		.data_a 			(wr_data[i*RW +: RW]),
		.wren_a 			(wr_en),
		.q_b 				(rdata[i]),
		.aclr0 			(1'b0),
		.aclr1 			(1'b0),
		.address2_a 	(1'b1),
		.address2_b 	(1'b1),
		.addressstall_a(1'b0),
		.addressstall_b(1'b0),
		.byteena_a 		(1'b1),
		.byteena_b 		(1'b1),
		.clock1 			(1'b1),
		.clocken0 		(1'b1),
		.clocken1 		(1'b1),
		.clocken2 		(1'b1),
		.clocken3 		(1'b1),
		.data_b 			({(RW){1'b1}}),
		.eccencbypass 	(1'b0),
		.eccencparity 	(8'b0),
		.eccstatus 		(),
		.q_a 				(),
		.rden_a 			(1'b1),
		.rden_b 			(1'b1),
		.sclr 			(1'b0),
		.wren_b 			(1'b0)
	);

	defparam
		altera_syncram_component.address_aclr_b  = "NONE",
		altera_syncram_component.address_reg_b  = "CLOCK0",
		altera_syncram_component.clock_enable_input_a  = "BYPASS",
		altera_syncram_component.clock_enable_input_b  = "BYPASS",
		altera_syncram_component.clock_enable_output_b  = "BYPASS",
		altera_syncram_component.enable_ecc  = "FALSE",
		altera_syncram_component.intended_device_family  = DEVICE,
		altera_syncram_component.lpm_type  = "altera_syncram",
		altera_syncram_component.numwords_a  = DEPTH,
		altera_syncram_component.numwords_b  = DEPTH,
		altera_syncram_component.operation_mode  = "DUAL_PORT",
		altera_syncram_component.outdata_aclr_b  = "NONE",
		altera_syncram_component.outdata_sclr_b  = "NONE",
		altera_syncram_component.outdata_reg_b  = OUTREG,
		altera_syncram_component.power_up_uninitialized  = "FALSE",
		altera_syncram_component.ram_block_type  = "M20K",
		altera_syncram_component.read_during_write_mode_mixed_ports  = "DONT_CARE",
		altera_syncram_component.widthad_a  = AW,
		altera_syncram_component.widthad_b  = AW,
		altera_syncram_component.width_a  = RW,
		altera_syncram_component.width_b  = RW,
		altera_syncram_component.width_byteena_a  = 1;
end

endgenerate
	
assign rd_data = rdata[id[1]];


`ifdef DISPLAY_MVU
always @(posedge clk) begin
	if(wr_en && MVU_TILE == 0) begin
		$display("[%0t][MVU-VRF] wr_addr: %d, wr_data: %d %d %d %d %d %d %d %d %d %d", 
			$time, 
			wr_addr,
			$signed(wr_data[7:0]),
			$signed(wr_data[15:8]),
			$signed(wr_data[23:16]),
			$signed(wr_data[31:24]),
			$signed(wr_data[39:32]),
			$signed(wr_data[47:40]),
			$signed(wr_data[55:48]),
			$signed(wr_data[63:56]),
			$signed(wr_data[71:64]),
			$signed(wr_data[79:72]));
	end

	if(rd_en && MVU_TILE == 0) begin
		$display("[%0t][MVU-VRF] rd_addr: %d %b", $time, rd_addr, rd_addr);
	end

	if(rd[1] && MVU_TILE == 0) begin
		$display("[%0t][MVU-VRF] vrf_id: %d, rd_data: %d %d %d %d %d %d %d %d %d %d", 
			$time,
			id[1],
			$signed(rd_data[7:0]),
			$signed(rd_data[15:8]),
			$signed(rd_data[23:16]),
			$signed(rd_data[31:24]),
			$signed(rd_data[39:32]),
			$signed(rd_data[47:40]),
			$signed(rd_data[55:48]),
			$signed(rd_data[63:56]),
			$signed(rd_data[71:64]),
			$signed(rd_data[79:72]));
	end
end
`endif

endmodule