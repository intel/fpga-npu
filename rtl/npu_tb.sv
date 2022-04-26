`timescale 1 ns / 1 ps 
`include "npu.vh"

module npu_tb ();

// Testbench Parameters
localparam CLK_PERIOD = 4;
// NPU Parameters
localparam EW = `EW;
localparam ACCW = `ACCW;
localparam DOTW = `DOTW;
localparam NTILE = `NTILE;
localparam NDPE = `NDPE;
localparam NMFU = `NMFU;
localparam NVRF = `NVRF;
localparam NMRF = `NMRF;
localparam VRFD = `VRFD;
localparam VRFAW = `VRFAW; 
localparam MRFD = `MRFD;
localparam MRFAW = `MRFAW;
localparam NSIZE = `NSIZE;
localparam NSIZEW = `NSIZEW;
localparam NTAG = `NTAG;
localparam NTAGW = `NTAGW;
localparam DOT_PER_DSP = `DOT_PER_DSP;
localparam PRIME_DOTW = `PRIME_DOTW;
localparam NUM_DSP = `NUM_DSP;
localparam NUM_ACCUM = `NUM_ACCUM;
localparam ACCIDW = `ACCIDW;
localparam VRFIDW = `VRFIDW;
localparam MRFIDW = `MRFIDW;
localparam MIW_MVU = `MIW_MVU;
localparam UIW_MVU = `UIW_MVU;
localparam MIW_EVRF = `MIW_EVRF;
localparam UIW_EVRF = `UIW_EVRF;
localparam MIW_MFU = `MIW_MFU;
localparam UIW_MFU = `UIW_MFU;
localparam MIW_LD = `MIW_LD;
localparam UIW_LD = `UIW_LD;
localparam MICW = `MICW;
localparam QDEPTH = `QDEPTH;
localparam WB_LMT = `WB_LMT;
localparam WB_LMTW = `WB_LMTW;
localparam MULT_LATENCY = `MULT_LATENCY;
localparam DPE_PIPELINE = `DPE_PIPELINE;
localparam SIM_FLAG = `SIM_FLAG;
localparam TILES_THRESHOLD = `TILES_THRESHOLD;
localparam DPES_THRESHOLD = `DPES_THRESHOLD;
localparam RTL_DIR = `RTL_DIR;
localparam TARGET_FPGA = `TARGET_FPGA;
localparam FILLED_MRFD = `FILLED_MRFD;
localparam OUTPUT_BUFFER_SIZE = `OUTPUT_BUFFER_SIZE;
localparam INST_DEPTH = `INST_DEPTH;
localparam INST_ADDRW = `INST_ADDRW;

logic clk;
logic rst;
// Signals for MRF load
logic [MRFAW-1:0] mrf_wr_addr;
logic [EW*DOTW-1:0] mrf_wr_data;
logic mrf_wr_en;
logic [MRFIDW-1:0] mrf_wr_id;
// Signals for instructions load
logic inst_wr_en;
logic inst_wr_rdy;
logic [INST_ADDRW-1:0] inst_wr_addr;
logic [MICW-1:0] inst_wr_data;
// Signals for input write
logic input_wr_en;
logic input_wr_rdy0, input_wr_rdy1;
logic [EW*DOTW-1:0] input_wr_data;
// Signals for output read
logic output_rd_en0, output_rd_en1;
logic output_rd_rdy0, output_rd_rdy1;
logic [EW*DOTW-1:0] output_rd_data0, output_rd_data1;
// Signals for control
logic [2:0] mode;
logic start;
logic [31:0] pc_offset;
logic done;


// Generate a 250MHz clock
initial clk = 1'b1;
always #(CLK_PERIOD/2) clk = ~clk;

