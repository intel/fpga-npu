
// This module implements a star-shapped interconnect from a source to multiple sinks with distinct pipelining registers.
(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name DONT_MERGE_REGISTER ON" *) module star_interconnect # (
	parameter END_POINTS = 4,
	parameter DATAW = 32,
	parameter LATENCY = 2
) (
	input 				clk,
	input 				rst,
	input  [DATAW-1:0] 	i_star_in,
	output [DATAW-1:0] 	o_star_out [0:END_POINTS-1]
);

reg [DATAW-1:0] pipeline [0:LATENCY-1][0:END_POINTS-1];

integer t, d;
always @ (posedge clk) begin
	if (rst) begin
		// Reset the first stage of the pipeline
		for (d = 0; d < END_POINTS; d = d + 1) begin
			pipeline[0][d] <= 'd0;
		end
	end else begin
		// Set the input to the first pipeline stage
		for (d = 0; d < END_POINTS; d = d + 1) begin
			pipeline[0][d] <= i_star_in;
		end

		// Progress the pipeline
		for (d = 0; d < END_POINTS; d = d + 1) begin
			for (t = 1; t < LATENCY; t = t + 1) begin
				pipeline[t][d] <= pipeline[t-1][d];
			end
		end
	end
end

// Hook up outputs
assign o_star_out = pipeline[LATENCY-1];

endmodule