`include "npu.vh"

module inst_ram # (
	parameter MODULE_ID = "",
	parameter OUTREG = "CLOCK0",
	parameter ID = 0,
	parameter ID_UNITS = (ID%10) + 8'h30,
	parameter ID_TENS = (ID/10 == 0)? "": ((ID/10)%10) + 8'h30,
	parameter ID_HUNDREDS = (ID/100 == 0)? "": (ID/100) + 8'h30,
	parameter DW = 32,
	parameter DEPTH = 512,
	parameter AW = 9,
	parameter RTL_DIR = `RTL_DIR,
	parameter TARGET_FPGA = `TARGET_FPGA
)(
	input           wr_en, 
	input  [AW-1:0] wr_addr, 
	input  [AW-1:0] rd_addr,
	input  [DW-1:0] wr_data,
	output [DW-1:0] rd_data,
	input 			clk, 
	input 			rst
);

wire [DW-1:0] sub_wire0;
assign rd_data = sub_wire0[DW-1:0];


//localparam RAM_SRC = {RTL_DIR, "mif_files/top_sched.mif"};      

altera_syncram  altera_syncram_component (
	.address_a 		(wr_addr),
	.address_b 		(rd_addr),
	.clock0 			(clk),
	.data_a 			(wr_data),
	.wren_a 			(wr_en),
	.q_b 				(sub_wire0),
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
	.data_b 			({(DW){1'b1}}),
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
/*`ifdef DEPLOY
	altera_syncram_component.init_file = RAM_SRC,
`endif*/
	altera_syncram_component.enable_ecc  = "FALSE",
	altera_syncram_component.intended_device_family  = TARGET_FPGA,
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
	altera_syncram_component.width_a  = DW,
	altera_syncram_component.width_b  = DW,
	altera_syncram_component.width_byteena_a  = 1;


// Debug
//   always @ (posedge clk) begin
//      if(wr_en) 
//          $display("[%0t][%s] wr ram%d[%d] = %x(%d,%d,%d,%d)", 
//          $time, `__FILE__, ID, wr_addr, wr_data, wr_data[7:0], wr_data[15:8],
//          wr_data[23:16], wr_data[31:24]);
//   end

endmodule

