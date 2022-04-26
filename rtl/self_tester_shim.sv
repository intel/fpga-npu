`include "npu.vh"

module self_tester_shim # (
	parameter NUM_INPUTS = `NUM_INPUTS,
	parameter INPUT_WIDTH = `DOTW * `EW,
	parameter INPUT_MIF_FILE = {`RTL_DIR, "mif_files/input.mif"},
	parameter INPUT_ADDRW = $clog2(NUM_INPUTS),
	parameter NUM_OUTPUTS = `NUM_OUTPUTS,
	parameter OUTPUT_WIDTH = `DOTW * `ACCW,
	parameter OUTPUT_LOWER_MIF_FILE = {`RTL_DIR, "mif_files/output_lower.mif"},
	parameter OUTPUT_UPPER_MIF_FILE = {`RTL_DIR, "mif_files/output_upper.mif"},
	parameter OUTPUT_ADDRW = $clog2(NUM_OUTPUTS),
	parameter OR_TREE_PADDING = (2 ** $clog2(OUTPUT_WIDTH))-OUTPUT_WIDTH,
	parameter OUTPUT_BUFFER_SIZE = `OUTPUT_BUFFER_SIZE,
	parameter INST_DEPTH = `INST_DEPTH,
	parameter INST_ADDRW = `INST_ADDRW,
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
	parameter NSIZE    = `NSIZE,
	parameter NSIZEW   = `NSIZEW,
	parameter NTAG     = `NTAG,
	parameter NTAGW    = `NTAGW,
	parameter DOT_PER_DSP = `DOT_PER_DSP,
	parameter PRIME_DOTW = `PRIME_DOTW,
	parameter NUM_DSP  = `NUM_DSP,
	parameter NUM_ACCUM= `NUM_ACCUM,
	parameter ACCIDW   = `ACCIDW,
	parameter VRFIDW   = `VRFIDW,
	parameter MIW_MVU  = `MIW_MVU,
	parameter UIW_MVU  = `UIW_MVU,
	parameter MIW_EVRF = `MIW_EVRF,
	parameter UIW_EVRF = `UIW_EVRF,
	parameter MIW_MFU  = `MIW_MFU,
	parameter UIW_MFU  = `UIW_MFU,
	parameter MIW_LD   = `MIW_LD,
	parameter UIW_LD   = `UIW_LD,
	parameter MICW     = `MICW
)(
	input clk,
	input reset,
	output [2:0] o_test_status,
	output [31:0] o_result_count,
	output [31:0] o_perf_counter,
	output o_test_done
);

localparam [2:0] TEST_IDLE = 3'b000, TEST_RUNNING = 3'b001, TEST_SUCCESS = 3'b010, TEST_FAIL = 3'b100;

reg [INPUT_ADDRW:0] addr_test_vectors;					
reg [OUTPUT_ADDRW:0] addr_golden_outputs;
wire [INPUT_WIDTH-1:0] data_test_vectors;
wire [(OUTPUT_WIDTH/2)-1:0] data_golden_outputs_lower, data_golden_outputs_upper;

reg dut_data_wen, r_dut_data_wen;
wire dut_data_rdy;
wire [$clog2(OUTPUT_BUFFER_SIZE)-1:0] dut_usedw;

reg dut_res_ren, r_dut_res_ren, rr_dut_res_ren;
wire [OUTPUT_WIDTH-1:0] dut_res, dut_res0, dut_res1;
reg [OUTPUT_WIDTH-1:0] r_golden_res;
reg [OUTPUT_WIDTH-1:0] r_dut_res, rr_dut_res;
reg compare_res, compare_en;

reg mismatch;
reg [2:0] test_status, output_test_status;
reg test_done;
reg [31:0] perf_counter;
wire npu_done;
reg done_flag;

