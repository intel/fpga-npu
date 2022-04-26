`include "npu.vh"

module evrf # (
    parameter VRF0_ID  = 0,
    // data width
    parameter EW       = `EW,    // element width
    parameter ACCW     = `ACCW,  // element width
    parameter DOTW     = `DOTW,  // # elemtns in vector
    // # functional units
    parameter NTILE    = `NTILE, // # mvu tiles
    parameter NDPE     = `NDPE,  // # dpes
    parameter NMFU     = `NMFU,  // # mfus
    parameter NVRF     = `NVRF,  // # vrfs
    parameter NMRF     = `NMRF,  // # mrfs
	// VRF & MRF
    parameter VRFD     = `VRFD,  // VRF depth
    parameter VRFAW    = `VRFAW, // VRF address width
    parameter MRFD     = `MRFD,  // MRF depth
    parameter MRFAW    = `MRFAW, // MRF address width
    // instructions
    parameter NSIZE    = `NSIZE,
    parameter NSIZEW   = `NSIZEW,
    parameter NTAG     = `NTAG,
    parameter NTAGW    = `NTAGW,
    parameter IW       = `UIW_EVRF,
    // others
    parameter QDEPTH   = `QDEPTH,  // queue depth
    parameter CREDITW  = $clog2(QDEPTH),
    parameter WB_LMT   = `WB_LMT,  // write-back limit
    parameter WB_LMTW  = `WB_LMTW,
	parameter BRAM_RD_LATENCY = `BRAM_RD_LATENCY

) (
    // vrf write
    input                  i_vrf_wr_en, 
    input  [2*NVRF-1:0]    i_vrf_wr_id,  
    input  [VRFAW-1:0]     i_vrf0_wr_addr,
    input  [VRFAW-1:0]     i_vrf1_wr_addr,
    input  [ACCW*DOTW-1:0] i_vrf_wr_data, 
    // pipeline datapath
    input  [DOTW-1:0]      i_data_wr_en,
    output [DOTW-1:0] 	   o_data_wr_rdy,
    input  [ACCW*DOTW-1:0] i_data_wr_din,
    input  [DOTW-1:0]      i_data_rd_en,
    output [DOTW-1:0]      o_data_rd_rdy,
    output [ACCW*DOTW-1:0] o_data_rd_dout,
    // instruction
    input                  i_inst_wr_en,
    output                 o_inst_wr_rdy,
    input  [VRFAW-1:0]     i_vrf_rd_addr,  
    input  [1:0]           i_src_sel,
    input  [NTAGW-1:0]     i_tag,
    // from ld
    input                  i_tag_update_en,
    // clk & rst
    input                  clk, rst
);

    localparam FROM_MVU = 0;
    localparam FROM_VRF = 1;
    localparam FLUSH_MVU = 2;
    localparam ISSUE_CTRL_LATENCY = 4,
               VRF_TO_OFIFO_LATENCY = 2;

    /********************************/
    /** Hazard Detection Mechanism **/
    /********************************/
    reg [NTAGW-1:0] current_tag;
    reg r_tag_update_en;
	 wire [IW-1:0] inst_ififo_wr_data, inst_ififo_rd_data;
    always @(posedge clk) begin
        if (rst) begin
            current_tag <= 'd0;
            r_tag_update_en <= 1'b0;
        end else begin
            current_tag <= (r_tag_update_en)? NTAGW'(current_tag + 1'b1) : current_tag;
            r_tag_update_en <= i_tag_update_en;
        end
    end


    /****************************/
    /** eVRF instruction queue **/
    /****************************/
    wire          inst_ififo_wr_ok, inst_ififo_wr_en;
    wire          inst_ififo_rd_ok, inst_ififo_rd_en;
    
    // FIFO instantiation
    inst_fifo #(
    	.ID      (0), 
        .DW      (IW), 
        .AW      ($clog2(QDEPTH)), 
        .DEPTH   (QDEPTH),
        .MODULE  ("evrf")
    ) inst_ififo (
        .wr_ok   (inst_ififo_wr_ok),
        .wr_en   (inst_ififo_wr_en),
        .wr_data (inst_ififo_wr_data),
        .rd_ok   (inst_ififo_rd_ok),
        .rd_en   (inst_ififo_rd_en),
        .rd_data (inst_ififo_rd_data),
        .clk     (clk), 
        .rst     (rst),
        .current_tag (current_tag)
    );

    // FIFO connections
    assign o_inst_wr_rdy      = inst_ififo_wr_ok;
    assign inst_ififo_wr_en   = i_inst_wr_en;
    assign inst_ififo_wr_data = {i_vrf_rd_addr,i_src_sel,i_tag};


    /*********************/
    /** eVRF data queue **/
    /*********************/
    wire [DOTW-1:0] data_ififo_wr_ok, data_ififo_rd_ok;
    wire [DOTW-1:0] data_ififo_wr_en;
    wire data_ififo_rd_en;
    wire [ACCW*DOTW-1:0] data_ififo_wr_data, data_ififo_rd_data;
    wire data_rd_en [0:DOTW-1];
    wire [CREDITW-1:0] data_usedw [0:DOTW-1];

    // FIFO instantiation
    genvar ff;
    generate
        for(ff = 0; ff < DOTW; ff = ff + 1) begin: gen_evrf_ififos
            fifo #(
                .ID      (0), 
                .DW      (ACCW), 
                .AW      ($clog2(QDEPTH)), 
                .DEPTH   (QDEPTH)
            ) data_ififo (
                .wr_ok   (data_ififo_wr_ok[ff]),
                .wr_en   (data_ififo_wr_en[ff]),
                .wr_data (data_ififo_wr_data[ACCW*(ff+1)-1:ACCW*ff]),
                .rd_ok   (data_ififo_rd_ok[ff]),
                .rd_en   (data_rd_en[ff]),
                .rd_data (data_ififo_rd_data[ACCW*(ff+1)-1:ACCW*ff]),
                .clk     (clk), 
                .rst     (rst),
                .usedw 	 (data_usedw[ff])
            );
        end
    endgenerate
    
    // FIFO connections
    assign o_data_wr_rdy      = data_ififo_wr_ok;
    assign data_ififo_wr_en   = i_data_wr_en;
    assign data_ififo_wr_data = i_data_wr_din;


    /*******************/
    /** Issuing Logic **/
    /*******************/
    reg  [CREDITW-1:0] credit, in_flight;
    wire issue_ok;
    wire inst_rd_en;
    wire [IW-1:0] inst_rd_data;

    star_interconnect # (
        .END_POINTS(DOTW),
        .DATAW(1),
        .LATENCY(ISSUE_CTRL_LATENCY)
    ) issue_data_pipe (
        .clk(clk),
        .rst(rst),
        .i_star_in(data_ififo_rd_en),
        .o_star_out(data_rd_en)
    );

    pipeline_interconnect # (
        .DATAW(IW+1),
        .LATENCY(ISSUE_CTRL_LATENCY)
    ) issue_inst_pipe (
        .clk(clk),
        .rst(rst),
        .i_pipe_in({inst_ififo_rd_en, inst_ififo_rd_data}),
        .o_pipe_out({inst_rd_en, inst_rd_data})
    );

    always @ (posedge clk) begin
        if (rst) begin
            in_flight <= 'd0;
        end else begin
            case({data_ififo_rd_en, data_rd_en[0]})
                2'b01: in_flight <= CREDITW'(in_flight - 1'b1);
                2'b10: in_flight <= CREDITW'(in_flight + 1'b1);
                default: in_flight <= in_flight;
            endcase
        end
    end

    assign issue_ok = (credit < QDEPTH);
    assign inst_ififo_rd_en =
        inst_ififo_rd_ok &&
        (((((`evrf_uinst_src_sel(inst_ififo_rd_data) == FROM_MVU) || (`evrf_uinst_src_sel(inst_ififo_rd_data) == FLUSH_MVU)) && (data_usedw[0] > in_flight)) ||
         (`evrf_uinst_src_sel(inst_ififo_rd_data) == FROM_VRF))) &&
        issue_ok;
    assign data_ififo_rd_en =
         inst_ififo_rd_ok &&
         (((`evrf_uinst_src_sel(inst_ififo_rd_data) == FROM_MVU) || (`evrf_uinst_src_sel(inst_ififo_rd_data) == FLUSH_MVU)) && (data_usedw[0] > in_flight)) &&
         issue_ok;      


    /************************/
    /** Inst & data to VRF **/
    /************************/
    wire [IW-1:0] vrf_inst;
    wire [ACCW*DOTW-1:0] mvu_data;
    wire vrf_valid;

    pipeline_interconnect # (
        .DATAW      (IW+(ACCW*DOTW)+1),
        .LATENCY    (BRAM_RD_LATENCY)
    ) inst_to_vrf_pipe (
        .clk        (clk),
        .rst        (rst),
        .i_pipe_in  ({inst_rd_en, inst_rd_data, data_ififo_rd_data}),
        .o_pipe_out ({vrf_valid, vrf_inst, mvu_data})
    );


    /**********************/
    /** The external VRF **/
    /**********************/
    wire [ACCW*DOTW-1:0] vrf_rd_data;
    wire vrf_wr_en;
    wire [VRFAW-1:0] vrf_wr_addr;
    assign vrf_wr_en = i_vrf_wr_en && (i_vrf_wr_id & (1<<(2*VRF0_ID)));
    assign vrf_wr_addr = (i_vrf_wr_id[2*VRF0_ID+1] == 1'b0)? i_vrf0_wr_addr : i_vrf1_wr_addr;

    // VRF instantiation
    ram #(
        .ID(VRF0_ID), 
        .DW(ACCW*DOTW), 
        .AW(VRFAW), 
        .DEPTH(VRFD)
    ) vrf (
      .wr_en   (vrf_wr_en), 
      .wr_addr (vrf_wr_addr),
      .wr_data (i_vrf_wr_data),
      .rd_addr (`evrf_uinst_vrf_addr(inst_rd_data)),
      .rd_data (vrf_rd_data),
      .clk(clk), 
      .rst(rst)
    );

    // Choose eVRF output and align instruction
    reg [ACCW*DOTW-1:0] evrf_out_data;
    reg evrf_out_valid;
    always @ (posedge clk) begin
        if (rst) begin
            evrf_out_data <= 'd0;
            evrf_out_valid <= 1'b0;
        end else begin
            evrf_out_data <= (`evrf_uinst_src_sel(vrf_inst) == FROM_VRF)? vrf_rd_data: mvu_data;
            evrf_out_valid <= vrf_valid && ~(`evrf_uinst_src_sel(vrf_inst) == FLUSH_MVU);
        end
    end

    // Pipeline to oFIFO
    wire ofifo_valid [0:DOTW-1];
    wire [ACCW*DOTW-1:0] ofifo_data;
    pipeline_interconnect # (
        .DATAW      (ACCW*DOTW),
        .LATENCY    (VRF_TO_OFIFO_LATENCY)
    ) vrf_to_ofifo_data (
        .clk        (clk),
        .rst        (rst),
        .i_pipe_in  (evrf_out_data),
        .o_pipe_out (ofifo_data)
    );

    star_interconnect # (
        .END_POINTS(DOTW),
        .DATAW(1),
        .LATENCY(VRF_TO_OFIFO_LATENCY)
    ) vrf_to_ofifo_valid (
        .clk(clk),
        .rst(rst),
        .i_star_in(evrf_out_valid),
        .o_star_out(ofifo_valid)
    );


    /*****************/
    /** Output FIFO **/
    /*****************/
    wire [DOTW-1:0] data_ofifo_rd_ok;
    wire [DOTW-1:0] data_ofifo_rd_en;
    wire [ACCW*DOTW-1:0] data_ofifo_rd_data;
    
    genvar kk;
    generate
    for(kk = 0; kk < DOTW; kk = kk + 1) begin: generate_mfu_ofifos
        fifo #(
            .ID         (2), 
            .DW         (ACCW), 
            .AW         ($clog2(QDEPTH)), 
            .DEPTH      (QDEPTH)
        ) data_ofifo (
            .wr_en      (ofifo_valid[kk]),
            .wr_data    (ofifo_data[ACCW*(kk+1)-1:ACCW*kk]),
            .rd_ok      (data_ofifo_rd_ok[kk]),
            .rd_en      (data_ofifo_rd_en[kk]),
            .rd_data    (data_ofifo_rd_data[ACCW*(kk+1)-1:ACCW*kk]),
            .clk        (clk), 
            .rst        (rst)
        );
    end
    endgenerate

    assign o_data_rd_rdy      = data_ofifo_rd_ok;
    assign o_data_rd_dout     = data_ofifo_rd_data;
    assign data_ofifo_rd_en   = i_data_rd_en;


    /******************/
    /** Credit Logic **/
    /******************/
    always @ (posedge clk) begin
        if (rst) begin
            credit <= 0;
        end else begin
            case({inst_ififo_rd_en && (`evrf_uinst_tag(inst_ififo_rd_data) != {(NTAGW){1'b1}}), ofifo_valid[0]})
                2'b01: credit <= (CREDITW+1)'(credit - 1'b1);
                2'b10: credit <= (CREDITW+1)'(credit + 1'b1);
                default: credit <= credit;
            endcase
        end
    end

endmodule
