
// This module implements a simple pipelined interconnect from a source to a single sink.
(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name DONT_MERGE_REGISTER ON" *) module pipeline_interconnect # (
	parameter DATAW = 32,
	parameter LATENCY = 2
) (
	input 				clk,
	input 				rst,
	input  [DATAW-1:0] 	i_pipe_in,
	output [DATAW-1:0] 	o_pipe_out
);

reg [DATAW-1:0] pipeline [0:LATENCY-1];

integer t;
always @ (posedge clk) begin
	// Set the input to the first pipeline stage
	pipeline[0] <= i_pipe_in;

	// Progress the pipeline
	for (t = 1; t < LATENCY; t = t + 1) begin
		pipeline[t] <= pipeline[t-1];
	end
end

// Hook up outputs
assign o_pipe_out = pipeline[LATENCY-1];

endmodule