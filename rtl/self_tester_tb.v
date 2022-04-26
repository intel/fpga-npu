`timescale 1 ps / 1 ps

module self_tester_tb; 
  reg clk, reset; 
  wire [2:0] status; 
  wire [31:0] count;
  wire [31:0] perf_counter;
  wire done;
    
self_tester_shim uut (
	.clk(clk),
	.reset(reset),
	.o_test_status(status),
	.o_result_count(count),
	.o_perf_counter(perf_counter),
	.o_test_done(done)
);
    
initial begin
	clk = 0; 
	reset = 0; 
end 
    
always  
	#5 clk = !clk; 
    
initial begin
	reset = 1; #20
	reset = 0; 
end
    
endmodule