// Instantiate the design under test
npu dut(
    .clk					(clk),
    .rst					(rst),

    .i_mrf_wr_addr			(mrf_wr_addr), 
    .i_mrf_wr_data			(mrf_wr_data), 
    .i_mrf_wr_en			(mrf_wr_id), 

    .i_minst_chain_wr_en	(inst_wr_en),
    .i_minst_chain_wr_addr	(inst_wr_addr),
    .i_minst_chain_wr_din	(inst_wr_data),

    .i_ld_in_wr_en 			(input_wr_en),
    .o_ld_in_wr_rdy 		(input_wr_rdy0),
    .i_ld_in_wr_din 		(input_wr_data),
    .i_ld_in_wr_en1			(input_wr_en),
    .o_ld_in_wr_rdy1 		(input_wr_rdy1),
    .i_ld_in_wr_din1 		(input_wr_data),

    .i_ld_out_rd_en 		(output_rd_en0),
    .o_ld_out_rd_rdy 		(output_rd_rdy0),
    .o_ld_out_rd_dout 		(output_rd_data0),
    .i_ld_out_rd_en1 		(output_rd_en1),
    .o_ld_out_rd_rdy1		(output_rd_rdy1),
    .o_ld_out_rd_dout1 		(output_rd_data1),

    .diag_mode 				(mode),
    .i_start 				(start),
    .pc_start_offset 		(pc_offset),
    .o_done 				(done) 					
);


integer temp;
logic [8000:0] line;
integer tile_id, dpe_id, lane_id, mrf_file_id, mrf_id, mrf_line;
integer mrf_file [0:NUM_DSP-1];
string mrf_hundreds, mrf_tens, mrf_units, mrf_bank;

integer input_file, num_inputs, input_id, input_addr;
integer inst_file, num_inst, inst_id, inst_addr;
integer output_file, num_output, output_id, output_addr;
logic [EW*DOTW-1:0] golden_output;
integer cycles;
logic success;

integer init_done, mrf_done, input_done, inst_done, sim_done;