reg rst, r_rst;
always @ (posedge clk) begin
	if(reset)begin
		rst <= 1'b1;
		r_rst <= 1'b1;
		output_test_status <= 2'b00;
		test_done <= 1'b0;
		perf_counter <= 32'd0;
	end else begin
		if(test_status == TEST_SUCCESS && done_flag) begin
			rst <= 1'b1;
			output_test_status <= test_status;
			test_done <= 1'b1;
		end else if (test_status == TEST_FAIL && done_flag) begin
			rst <= 1'b1;
			output_test_status <= test_status;
			test_done <= 1'b1;
		end else begin
			rst <= 1'b0;
			perf_counter <= (~test_done)? perf_counter + 1'b1: perf_counter;
		end
		r_rst <= rst;
	end
end

always @ (posedge clk) begin
	if(rst)begin
		done_flag <= 1'b0;
	end else begin
		if(npu_done) begin
			done_flag <= 1'b1;
		end else begin
			done_flag <= done_flag;
		end
	end
end
			
// ROM storing test vectors
test_rom # (
	.DEPTH(NUM_INPUTS),
	.DATAW(INPUT_WIDTH), 
	.MIF_FILE(INPUT_MIF_FILE)
) test_vectors_rom (
	.clock(clk),
	.address(addr_test_vectors[INPUT_ADDRW-1:0]), 
	.q(data_test_vectors)
);

// ROM storing golden outputs
test_rom # (
	.DEPTH(NUM_OUTPUTS),
	.DATAW(OUTPUT_WIDTH/2),
	.MIF_FILE(OUTPUT_LOWER_MIF_FILE)
) golden_outputs_lower_rom (
	.clock(clk),
	.address(addr_golden_outputs[OUTPUT_ADDRW-1:0]), 
	.q(data_golden_outputs_lower)
);
test_rom # (
	.DEPTH	(NUM_OUTPUTS),
	.DATAW	(OUTPUT_WIDTH/2),
	.MIF_FILE(OUTPUT_UPPER_MIF_FILE)
) golden_outputs_upper_rom (
	.clock(clk),
	.address(addr_golden_outputs[OUTPUT_ADDRW-1:0]), 
	.q(data_golden_outputs_upper)
);

// Reset Pipeline
reg test_rst [0:9];
integer n;
always @ (posedge clk) begin
	if(reset)begin
		for(n = 0; n < 10; n = n + 1) begin
			test_rst[n] <= 0;
		end
	end else begin
		test_rst[0] <= rst;
		for(n = 1; n < 10; n = n + 1) begin
			test_rst[n] <= test_rst[n-1];
		end
	end
end

