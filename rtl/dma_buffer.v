`timescale 1ns / 1ps

module dma_buffer # (
	parameter WIDTH = 512,
	parameter DEPTH = 8192,
	parameter ADDRW = $clog2(DEPTH),
	parameter BYENW = WIDTH / 8
)(
	input  clk,
	input  ren,
	input  [ADDRW-1:0] raddr,
	output [WIDTH-1:0] rdata,
	input  wen,
	input  [ADDRW-1:0] waddr,
	input  [BYENW-1:0] wben,
	input  [WIDTH-1: 0] wdata
);

reg [WIDTH-1:0] readdata;
wire [WIDTH-1:0] readdata_ram;
wire wren;

always @(posedge clk) begin
	//if (ren) begin
		readdata <= readdata_ram;
	//end
end

assign rdata = readdata;

altera_syncram altera_syncram_component (
	.address_a (waddr),
	.address_b (raddr),
	.byteena_a (1'b1),
	.clock0 (clk),
	.data_a (wdata),
	.wren_a (wen),
	.q_b (readdata_ram),
	.aclr0 (1'b0),
	.aclr1 (1'b0),
	.address2_a (1'b1),
	.address2_b (1'b1),
	.addressstall_a (1'b0),
	.addressstall_b (1'b0),
	.byteena_b (1'b1),
	.clock1 (1'b1),
	.clocken0 (1'b1),
	.clocken1 (1'b1),
	.clocken2 (1'b1),
	.clocken3 (1'b1),
	.data_b ({512{1'b1}}),
	.eccencbypass (1'b0),
	.eccencparity (8'b0),
	.eccstatus (),
	.q_a (),
	.rden_a (1'b1),
	.rden_b (1'b1),
	.sclr (1'b0),
	.wren_b (1'b0)
);
defparam
	altera_syncram_component.address_aclr_b  = "NONE",
	altera_syncram_component.address_reg_b  = "CLOCK0",
	altera_syncram_component.byte_size  = 8,
	altera_syncram_component.clock_enable_input_a  = "BYPASS",
	altera_syncram_component.clock_enable_input_b  = "BYPASS",
	altera_syncram_component.clock_enable_output_b  = "BYPASS",
	altera_syncram_component.intended_device_family  = "Stratix 10",
	altera_syncram_component.lpm_type  = "altera_syncram",
	altera_syncram_component.numwords_a  = DEPTH,
	altera_syncram_component.numwords_b  = DEPTH,
	altera_syncram_component.operation_mode  = "DUAL_PORT",
	altera_syncram_component.outdata_aclr_b  = "NONE",
	altera_syncram_component.outdata_sclr_b  = "NONE",
	altera_syncram_component.outdata_reg_b  = "UNREGISTERED",
	altera_syncram_component.power_up_uninitialized  = "FALSE",
	altera_syncram_component.read_during_write_mode_mixed_ports  = "DONT_CARE",
	altera_syncram_component.widthad_a  = ADDRW,
	altera_syncram_component.widthad_b  = ADDRW,
	altera_syncram_component.width_a  = WIDTH,
	altera_syncram_component.width_b  = WIDTH,
	altera_syncram_component.width_byteena_a  = 1;

endmodule