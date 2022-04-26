module test_rom # (
	parameter DEPTH = 2,
	parameter DATAW = 16,
	parameter ADDRW = $clog2(DEPTH),
	parameter MIF_FILE = "/nfs/site/home/aboutros/self_tester/test_vectors.mif"
)(
    input [ADDRW-1:0] address,
    input clock,
    output [DATAW-1:0] q
);

    wire [DATAW-1:0] sub_wire0;
    assign q = sub_wire0[DATAW-1:0];

    altera_syncram  altera_syncram_component (
                .address_a (address),
                .clock0 (clock),
                .q_a (sub_wire0),
                .aclr0 (1'b0),
                .aclr1 (1'b0),
                .address2_a (1'b1),
                .address2_b (1'b1),
                .address_b (1'b1),
                .addressstall_a (1'b0),
                .addressstall_b (1'b0),
                .byteena_a (1'b1),
                .byteena_b (1'b1),
                .clock1 (1'b1),
                .clocken0 (1'b1),
                .clocken1 (1'b1),
                .clocken2 (1'b1),
                .clocken3 (1'b1),
                .data_a ({(DATAW){1'b1}}),
                .data_b (1'b1),
                .eccencbypass (1'b0),
                .eccencparity (8'b0),
                .eccstatus ( ),
                .q_b ( ),
                .rden_a (1'b1),
                .rden_b (1'b1),
                .sclr (1'b0),
                .wren_a (1'b0),
                .wren_b (1'b0));
    defparam
        altera_syncram_component.address_aclr_a  = "NONE",
        altera_syncram_component.clock_enable_input_a  = "BYPASS",
        altera_syncram_component.clock_enable_output_a  = "BYPASS",
        altera_syncram_component.init_file = MIF_FILE,
        altera_syncram_component.intended_device_family  = "Stratix 10",
        altera_syncram_component.lpm_type  = "altera_syncram",
        altera_syncram_component.numwords_a  = DEPTH,
        altera_syncram_component.operation_mode  = "ROM",
        altera_syncram_component.outdata_aclr_a  = "NONE",
        altera_syncram_component.outdata_sclr_a  = "NONE",
        altera_syncram_component.outdata_reg_a  = "CLOCK0",
        altera_syncram_component.ram_block_type  = "M20K",
        altera_syncram_component.enable_force_to_zero  = "TRUE",
        altera_syncram_component.widthad_a  = ADDRW,
        altera_syncram_component.width_a  = DATAW,
        altera_syncram_component.width_byteena_a  = 1;

endmodule