// Design under test
npu dut (
	.clk(clk),
	.rst(rst),
	.i_start(r_rst),
	.o_done(npu_done),
	.pc_start_offset({(INST_ADDRW){1'b0}}),
	.diag_mode(3'd4),
	// MRF interface
	.i_mrf_wr_addr({($clog2(`MRFD)){1'b0}}), 
	.i_mrf_wr_data({(`EW*`DOTW){1'b0}}), 
	.i_mrf_wr_en(1'b0), 
	.i_mrf_wr_id({(`NTILE*`NDPE){1'b0}}),
	// Instruction interface
	.i_minst_chain_wr_en(1'b0),
	.i_minst_chain_wr_addr({(INST_ADDRW){1'b0}}),
	.i_minst_chain_wr_din({(MICW){1'b0}}),
	// Input interface 0
	.i_ld_in_wr_en(r_dut_data_wen),
	.o_ld_in_wr_rdy(dut_data_rdy),
	.i_ld_in_wr_din(data_test_vectors),
	// Input interface 1
	.i_ld_in_wr_en1(r_dut_data_wen),
	.o_ld_in_wr_rdy1(),
	.i_ld_in_wr_din1(data_test_vectors),
	// Output Interface 0
	.i_ld_out_rd_en(dut_res_ren),
	.o_ld_out_rd_rdy(dut_res_rdy),
	.o_ld_out_rd_dout(dut_res0),
	.o_ld_out_usedw(dut_usedw),
	// Output Interface 1
	.i_ld_out_rd_en1(dut_res_ren),
	.o_ld_out_rd_rdy1(),
	.o_ld_out_rd_dout1(dut_res1),
	// Result Counter
	.o_result_count(o_result_count)
);
assign dut_res = dut_res0 | dut_res1;

// Logic to feed inputs
always @ (posedge clk) begin
	if(test_rst[9])begin
		addr_test_vectors <= 0;
		dut_data_wen <= 1'b0;
	end else begin
		if ((addr_test_vectors < NUM_INPUTS) && dut_data_rdy) begin
			addr_test_vectors = addr_test_vectors + 1'b1;
			dut_data_wen <= 1'b1;
		end else begin
			dut_data_wen <= 1'b0;
		end
		r_dut_data_wen <= dut_data_wen;
	end
end

or_tree #(
	.DW(OR_TREE_PADDING+OUTPUT_WIDTH)
) reduce_tree (
	.clk(clk),
	.rst(test_rst[9]),
	.din({{(OR_TREE_PADDING){1'b0}}, rr_dut_res ^ r_golden_res}),
	.valid_in(rr_dut_res_ren),
	.result(compare_res),
	.valid_out(compare_en)
);

// Logic to read outputs
always @ (posedge clk) begin
	if(test_rst[9])begin
		addr_golden_outputs <= 0;
		dut_res_ren <= 1'b0;
		r_dut_res_ren <= 1'b0;
		rr_dut_res_ren <= 1'b0;
		r_golden_res <= 0;
		r_dut_res <= 0;
		rr_dut_res <= 0;
		test_status <= TEST_IDLE;
		mismatch <= 1'b0;
	end else begin
		if ((addr_golden_outputs < NUM_OUTPUTS) && dut_usedw >= 3) begin
			addr_golden_outputs <= addr_golden_outputs + 1'b1;
			dut_res_ren <= 1'b1;
		end else begin
			dut_res_ren <= 1'b0;
		end
		// Adjusting output delays
		r_dut_res_ren <= dut_res_ren;
		rr_dut_res_ren <= r_dut_res_ren;
		r_dut_res <= dut_res;
		rr_dut_res <= r_dut_res;
		r_golden_res <= {data_golden_outputs_upper, data_golden_outputs_lower};
		
		if(compare_en) begin
			mismatch <= mismatch | compare_res;
		end
		
		// Producing the test status output
		if(test_status == TEST_FAIL) begin
			test_status <= TEST_FAIL;
		end else if (addr_golden_outputs >= NUM_OUTPUTS-1) begin
			test_status <= (mismatch)? TEST_FAIL: TEST_SUCCESS;
		end else begin
			test_status <= TEST_RUNNING;
		end
	end
end

assign o_test_status = output_test_status;
assign o_perf_counter = perf_counter;
assign o_test_done = test_done;

endmodule


module or_tree #(
	parameter DW    = 1024
)(
	input  clk,
	input  rst,
	input  [DW-1:0] din,
	input  valid_in,
	output reg result,
	output reg valid_out
);

	reg [DW/2-1:0] or_reduce;
	reg valid;

	genvar i;
	generate
		if (DW == 1) begin
			always @(posedge clk) begin
				if(rst)begin
					result <= 0;
					valid_out <= 0;
				end else begin
					result <= din;
					valid_out <= valid_in;
				end
			end
		end else if (DW == 2) begin
			always @(posedge clk) begin
				if(rst)begin
					result <= 0;
					valid_out <= 0;
				end else begin
					result <= din[0] | din[1];
					valid_out <= valid_in;
				end
			end
		end else begin
			for (i = 0; i < DW/2; i = i + 1) begin : gen_vectors
				always @(posedge clk) begin
					if(rst)begin
						or_reduce[i] <= 0;
					end else begin
						or_reduce[i] <= din[2*i] | din[(2*i)+1];
					end
				end
			end
			
			always @(posedge clk) begin
				if(rst)begin
					valid <= 0;
				end else begin
					valid <= valid_in;
				end
			end
			
			or_tree #(
				.DW(DW/2)
			) or_reduce_tree (
				.din(or_reduce), 
				.result(result),
				.valid_in(valid),
				.valid_out(valid_out),
				.clk(clk), 
				.rst(rst)
			);
		end
	endgenerate

endmodule