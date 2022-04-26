module prime_dsp_tensor_int8 # (
	parameter TILE_ID = 99,
	parameter DPE_ID = 99,
	parameter DSP_CASCADE = "cascade_disabled"
)(
	input  clk,
	input  clr,
	input  ena,
	input  [95:0] data_in,
	input  load_buf_sel,
	input  load_bb_one,
	input  load_bb_two,
	input  [1:0] feed_sel,
	input  zero_en,
	input  [87:0] cascade_weight_in,
	output [87:0] cascade_weight_out,
	input  [95:0] cascade_data_in,
	output [95:0] cascade_data_out,
	output [36:0] result_h,
	output [37:0] result_l
);

reg [87:0] r_bb_one [0:2];
reg [87:0] r_bb_two [0:2];
reg [95:0] r_data_in; 
reg [24:0] r_dot_out [0:2];
reg [24:0] r_acc_out [0:2];
reg [95:0] r_cascade_data_in;

reg [87:0] dot_in [0:2];

reg signed [15:0] mult_out0 [0:2];
reg signed [15:0] mult_out1 [0:2];
reg signed [15:0] mult_out2 [0:2];
reg signed [15:0] mult_out3 [0:2];
reg signed [15:0] mult_out4 [0:2];
reg signed [15:0] mult_out5 [0:2];
reg signed [15:0] mult_out6 [0:2];
reg signed [15:0] mult_out7 [0:2];
reg signed [15:0] mult_out8 [0:2];
reg signed [15:0] mult_out9 [0:2];

reg r_load_bb_one, r_load_bb_two, r_load_buf_sel;
always @ (posedge clk) begin
	if (clr) begin
		r_load_bb_one <= 0;
		r_load_bb_two <= 0;
		r_load_buf_sel <= 0;
	end else begin
		r_load_bb_one <= load_bb_one;
		r_load_bb_two <= load_bb_two;
		r_load_buf_sel <= load_buf_sel;
	end
end

integer i;
always @ (*) begin
	for (i=0; i<3; i=i+1) begin
		dot_in[i] <= (r_load_buf_sel)? r_bb_two[i]: r_bb_one[i];
		mult_out0[i] <= (signed'(r_data_in[7:0])   * signed'(dot_in[i][7:0]));
		mult_out1[i] <= (signed'(r_data_in[15:8])  * signed'(dot_in[i][15:8]));
		mult_out2[i] <= (signed'(r_data_in[23:16]) * signed'(dot_in[i][23:16]));
		mult_out3[i] <= (signed'(r_data_in[31:24]) * signed'(dot_in[i][31:24]));
		mult_out4[i] <= (signed'(r_data_in[39:32]) * signed'(dot_in[i][39:32]));
		mult_out5[i] <= (signed'(r_data_in[47:40]) * signed'(dot_in[i][47:40]));
		mult_out6[i] <= (signed'(r_data_in[55:48]) * signed'(dot_in[i][55:48]));
		mult_out7[i] <= (signed'(r_data_in[63:56]) * signed'(dot_in[i][63:56]));
		mult_out8[i] <= (signed'(r_data_in[71:64]) * signed'(dot_in[i][71:64]));
		mult_out9[i] <= (signed'(r_data_in[79:72]) * signed'(dot_in[i][79:72]));
	end
end