initial begin
	rst = 1;
	start = 0;
	pc_offset = 0;
	mode = 4;
	mrf_wr_id = 0;
	#(5*CLK_PERIOD);
	rst = 0;
	#(30*CLK_PERIOD);
	init_done = $fopen("init_done", "w");
	$fwrite(init_done, "init done\n");
	$fclose(init_done);

	// Step 1: Load MRF values
	/*mrf_wr_id = 0;
	for (tile_id = 0; tile_id < NTILE; tile_id = tile_id + 1) begin
		for (dpe_id = 0; dpe_id < NDPE; dpe_id = dpe_id + 1) begin
			mrf_id = (tile_id * NDPE) + dpe_id;
			$display("Loading MRF %d", mrf_id);
			for (mrf_file_id = 0; mrf_file_id < NUM_DSP; mrf_file_id = mrf_file_id + 1) begin
				// Open the MIFs for a specific MRF
				mrf_hundreds.itoa(mrf_id / 100);
				mrf_tens.itoa((mrf_id % 100) / 10);
				mrf_units.itoa(mrf_id % 10);
				mrf_bank.itoa(mrf_file_id);
				mrf_file[mrf_file_id] = $fopen({"mif_files/mvu-mrf", mrf_hundreds, mrf_tens, mrf_units, "_", mrf_bank, ".mif"}, "r");
				
				// Read and ignore the MIF header
				temp = $fgets(line, mrf_file[mrf_file_id]);
				temp = $fgets(line, mrf_file[mrf_file_id]);
				temp = $fgets(line, mrf_file[mrf_file_id]);
				temp = $fgets(line, mrf_file[mrf_file_id]);
				temp = $fgets(line, mrf_file[mrf_file_id]);
				temp = $fgets(line, mrf_file[mrf_file_id]);
			end

			// Read the MRF address and data
			for (mrf_line = 0; mrf_line < FILLED_MRFD; mrf_line = mrf_line + 1) begin
				for (mrf_file_id = 0; mrf_file_id < NUM_DSP; mrf_file_id = mrf_file_id + 1) begin
					temp = $fscanf(mrf_file[mrf_file_id], "%d: %b;\n", mrf_wr_addr, mrf_wr_data[(EW*DOTW)-((mrf_file_id+1)*EW*PRIME_DOTW) +: EW*PRIME_DOTW]);
				end
				mrf_wr_id = (tile_id * NDPE) + dpe_id + 1;
				#(CLK_PERIOD);
			end
		end
	end
	$display("Contents of %d MRFs were loaded successfully!", mrf_id+1);
	mrf_wr_id = 0;
	mrf_done = $fopen("mrf_done", "w");
	$fwrite(mrf_done, "MRF loaded\n");
	$fclose(mrf_done);
	#(CLK_PERIOD);*/

	// Step 2: Load Inputs
	input_file = $fopen({"mif_files/input.mif"}, "r");
	temp = $fscanf(input_file, "DEPTH = %d;\n", num_inputs);
	temp = $fgets(line, input_file);
	temp = $fgets(line, input_file);
	temp = $fgets(line, input_file);
	temp = $fgets(line, input_file);
	temp = $fgets(line, input_file);
	input_id = 0;
	// Feed in input vectors as long as the NPU is ready to accept new inputs
	while(input_id < num_inputs) begin
		if(input_wr_rdy0 && input_wr_rdy1) begin
			temp = $fscanf(input_file, "%d: %x;\n", input_addr, input_wr_data);
			input_wr_en = 1;
			#(CLK_PERIOD);
			input_id = input_id + 1;
		end else begin
			input_wr_en = 0;
			#(CLK_PERIOD);
		end
	end
	$display("%d input vectors were loaded successfully!", input_id);
	input_wr_en = 0;
	input_done = $fopen("input_done", "w");
	$fwrite(input_done, "Inputs loaded\n");
	$fclose(input_done);
	#(CLK_PERIOD);

	// Step 3: Load Instructions
	inst_file = $fopen({"mif_files/top_sched.mif"}, "r");
	temp = $fscanf(inst_file, "DEPTH = %d;\n", num_inst);
	temp = $fgets(line, inst_file);
	temp = $fgets(line, inst_file);
	temp = $fgets(line, inst_file);
	temp = $fgets(line, inst_file);
	temp = $fgets(line, inst_file);
	inst_id = 0;
	// Feed in instructions as long as the NPU is ready to accept new inputs
	while(inst_id < num_inst) begin
		temp = $fscanf(inst_file, "%d: %b;\n", inst_wr_addr, inst_wr_data);
		$display("%d: %b", inst_wr_addr, inst_wr_data);
		inst_wr_en = 1;
		#(CLK_PERIOD);
		inst_id = inst_id + 1;
	end
	$display("%d instructions were loaded successfully!", inst_id);
	inst_wr_en = 0;
	inst_done = $fopen("inst_done", "w");
	$fwrite(inst_done, "Instructions loaded\n");
	$fclose(inst_done);
	#(CLK_PERIOD);

	// Step 4: Prepare for simulation
	output_file = $fopen({"mif_files/output.mif"}, "r");
	temp = $fscanf(output_file, "DEPTH = %d;\n", num_output);
	temp = $fgets(line, output_file);
	temp = $fgets(line, output_file);
	temp = $fgets(line, output_file);
	temp = $fgets(line, output_file);
	temp = $fgets(line, output_file);
	output_id = 0;
	cycles = 0;
	pc_offset = 0;
	mode = 4;
	success = 1;
	#(CLK_PERIOD);

	// Step 5: Run the simulation and listen for outputs
	start = 1;
	#(CLK_PERIOD);
	cycles = cycles + 1;

	start = 0;
	while (output_id < num_output) begin
		if(output_rd_rdy0 && output_rd_rdy1) begin
			temp = $fscanf(output_file, "%d: %x;\n", output_addr, golden_output);
			if((golden_output == output_rd_data0) && (golden_output == output_rd_data1)) begin
				success = success & 1'b1;
				$display("Output %d is matching", output_id);
				//$display("Expected: %x", golden_output);
				//$display("Got: %x", output_rd_data0);
			end else begin
				success = success & 1'b0;
				$display("Output %d is not matching", output_id);
				$display("Expected: %x", golden_output);
				$display("Got: %x", output_rd_data0);
			end
			output_rd_en0 = 1;
			output_rd_en1 = 1;
			output_id = output_id + 1;
		end else begin
			output_rd_en0 = 0;
			output_rd_en1 = 0;
		end
		#(CLK_PERIOD);
		cycles = cycles + 1;
	end

	sim_done = $fopen("sim_done", "w");
	if (success)begin
		$display("****************************************************************************************");
		$display("SUCCESS! ALL OUTPUTS ARE MATCHING! Runtime = %d cycle(s)", cycles);
		$display("****************************************************************************************");
		$fwrite(sim_done, "PASS\n");
	end else begin
		$display("****************************************************************************************");
		$display("FAILURE! SOME OUTPUTS ARE NOT MATCHING! Runtime = %d cycle(s)", cycles);
		$display("****************************************************************************************");
		$fwrite(sim_done, "FAIL\n");
	end
	$fwrite(sim_done, "%0d", cycles);
	$fclose(sim_done);

	//$stop(0);
	$finish;
end

endmodule