always @ (posedge clk) begin
	if (clr) begin
		for(i=0; i<3; i=i+1) begin
			r_bb_one[i] <= 0;
			r_bb_two[i] <= 0;
			r_dot_out[i] <= 0;
			r_acc_out[i] <= 0;
		end	
		r_data_in <= 0;
		r_cascade_data_in <= 0;
	end else begin
		// Data input register
		r_data_in <= data_in;
		r_cascade_data_in <= cascade_data_in;

		// Ping-pong buffers
		if(r_load_bb_one) begin
			r_bb_one[0] <= (feed_sel == 2'b00)? data_in[87:0]: cascade_weight_in[87:0];
			r_bb_one[1] <= r_bb_one[0];
			r_bb_one[2] <= r_bb_one[1];
		end
		if(r_load_bb_two) begin
			r_bb_two[0] <= (feed_sel == 2'b00)? data_in[87:0]: cascade_weight_in[87:0];
			r_bb_two[1] <= r_bb_two[0];
			r_bb_two[2] <= r_bb_two[1];
		end

		// Dot product
		for(i=0; i<3; i=i+1) begin
			r_dot_out[i] <= mult_out0[i] + mult_out1[i] + mult_out2[i] + mult_out3[i] + mult_out4[i] + 
					mult_out5[i] + mult_out6[i] + mult_out7[i] + mult_out8[i] + mult_out9[i];
			r_acc_out[i] <= (DSP_CASCADE == "cascade_enabled")? r_dot_out[i] + $signed(r_cascade_data_in[32*i+:25]): r_dot_out[i];
		end
	end
end 

assign cascade_weight_out = (r_bb_one[2] & {(88){r_load_bb_one}}) ^ (r_bb_two[2] & {(88){r_load_bb_two}});
assign cascade_data_out = {{(7){r_acc_out[2][24]}}, r_acc_out[2], {(7){r_acc_out[1][24]}}, r_acc_out[1], {(7){r_acc_out[0][24]}}, r_acc_out[0]};
assign result_l = {(38){~zero_en}} & {r_acc_out[1][12:0], r_acc_out[0]};
assign result_h = {(37){~zero_en}} & {r_acc_out[2], r_acc_out[1][24:13]};

`ifdef DISPLAY_MVU
    always @(posedge clk) begin
    	if(TILE_ID == 0 && DPE_ID == 0) begin
	    	if(r_load_bb_one && ena) begin
	    		$display("[%0t][%s][DPE] r_data_in: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(data_in[7:0]),
		            $signed(data_in[15:8]),
		            $signed(data_in[23:16]),
		            $signed(data_in[31:24]),
		            $signed(data_in[39:32]),
		            $signed(data_in[47:40]),
		            $signed(data_in[55:48]),
		            $signed(data_in[63:56]),
		            $signed(data_in[71:64]),
		            $signed(data_in[79:72])
		        );
		        $display("[%0t][%s][DPE] bb_one[0]: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(cascade_weight_in[7:0]),
		            $signed(cascade_weight_in[15:8]),
		            $signed(cascade_weight_in[23:16]),
		            $signed(cascade_weight_in[31:24]),
		            $signed(cascade_weight_in[39:32]),
		            $signed(cascade_weight_in[47:40]),
		            $signed(cascade_weight_in[55:48]),
		            $signed(cascade_weight_in[63:56]),
		            $signed(cascade_weight_in[71:64]),
		            $signed(cascade_weight_in[79:72])
		        );
		        $display("[%0t][%s][DPE] bb_one[1]: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(r_bb_one[0][7:0]),
		            $signed(r_bb_one[0][15:8]),
		            $signed(r_bb_one[0][23:16]),
		            $signed(r_bb_one[0][31:24]),
		            $signed(r_bb_one[0][39:32]),
		            $signed(r_bb_one[0][47:40]),
		            $signed(r_bb_one[0][55:48]),
		            $signed(r_bb_one[0][63:56]),
		            $signed(r_bb_one[0][71:64]),
		            $signed(r_bb_one[0][79:72])
		        );
		        $display("[%0t][%s][DPE] bb_one[2]: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(r_bb_one[1][7:0]),
		            $signed(r_bb_one[1][15:8]),
		            $signed(r_bb_one[1][23:16]),
		            $signed(r_bb_one[1][31:24]),
		            $signed(r_bb_one[1][39:32]),
		            $signed(r_bb_one[1][47:40]),
		            $signed(r_bb_one[1][55:48]),
		            $signed(r_bb_one[1][63:56]),
		            $signed(r_bb_one[1][71:64]),
		            $signed(r_bb_one[1][79:72])
		        );
		        $display("[%0t][%s][DPE] dout: %d %d %d", 
		            $time, `__FILE__,
		            $signed(r_dot_out[0]),
		            $signed(r_dot_out[1]),
		            $signed(r_dot_out[2])
		        );
	    	end

	    	if(r_load_bb_two && ena) begin
	    		$display("[%0t][%s][DPE] r_data_in: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(data_in[7:0]),
		            $signed(data_in[15:8]),
		            $signed(data_in[23:16]),
		            $signed(data_in[31:24]),
		            $signed(data_in[39:32]),
		            $signed(data_in[47:40]),
		            $signed(data_in[55:48]),
		            $signed(data_in[63:56]),
		            $signed(data_in[71:64]),
		            $signed(data_in[79:72])
		        );
		        $display("[%0t][%s][DPE] bb_two[0]: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(cascade_weight_in[7:0]),
		            $signed(cascade_weight_in[15:8]),
		            $signed(cascade_weight_in[23:16]),
		            $signed(cascade_weight_in[31:24]),
		            $signed(cascade_weight_in[39:32]),
		            $signed(cascade_weight_in[47:40]),
		            $signed(cascade_weight_in[55:48]),
		            $signed(cascade_weight_in[63:56]),
		            $signed(cascade_weight_in[71:64]),
		            $signed(cascade_weight_in[79:72])
		        );
		        $display("[%0t][%s][DPE] bb_two[1]: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(r_bb_two[0][7:0]),
		            $signed(r_bb_two[0][15:8]),
		            $signed(r_bb_two[0][23:16]),
		            $signed(r_bb_two[0][31:24]),
		            $signed(r_bb_two[0][39:32]),
		            $signed(r_bb_two[0][47:40]),
		            $signed(r_bb_two[0][55:48]),
		            $signed(r_bb_two[0][63:56]),
		            $signed(r_bb_two[0][71:64]),
		            $signed(r_bb_two[0][79:72])
		        );
		        $display("[%0t][%s][DPE] bb_two[2]: %d %d %d %d %d %d %d %d %d %d", 
		            $time, `__FILE__,
		            $signed(r_bb_two[1][7:0]),
		            $signed(r_bb_two[1][15:8]),
		            $signed(r_bb_two[1][23:16]),
		            $signed(r_bb_two[1][31:24]),
		            $signed(r_bb_two[1][39:32]),
		            $signed(r_bb_two[1][47:40]),
		            $signed(r_bb_two[1][55:48]),
		            $signed(r_bb_two[1][63:56]),
		            $signed(r_bb_two[1][71:64]),
		            $signed(r_bb_two[1][79:72])
		        );
		        $display("[%0t][%s][DPE] dout: %d %d %d", 
		            $time, `__FILE__,
		            $signed(r_dot_out[0]),
		            $signed(r_dot_out[1]),
		            $signed(r_dot_out[2])
		        );
	    	end
	    end
    end
`endif

endmodule
