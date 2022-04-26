module altera_syncram   (
                    wren_a,
                    wren_b,
                    rden_a,
                    rden_b,
                    data_a,
                    data_b,
                    address_a,
                    address_b,
                    clock0,
                    clock1,
                    clocken0,
                    clocken1,
                    clocken2,
                    clocken3,
                    aclr0,
                    aclr1,
                    byteena_a,
                    byteena_b,
                    addressstall_a,
                    addressstall_b,
                    q_a,
                    q_b,
                    eccstatus,
                    // Available only from Stratix10 onwards,
                    address2_a,
                    address2_b,
                    eccencparity,
                    eccencbypass,
                    sclr
                    );

// GLOBAL PARAMETER DECLARATION

    // PORT A PARAMETERS
    parameter width_a          = 1;
    parameter widthad_a        = 1;
    parameter widthad2_a       = 1;
    parameter numwords_a       = 0;
    parameter outdata_reg_a    = "UNREGISTERED";
    parameter address_aclr_a   = "NONE";
    parameter outdata_aclr_a   = "NONE";
    parameter width_byteena_a  = 1;

    // PORT B PARAMETERS
    parameter width_b                   = 1;
    parameter widthad_b                 = 1;
    parameter widthad2_b                = 1;
    parameter numwords_b                = 0;
    parameter rdcontrol_reg_b           = "CLOCK1";
    parameter address_reg_b             = "CLOCK1";
    parameter outdata_reg_b             = "UNREGISTERED";
    parameter outdata_aclr_b            = "NONE";
    parameter indata_reg_b              = "CLOCK1";
    parameter byteena_reg_b             = "CLOCK1";
    parameter address_aclr_b            = "NONE";
    parameter width_byteena_b           = 1;

    // Clock Enable Parameters
    parameter clock_enable_input_a  = "NORMAL";
    parameter clock_enable_output_a = "NORMAL";
    parameter clock_enable_input_b  = "NORMAL";
    parameter clock_enable_output_b = "NORMAL";
    parameter clock_enable_core_a = "USE_INPUT_CLKEN";
    parameter clock_enable_core_b = "USE_INPUT_CLKEN";
	
	// Read During Write Paramters
    parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ";
    parameter read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ";
    parameter read_during_write_mode_mixed_ports = "DONT_CARE";
	
    // ECC STATUS RELATED PARAMETERS
    parameter enable_ecc = "FALSE";
    parameter width_eccstatus = 2;
    parameter ecc_pipeline_stage_enabled = "FALSE";

    // NADDER NEW FEATURES
    parameter outdata_sclr_a            = "NONE";
    parameter outdata_sclr_b            = "NONE";
    parameter enable_ecc_encoder_bypass = "FALSE";
    parameter enable_coherent_read      = "FALSE";
    parameter enable_force_to_zero	= "FALSE";
    parameter width_eccencparity        = 8;
    
    // GLOBAL PARAMETERS
    parameter operation_mode                     = "BIDIR_DUAL_PORT";
    parameter byte_size                          = 0; //!! From FD review, to change default to 0, and to be calculated from width / width_byteena if it's non-zero 
    parameter ram_block_type                     = "AUTO";
    parameter init_file                          = "UNUSED";
    parameter init_file_layout                   = "UNUSED";
    parameter maximum_depth                      = 0;
    parameter intended_device_family             = "Arria 10";
    parameter lpm_hint                           = "UNUSED";
    parameter lpm_type                           = "altsyncram";
    parameter implement_in_les                 = "OFF";
    parameter power_up_uninitialized            = "FALSE";
    
// SIMULATION_ONLY_PARAMETERS_BEGIN

    parameter sim_show_memory_data_in_port_b_layout  = "OFF";

// SIMULATION_ONLY_PARAMETERS_END
    
// LOCAL_PARAMETERS_BEGIN

`ifdef ENA_NON_CORRUPT
    parameter enable_non_corrupted_behav =1;
`else
    parameter enable_non_corrupted_behav =0;
`endif

    parameter is_lutram = ((ram_block_type == "LUTRAM") || (ram_block_type == "MLAB"))? 1 : 0;
    
    parameter is_bidir_and_wrcontrol_addb_clk0 =    ((((operation_mode == "QUAD_PORT") || (operation_mode == "BIDIR_DUAL_PORT")) && (address_reg_b == "CLOCK0"))? 
                                                    1 : 0);

    parameter is_bidir_and_wrcontrol_addb_clk1 =    ((((operation_mode == "QUAD_PORT") || (operation_mode == "BIDIR_DUAL_PORT")) && (address_reg_b == "CLOCK1"))? 
                                                    1 : 0);

    parameter dual_port_addreg_b_clk0 = (((operation_mode == "DUAL_PORT") && (address_reg_b == "CLOCK0"))? 1: 0);

    parameter dual_port_addreg_b_clk1 = (((operation_mode == "DUAL_PORT") && (address_reg_b == "CLOCK1"))? 1: 0);

    parameter i_byte_size_tmp = (width_byteena_a > 1)? width_a / width_byteena_a : 8;
    
    parameter i_lutram_read = (((is_lutram == 1) && (read_during_write_mode_port_a == "DONT_CARE")) ||
                                ((is_lutram == 1) && (outdata_reg_a == "UNREGISTERED") && (operation_mode == "SINGLE_PORT")))? 1 : 0;

   parameter enable_mem_data_b_reading =  (sim_show_memory_data_in_port_b_layout == "ON") && ((operation_mode == "QUAD_PORT") || (operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "DUAL_PORT")) ? 1 : 0;
   
   parameter wrcontrol_wraddress_reg_b = ((operation_mode == "QUAD_PORT") || (operation_mode == "BIDIR_DUAL_PORT"))? address_reg_b : "CLOCK1";
   
   //!! Local Parameters
   //!!
   //!! Stratix V LUTRAM writes at positive clock edge
   //!! Consider SII RAM compiled for SIII
   //!! M512, M4K, and Titan LUTRAM write at negative clock edge
   //!! AUTO is assumed as BRAM
   parameter is_write_on_positive_edge = 1; //TBR

   parameter lutram_single_port_fast_read = ((is_lutram == 1) && ((read_during_write_mode_port_a == "DONT_CARE") || (outdata_reg_a == "UNREGISTERED")) && (operation_mode == "SINGLE_PORT")) ? 1 : 0;
            
   parameter lutram_dual_port_fast_read = ((is_lutram == 1) && ((read_during_write_mode_mixed_ports == "NEW_DATA") || (read_during_write_mode_mixed_ports == "DONT_CARE") || (read_during_write_mode_mixed_ports == "CONSTRAINED_DONT_CARE") || ((read_during_write_mode_mixed_ports == "OLD_DATA") && (outdata_reg_b == "UNREGISTERED")))) ? 1 : 0;
            
   parameter block_ram_output_unreg =  ((is_lutram != 1) && (outdata_reg_a != "CLOCK0") && (outdata_reg_a != "CLOCK1")) ? 1 : 0;

   parameter s3_address_aclr_b =  ((is_lutram != 1) && (outdata_reg_b != "CLOCK0") && (outdata_reg_b != "CLOCK1")) ? 1 : 0;

   parameter is_rom = (operation_mode == "ROM") ? 1 : 0;
    
   parameter i_address_aclr_family_b = ((operation_mode != "DUAL_PORT") || ((is_lutram == 1) && (operation_mode == "DUAL_PORT") && (read_during_write_mode_mixed_ports == "OLD_DATA"))) ? 1 : 0;

// LOCAL_PARAMETERS_END

// INPUT PORT DECLARATION

    input  wren_a; // Port A write/read enable input
    input  wren_b; // Port B write enable input
    input  rden_a; // Port A read enable input
    input  rden_b; // Port B read enable input
    input  [width_a-1:0] data_a; // Port A data input
    input  [width_b-1:0] data_b; // Port B data input
    input  [widthad_a-1:0] address_a; // Port A address input
    input  [widthad_b-1:0] address_b; // Port B address input

    // clock inputs on both ports and here are their usage
    // Port A -- 1. all input registers must be clocked by clock0.
    //           2. output register can be clocked by either clock0, clock1 or none.
    // Port B -- 1. all input registered must be clocked by either clock0 or clock1.
    //           2. output register can be clocked by either clock0, clock1 or none.
    input  clock0;
    input  clock1;

    // clock enable inputs and here are their usage
    // clocken0 -- can only be used for enabling clock0.
    // clocken1 -- can only be used for enabling clock1.
    // clocken2 -- as an alternative for enabling clock0.
    // clocken3 -- as an alternative for enabling clock1.
    input  clocken0;
    input  clocken1;
    input  clocken2;
    input  clocken3;

    // clear inputs on both ports and here are their usage
    // Port A -- 1. all input registers can only be cleared by clear0 or none.
    //           2. output register can be cleared by either clear0, clear1 or none.
    // Port B -- 1. all input registers can be cleared by clear0, clear1 or none.
    //           2. output register can be cleared by either clear0, clear1 or none.
    input  aclr0;
    input  aclr1;

    input [width_byteena_a-1:0] byteena_a; // Port A byte enable input
    input [width_byteena_b-1:0] byteena_b; // Port B byte enable input

    // Stratix II related ports
    input addressstall_a;
    input addressstall_b;

    // Nadder new features
    input   sclr;
    input   eccencbypass;
    input   [width_eccencparity-1:0] eccencparity;
    input   [widthad2_a-1:0] address2_a; // Port A address input (Read Address for SQP)
    input   [widthad2_b-1:0] address2_b; // Port B address input (Read Address for SQP)
    


// OUTPUT PORT DECLARATION

    output [width_a-1:0] q_a; // Port A output
    output [width_b-1:0] q_b; // Port B output

    output [width_eccstatus-1:0] eccstatus;   // ECC status flags

// INTERNAL REGISTERS DECLARATION

    reg [width_eccstatus-1:0] ecc_data [0:(1<<widthad_a)-1];
    reg [width_eccstatus-1:0] ecc_data_b [0:(1<<widthad_b)-1];
    reg [width_eccencparity-1:0] i_eccencparity;
    reg [width_a-1:0] mem_data [0:(1<<widthad_a)-1];
    reg [width_b-1:0] mem_data_b [0:(1<<widthad_b)-1];
    reg [width_a-1:0] i_data_reg_a;
    reg [width_eccstatus-1:0] temp_ecc_a;
    reg [width_eccstatus-1:0] temp_ecc_b;
    reg [width_a-1:0] temp_wa;
    reg [width_a-1:0] temp_wa2;
    reg [width_a-1:0] temp_wa2b;
    reg [width_a-1:0] init_temp;
    reg [width_b-1:0] i_data_reg_b;
    reg [width_b-1:0] temp_wb;
    reg [width_b-1:0] temp_wb2;
    reg temp;
    reg [width_a-1:0] i_q_reg_a;
    reg [width_eccstatus-1:0] i_q_reg_ecc_a;
    reg [width_a-1:0] i_q_tmp_a;
    reg [width_eccstatus-1:0] i_q_tmp_ecc_a;
    reg [width_a-1:0] i_q_tmp2_a;
    reg [width_eccstatus-1:0] i_q_tmp2_ecc_a;
    reg [width_b-1:0] i_q_reg_b;
    reg [width_eccstatus-1:0] i_q_reg_ecc_b;
    reg [width_b-1:0] i_q_tmp_b;
    reg [width_eccstatus-1:0] i_q_tmp_ecc_b;
    reg [width_b-1:0] i_q_tmp2_b;
    reg [width_eccstatus-1:0] i_q_tmp2_ecc_b;
    reg [width_b-1:0] i_q_output_latch;
    reg [width_eccstatus-1:0] i_q_output_latch_ecc;
    reg [width_a-1:0] i_byteena_mask_reg_a;
    reg [width_b-1:0] i_byteena_mask_reg_b;
    reg [widthad_a-1:0] i_address_reg_a;
    reg [widthad_b-1:0] i_address_reg_b;
    reg [widthad2_a-1:0] i_address_reg_a2;
    reg [widthad2_b-1:0] i_address_reg_b2;
	
    reg [width_b-1:0] i_q_ecc_reg_b;
    reg [width_eccstatus-1:0] i_q_ecc_status_reg_b;
    reg [width_b-1:0] i_q_ecc_tmp_b;
    reg [width_eccstatus-1:0] i_q_ecc_status_tmp_b;
	
    reg [widthad_a-1:0] i_original_address_a;
    
    reg [width_a-1:0] i_byteena_mask_reg_a_tmp;
    reg [width_b-1:0] i_byteena_mask_reg_b_tmp;
    reg [width_a-1:0] i_byteena_mask_reg_a_out;
    reg [width_b-1:0] i_byteena_mask_reg_b_out;
    reg [width_a-1:0] i_byteena_mask_reg_a_x;
    reg [width_b-1:0] i_byteena_mask_reg_b_x;
    reg [width_a-1:0] i_byteena_mask_reg_a_out_b;
    reg [width_b-1:0] i_byteena_mask_reg_b_out_a;


    reg [8*256:1] ram_initf;
    reg i_wren_reg_a;
    reg i_wren_reg_b;
    reg i_rden_reg_a;
    reg i_rden_reg_b;
    reg i_rden_reg_b_bypass;
    reg i_read_flag_a;
    reg i_read_flag_b;
    reg i_write_flag_a;
    reg i_write_flag_b;
    reg good_to_go_a;
    reg good_to_go_b;
    reg [31:0] file_desc;
    reg init_file_b_port;
    reg i_nmram_write_a;
    reg i_nmram_write_b;

    reg [width_a - 1: 0] wa_mult_x;
    reg [width_eccstatus - 1: 0] ecc_a_mult_x;
    reg [width_a - 1: 0] wa_mult_x_ii;
    reg [width_a - 1: 0] wa_mult_x_iii;
    reg [widthad_a + width_a - 1:0] add_reg_a_mult_wa;
    reg [widthad_b + width_b -1:0] add_reg_b_mult_wb;
    reg [widthad_a + width_a - 1:0] add_reg_a_mult_wa_pl_wa;
    reg [widthad_b + width_b -1:0] add_reg_b_mult_wb_pl_wb;

    reg same_clock_pulse0;
    reg same_clock_pulse1;
    
    reg [width_b - 1 : 0] i_original_data_b;
    reg [width_a - 1 : 0] i_original_data_a;
    
    reg i_address_aclr_a_flag;
    reg i_address_aclr_a_prev;
    reg i_address_aclr_b_flag;
    reg i_address_aclr_b_prev;
    reg i_outdata_aclr_a_prev;
    reg i_outdata_aclr_b_prev;
    reg i_outdata_sclr_a_prev;
    reg i_outdata_sclr_b_prev;
    reg i_outdata_sclr_a_reg;
    reg i_outdata_sclr_b_reg;
    reg i_force_reread_a;
    reg i_force_reread_a1;
    reg i_force_reread_b;
    reg i_force_reread_b1;
    reg i_force_reread_a_signal;
    reg i_force_reread_b_signal;


// REG FOR DELTA DELAYS OF INPUT PORTS

	reg wren_a_dly;
	reg wren_b_dly;
	reg rden_a_dly;
	reg rden_b_dly;
	reg [width_a-1:0] data_a_dly;
	reg [width_b-1:0] data_b_dly;
	reg [widthad_a-1:0] address_a_dly;
	reg [widthad_b-1:0] address_b_dly;
	reg clocken0_dly;
	reg clocken1_dly;
	reg clocken2_dly;
	reg clocken3_dly;
	reg [width_byteena_a-1:0] byteena_a_dly;
	reg [width_byteena_b-1:0] byteena_b_dly;
	reg addressstall_a_dly;
	reg addressstall_b_dly;
	
	// Available only from Stratix10 onwards;
	reg [widthad2_a-1:0] address2_a_dly;
	reg [widthad2_b-1:0] address2_b_dly;
	reg [width_eccencparity-1:0] eccencparity_dly;
	reg eccencbypass_dly;

// INTERNAL PARAMETER
    reg [21*8:0] cread_during_write_mode_mixed_ports;
    reg [7*8:0] i_ram_block_type;
    integer i_byte_size;
    
//!! SPR 218496 : to control writes for M4K in HC families 
    wire i_good_to_write_a;
    wire i_good_to_write_b;
    reg i_good_to_write_a2;
    reg i_good_to_write_b2;

    reg i_core_clocken_a_reg;
    reg i_core_clocken0_b_reg;
    reg i_core_clocken1_b_reg;

// INTERNAL WIRE DECLARATIONS

    wire i_indata_aclr_a;
    wire i_address_aclr_a;
    wire i_wrcontrol_aclr_a;
    wire i_indata_aclr_b;
    wire i_address_aclr_b;
    wire i_wrcontrol_aclr_b;
    wire i_outdata_aclr_a;
    wire i_outdata_aclr_b;
    wire i_outdata_sclr_a;
    wire i_outdata_sclr_b;
    wire i_rdcontrol_aclr_b;
    wire i_byteena_aclr_a;
    wire i_byteena_aclr_b;
    wire i_outdata_clken_a;
    wire i_outdata_clken_b;
    wire i_outlatch_clken_a;
    wire i_outlatch_clken_b;	
    wire i_clocken0;
    wire i_clocken1_b;
    wire i_clocken0_b;
    wire i_core_clocken_a;
    wire i_core_clocken_b;
    wire i_core_clocken0_b;
    wire i_core_clocken1_b;
    wire [widthad_a - 1:0] i_out_addr_a;
    wire [widthad_b - 1:0] i_out_addr_b;
    
// INTERNAL TRI DECLARATION

    tri0 wren_a;
    tri0 wren_b;
    tri1 rden_a;
    tri1 rden_b;
    tri1 clock0;
    tri1 clocken0;
    tri1 clocken1;
    tri1 clocken2;
    tri1 clocken3;
    tri0 aclr0;
    tri0 aclr1;
    tri0 sclr;
    tri0 eccencbypass;
    tri0 [width_eccencparity-1:0] eccencparity;
    tri0 [widthad2_a -1:0] address2_a;
    tri0 [widthad2_b -1:0] address2_b;
    tri0 addressstall_a;
    tri0 addressstall_b;
    tri1 [width_byteena_a-1:0] byteena_a;
    tri1 [width_byteena_b-1:0] byteena_b;
    tri1 [width_byteena_a-1:0] i_byteena_a;
    tri1 [width_byteena_b-1:0] i_byteena_b;


// LOCAL INTEGER DECLARATION

    integer i_numwords_a;
    integer i_numwords_b;
    integer i_aclr_flag_a;
    integer i_aclr_flag_b;
    integer i_q_tmp2_a_idx;

    // for loop iterators
    integer init_i;
    integer i;
    integer i2;
    integer i3;
    integer i4;
    integer i5;
    integer j;
    integer j2;
    integer j3;
    integer k;
    integer k2;
    integer k3;
    integer k4;
    
    // For temporary calculation
    integer i_div_wa;
    integer i_div_wb;
    integer j_plus_i2;
    integer j2_plus_i5;
    integer j3_plus_i5;
    integer j_plus_i2_div_a;
    integer j2_plus_i5_div_a;
    integer j3_plus_i5_div_a;
    integer j3_plus_i5_div_b;
    integer i_byteena_count;
    integer port_a_bit_count_low;
    integer port_a_bit_count_high;
    integer port_b_bit_count_low;
    integer port_b_bit_count_high;

    time i_data_write_time_a;
    time i_data_write_time_b;

    // ------------------------
    // COMPONENT INSTANTIATIONS
    // ------------------------
    // ALTERA_DEVICE_FAMILIES dev ();
    ALTERA_LNSIM_MEMORY_INITIALIZATION mem ();

// DELTA DELAYS FOR INPUT PORTS
	always@(wren_a) begin
		wren_a_dly <= wren_a;
	end
	
	always@(wren_b) begin
		wren_b_dly <= wren_b;
	end
	
	always@(rden_a) begin
		rden_a_dly <= rden_a;
	end
	
	always@(rden_b) begin
		rden_b_dly <= rden_b;
	end
	
	always@(data_a) begin
		data_a_dly <= data_a;
	end
	
	always@(data_b) begin
		data_b_dly <= data_b;
	end
	
	always@(address_a) begin
		address_a_dly <= address_a;
	end
	
	always@(address_b) begin
		address_b_dly <= address_b;
	end
	
	always@(clocken0) begin
		clocken0_dly <= clocken0;
	end
	
	always@(clocken1) begin
		clocken1_dly <= clocken1;
	end
	
	always@(clocken2) begin
		clocken2_dly <= clocken2;
	end
	
	always@(clocken3) begin
		clocken3_dly <= clocken3;
	end
	
	always@(byteena_a) begin
		byteena_a_dly <= byteena_a;
	end
	
	always@(byteena_b) begin
		byteena_b_dly <= byteena_b;
	end
	
	always@(addressstall_a) begin
		addressstall_a_dly <= addressstall_a;
	end
	
	always@(addressstall_b) begin
		addressstall_b_dly <= addressstall_b;
	end
	
	always@(eccencparity) begin
		eccencparity_dly <= eccencparity;
	end
	
	always@(eccencbypass) begin
		eccencbypass_dly <= eccencbypass;
	end
	
	always@(address2_a) begin
		address2_a_dly <= address2_a;
	end
	
	always@(address2_b) begin
		address2_b_dly <= address2_b;
	end


        // Initialize mem_data
    task automatic initialize_mem_contents();
        if ((init_file == "UNUSED") || (init_file == ""))
        begin
            if(power_up_uninitialized == "TRUE")
            begin
                wa_mult_x = {width_a{1'bx}};
                for (i = 0; i < (1 << widthad_a); i = i + 1)
                    mem_data[i] = wa_mult_x;

                if (enable_mem_data_b_reading)
                begin
                    for (i = 0; i < (1 << widthad_b); i = i + 1)
                    mem_data_b[i] = {width_b{1'bx}};
                end
            end
            else
            begin
                wa_mult_x = {width_a{1'b0}};
		ecc_a_mult_x = {width_eccstatus{1'b0}};
                for (i = 0; i < (1 << widthad_a); i = i + 1)
		begin                 
   		    mem_data[i] = wa_mult_x;
		    ecc_data[i] = wa_mult_x;
		end
           
                if (enable_mem_data_b_reading)
                begin
                    for (i = 0; i < (1 << widthad_b); i = i + 1)
                        mem_data_b[i] = {width_b{1'b0}};
 	 		ecc_data_b[i] = {width_eccstatus{1'b0}};
                end
            end
	end
        else  // Memory initialization file is used
        begin

            wa_mult_x = {width_a{1'b0}};
	    ecc_a_mult_x = {width_eccstatus{1'b0}};
            for (i = 0; i < (1 << widthad_a); i = i + 1)
	    begin
                mem_data[i] = wa_mult_x;
		ecc_data[i] = ecc_a_mult_x;
            end
                
            for (i = 0; i < (1 << widthad_b); i = i + 1)
	    begin
                mem_data_b[i] = {width_b{1'b0}};
		ecc_data_b[i] = {width_eccstatus{1'b0}};
            end

            init_file_b_port = 0;

            if ((init_file_layout != "PORT_A") &&
                (init_file_layout != "PORT_B"))
            begin
                if (operation_mode == "DUAL_PORT")
                    init_file_b_port = 1;
                else
                    init_file_b_port = 0;
            end
            else
            begin
                if (init_file_layout == "PORT_A")
                    init_file_b_port = 0;
                else if (init_file_layout == "PORT_B")
                    init_file_b_port = 1;
            end

            if (init_file_b_port)
            begin
               if (ram_initf == 0) begin
                  mem.convert_to_ver_file(init_file, width_b, ram_initf);
               end
               $display("Initializing memory contents for %m with %s", ram_initf);
               $readmemh(ram_initf, mem_data_b);

                for (i = 0; i < (i_numwords_b * width_b); i = i + 1)
                begin
                    temp_wb = mem_data_b[i / width_b];
		    temp_ecc_b = {width_eccstatus{1'b0}};
                    i_div_wa = i / width_a;
                    temp_wa = mem_data[i_div_wa];
		    temp_ecc_a = {width_eccstatus{1'b0}};
                    temp_wa[i % width_a] = temp_wb[i % width_b];
 		    temp_ecc_a[i % width_a] = temp_ecc_b[i % width_b];
                    mem_data[i_div_wa] = temp_wa;
		    ecc_data[i_div_wa] = temp_ecc_a;
                end
            end
            else
            begin
               if (ram_initf == 0) begin
                  mem.convert_to_ver_file(init_file, width_a, ram_initf);
               end
               $display("Initializing memory contents for %m with %s", ram_initf);
               $readmemh(ram_initf, mem_data);
                
                if (enable_mem_data_b_reading)
                begin                
                    for (i = 0; i < (i_numwords_a * width_a); i = i + 1)
                    begin
                        temp_wa = mem_data[i / width_a];
                        i_div_wb = i / width_b;
                        temp_wb = mem_data_b[i_div_wb];
 			temp_ecc_b = {width_eccstatus{1'b0}};
                        temp_wb[i % width_b] = temp_wa[i % width_a];
			temp_ecc_b[i % width_b] = temp_ecc_a[i % width_a];
                        mem_data_b[i_div_wb] = temp_wb;
			ecc_data_b[i_div_wb] = temp_ecc_b;
                    end
                end
            end
        end
    endtask

// INITIAL CONSTRUCT BLOCK

    initial
    begin
		
        //!! INTERNAL PARAMETER SETTING

        i_numwords_a = (numwords_a != 0) ? numwords_a : (1 << widthad_a);
        i_numwords_b = (numwords_b != 0) ? numwords_b : (1 << widthad_b);
        

		if ((is_lutram == 1) || (ram_block_type == "M10K") || (ram_block_type == "M20K"))
			i_ram_block_type = ram_block_type;
		else
			i_ram_block_type = "AUTO";
			
        cread_during_write_mode_mixed_ports = read_during_write_mode_mixed_ports;
            
        i_byte_size = (byte_size > 0) ? byte_size
                        : ((i_byte_size_tmp != 5) && (i_byte_size_tmp !=10) && (i_byte_size_tmp != 8) && (i_byte_size_tmp != 9)) ?
                            8 : i_byte_size_tmp;
            
        // Parameter Checking
        if ((operation_mode != "QUAD_PORT") && (operation_mode != "BIDIR_DUAL_PORT") && (operation_mode != "SINGLE_PORT") &&
            (operation_mode != "DUAL_PORT") && (operation_mode != "ROM") && (operation_mode != "QUAD_PORT"))
        begin
            $display("Error: Not a valid operation mode.");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if (i_ram_block_type != ram_block_type)
        begin
            $display("Warning: RAM block type is assumed as %s", i_ram_block_type);
            $display("Time: %0t  Instance: %m", $time);
        end

//!! End checking

        if ((cread_during_write_mode_mixed_ports != "DONT_CARE") &&
            (cread_during_write_mode_mixed_ports != "CONSTRAINED_DONT_CARE") &&
            (cread_during_write_mode_mixed_ports != "OLD_DATA") && 
	    (cread_during_write_mode_mixed_ports != "NEW_A_OLD_B") && 
            (cread_during_write_mode_mixed_ports != "NEW_DATA"))
        begin
            $display("Error: Invalid value for read_during_write_mode_mixed_ports parameter. It has to be OLD_DATA or DONT_CARE or CONSTRAINED_DONT_CARE or NEW_DATA");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end
        
        if ((cread_during_write_mode_mixed_ports != read_during_write_mode_mixed_ports) && ((operation_mode != "SINGLE_PORT") && (operation_mode != "ROM")))
        begin
            $display("Warning: read_during_write_mode_mixed_ports is assumed as %s", cread_during_write_mode_mixed_ports);
            $display("Time: %0t  Instance: %m", $time);
        end
        
        if ((is_lutram != 1) && (cread_during_write_mode_mixed_ports == "CONSTRAINED_DONT_CARE"))
        begin
            $display("Warning: read_during_write_mode_mixed_ports cannot be set to CONSTRAINED_DONT_CARE for non-LUTRAM ram block type. This will cause incorrect simulation result.");
            $display("Time: %0t  Instance: %m", $time);
        end

        if ((is_lutram != 1) && (cread_during_write_mode_mixed_ports == "NEW_DATA"))
        begin
            $display("Warning: read_during_write_mode_mixed_ports cannot be set to NEW_DATA for non-LUTRAM ram block type. This will cause incorrect simulation result.");
            $display("Time: %0t  Instance: %m", $time);
        end
		
		if ((is_lutram == 1) && (read_during_write_mode_port_a == "NEW_DATA_WITH_NBE_READ") && (operation_mode == "SINGLE_PORT") && (outdata_reg_a == "UNREGISTERED"))
		begin
            $display("Warning: Value for read_during_write_mode_port_a of instance is not honoured in SINGLE PORT operation mode when output registers are not clocked by clock0 for LUTRAM.");
            $display("Time: %0t  Instance: %m", $time);
        end
		
		if ((is_lutram != 1) && (ram_block_type != "AUTO") && (read_during_write_mode_port_a == "DONT_CARE") && (operation_mode == "SINGLE_PORT"))
		begin
			$display("Warning: Value for read_during_write_mode_port_a of instance is assumed as NEW_DATA_NO_NBE_READ for current INTENDED DEVICE FAMILY %s", intended_device_family);
			$display("Time: %0t  Instance: %m", $time);
		end
		
//!! Byte size checking for Titan/Barracuda
        if ((i_byte_size != 5) && (i_byte_size != 8) && (i_byte_size != 9) && (i_byte_size != 10))
        begin
            $display("Error: byte_size has to be either 5,8,9 or 10 for %s device family", intended_device_family);
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if (width_a <= 0)
        begin
            $display("Error: Invalid value for WIDTH_A parameter");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if ((width_b <= 0) &&
            ((operation_mode != "SINGLE_PORT") && (operation_mode != "ROM")))
        begin
            $display("Error: Invalid value for WIDTH_B parameter");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if (widthad_a <= 0)
        begin
            $display("Error: Invalid value for WIDTHAD_A parameter");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if ((widthad_b <= 0) &&
            ((operation_mode != "SINGLE_PORT") && (operation_mode != "ROM")))
        begin
            $display("Error: Invalid value for WIDTHAD_B parameter");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if ((operation_mode == "DUAL_PORT") && (i_numwords_a * width_a != i_numwords_b * width_b))
        begin
            $display("Error: Total number of bits of port A and port B should be the same for dual port mode");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end
		
        if ((operation_mode == "BIDIR_DUAL_PORT") && (i_numwords_a * width_a != i_numwords_b * width_b))
        begin
            $display("Error: Total number of bits of port A and port B should be the same for bidir dual port mode");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end
		
        if ((operation_mode == "QUAD_PORT") && (i_numwords_a * width_a != i_numwords_b * width_b))
        begin
            $display("Error: Total number of bits of port A and port B should be the same for quad port mode");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if ((implement_in_les != "OFF") && (implement_in_les != "ON"))
        begin
            $display("Error: Illegal value for implement_in_les parameter");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

        if (((init_file == "UNUSED") || (init_file == "")) &&
            (operation_mode == "ROM"))
        begin
            $display("Error! Altsyncram needs data file for memory initialization in ROM mode.");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

//!! Aclr parameter checking
        if (((address_aclr_a != "UNUSED") && (address_aclr_a != "NONE") && (operation_mode != "ROM")) ||
            ((address_aclr_b != "UNUSED") && (address_aclr_b != "NONE") && (operation_mode != "DUAL_PORT")))
        begin
            $display("Warning: %s aclr signal on input ports is not supported for current operation mode. The aclr to input ports will be ignored.", intended_device_family);
            $display("Time: %0t  Instance: %m", $time);
        end
        
//!! Read-during-write-mixed-port = NEW_DATA or CONSTRAINED_DONT_CARE: only allowed in LUTRAM, with input and output clocked by the same source
        if ((is_lutram != 1) && (i_ram_block_type != "AUTO") && 
            ((read_during_write_mode_mixed_ports == "NEW_DATA") || (read_during_write_mode_mixed_ports == "CONSTRAINED_DONT_CARE")))
        begin
            $display("Error: %s value for read_during_write_mode_mixed_ports is not supported in %s RAM block type", read_during_write_mode_mixed_ports, i_ram_block_type);
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end
        
//!! SPR 272541: Constraint on LUTRAM warning only when read_during_writemode_mixed_ports is set to OLD_DATA
        if ((operation_mode == "DUAL_PORT") && (outdata_reg_b != "CLOCK0") && (is_lutram == 1) && (read_during_write_mode_mixed_ports == "OLD_DATA"))
        begin
            $display("Warning: Value for read_during_write_mode_mixed_ports of instance is not honoured in DUAL PORT operation mode when output registers are not clocked by clock0 for LUTRAM.");
            $display("Time: %0t  Instance: %m", $time);
        end
        
        if ((address_aclr_b != "NONE") && (address_aclr_b != "UNUSED") && ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT")))
        begin
            $display("Warning: %s value for address_aclr_b is not supported for write port in %s device family. The aclr to address_b registers will be ignored.", address_aclr_b, intended_device_family);
            $display("Time: %0t  Instance: %m", $time);
        end
    
        if ((is_lutram == 1) && (read_during_write_mode_mixed_ports == "OLD_DATA")
            && ((address_aclr_b != "NONE") && (address_aclr_b != "UNUSED")) && (operation_mode == "DUAL_PORT"))
        begin
            $display("Warning : aclr signal for address_b is ignored for RAM block type %s when read_during_write_mode_mixed_ports is set to OLD_DATA", ram_block_type);
            $display("Time: %0t  Instance: %m", $time);
        end

//!! Only SDP mode M144K and M20K can use ECC. Error out since legality check in synthesis errors out anyway.
       if((enable_ecc == "TRUE") && ((i_ram_block_type != "M20K") || (operation_mode != "DUAL_PORT")))
        begin
            $display("Error: %s value for enable_ecc is not supported in %s ram block type for %s device family in %s operation mode", enable_ecc, i_ram_block_type, intended_device_family, operation_mode);
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end
 
//!! ECC Errors : SPR 372383, FB:22498	
		if ((i_ram_block_type != "M20K") && (ecc_pipeline_stage_enabled == "TRUE"))
        begin
            $display("Error: %s value for ecc_pipeline_stage_enabled is not supported in %s ram block type.", ecc_pipeline_stage_enabled, i_ram_block_type);
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end

		if ((outdata_reg_b == "UNREGISTERED") && (ecc_pipeline_stage_enabled == "TRUE"))
        begin
            $display("Error: %s value for ecc_pipeline_stage_enabled is not supported when output_reg_b is set to %s.", ecc_pipeline_stage_enabled, outdata_reg_b);
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end		
		
		//Setting this to only warning because in synthesis it will ignore the ecc_pipeline_stage_enabled parameter when enable_ecc is set to false
		if((ecc_pipeline_stage_enabled == "TRUE") && (enable_ecc != "TRUE"))
		begin
            $display("Warning: %s value for ecc_pipeline_stage_enabled is not supported when enable_ecc is set to %s", ecc_pipeline_stage_enabled, enable_ecc);
            $display("Time: %0t  Instance: %m", $time);
		end
		
        if ((i_ram_block_type == "M20K") && (enable_ecc == "TRUE") && (read_during_write_mode_mixed_ports == "OLD_DATA"))
        begin
            $display("Error : ECC is not supported for read-before-write mode.");
            $display("Time: %0t  Instance: %m", $time);
            $finish;
        end
        
        if (operation_mode != "DUAL_PORT")
        begin
            if ((outdata_reg_a != "CLOCK0") && (outdata_reg_a != "CLOCK1") && (outdata_reg_a != "UNUSED")  && (outdata_reg_a != "UNREGISTERED"))
            begin
                $display("Error: %s value for outdata_reg_a is not supported.", outdata_reg_a);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end
        end

        if ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "DUAL_PORT") || (operation_mode == "QUAD_PORT"))
        begin
            if ((address_reg_b != "CLOCK0") && (address_reg_b != "CLOCK1") && (address_reg_b != "UNUSED"))
            begin
                $display("Error: %s value for address_reg_b is not supported.", address_reg_b);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end
    
            if ((outdata_reg_b != "CLOCK0") && (outdata_reg_b != "CLOCK1") && (outdata_reg_b != "UNUSED") && (outdata_reg_b != "UNREGISTERED"))
            begin
                $display("Error: %s value for outdata_reg_b is not supported.", outdata_reg_b);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end

            if ((rdcontrol_reg_b != "CLOCK0") && (rdcontrol_reg_b != "CLOCK1") && (rdcontrol_reg_b != "UNUSED") && (operation_mode == "DUAL_PORT"))
            begin
                $display("Error: %s value for rdcontrol_reg_b is not supported.", rdcontrol_reg_b);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end
    
            if ((indata_reg_b != "CLOCK0") && (indata_reg_b != "CLOCK1") && (indata_reg_b != "UNUSED") && ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT")))
            begin
                $display("Error: %s value for indata_reg_b is not supported.", indata_reg_b);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end
    
            if ((wrcontrol_wraddress_reg_b != "CLOCK0") && (wrcontrol_wraddress_reg_b != "CLOCK1") && (wrcontrol_wraddress_reg_b != "UNUSED") && ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT")))
            begin
                $display("Error: %s value for wrcontrol_wraddress_reg_b is not supported.", wrcontrol_wraddress_reg_b);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end
    
            if ((byteena_reg_b != "CLOCK0") && (byteena_reg_b != "CLOCK1") && (byteena_reg_b != "UNUSED") && ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT")))
            begin
                $display("Error: %s value for byteena_reg_b is not supported.", byteena_reg_b);
                $display("Time: %0t  Instance: %m", $time);
                $finish;
            end
        end

        // *****************************************
        // legal operations for all operation modes:
        //      |  PORT A  |  PORT B  |
        //      |  RD  WR  |  RD  WR  |
        // BDP  |  x   x   |  x   x   |
        // DP   |      x   |  x       |
        // SP   |  x   x   |          |
        // ROM  |  x       |          |
        // *****************************************


        // Clear the filename to initialize
        ram_initf = 0;
        
        initialize_mem_contents();

        i_nmram_write_a = 0;
        i_nmram_write_b = 0;

        i_aclr_flag_a = 0;
        i_aclr_flag_b = 0;

        i_outdata_aclr_a_prev = 0;
        i_outdata_aclr_b_prev = 0;
        i_address_aclr_a_prev = 0;
        i_address_aclr_b_prev = 0;
        i_outdata_sclr_a_prev = 0;
        i_outdata_sclr_b_prev = 0;
        i_outdata_sclr_a_reg  = 0;
        i_outdata_sclr_b_reg  = 0;
        
        i_force_reread_a = 0;
        i_force_reread_a1 = 0;
        i_force_reread_b = 0;
        i_force_reread_b1 = 0;
        i_force_reread_a_signal = 0;
        i_force_reread_b_signal = 0;
        
        // Initialize internal registers/signals
	wren_a_dly  = 0;
        i_data_reg_a = 0;
        i_data_reg_b = 0;
        i_address_reg_a = 0;
        i_address_reg_b = 0;
        i_address_reg_a2 = 0;
        i_address_reg_b2 = 0;
        i_original_address_a = 0;
        i_wren_reg_a = 0;
        i_wren_reg_b = 0;
        i_read_flag_a = 0;
        i_read_flag_b = 0;
        i_write_flag_a = 0;
        i_write_flag_b = 0;
        i_byteena_mask_reg_a_x = 0;
        i_byteena_mask_reg_b_x = 0;
        i_original_data_b = 0;
        i_original_data_a = 0;
        i_data_write_time_a = 0;
        i_data_write_time_b = 0;
        i_core_clocken_a_reg = 0;
        i_core_clocken0_b_reg = 0;
        i_core_clocken1_b_reg = 0;

        i_byteena_mask_reg_a = {width_a{1'b0}};
        i_byteena_mask_reg_b = {width_a{1'b0}};
        i_byteena_mask_reg_a_out = {width_a{1'b0}};
        i_byteena_mask_reg_b_out = {width_a{1'b0}};
		
		i_rden_reg_a = 0;
		i_rden_reg_b = 0;
		i_rden_reg_b_bypass = 1'b0;
		//initialize reg and latches
		if (is_lutram == 1) 
		begin
			i_q_tmp_a = mem_data[0];
			i_q_tmp2_a = mem_data[0];

			for (init_i = 0; init_i < width_b; init_i = init_i + 1)
			begin
				init_temp = mem_data[init_i / width_a];
				i_q_tmp_b[init_i] = init_temp[init_i % width_a];
				i_q_tmp2_b[init_i] = init_temp[init_i % width_a];
			end

			i_q_reg_a = 0;
			i_q_reg_b = 0;
			i_q_reg_ecc_b = 0;
			i_q_output_latch = 0;
			i_q_output_latch_ecc = 0;
		end
		else
		begin
			i_q_tmp_a = 0;
                        i_q_tmp_ecc_a = 0;
			i_q_tmp_b = 0;
			i_q_tmp_ecc_b = 0;
			i_q_tmp2_a = 0;
			i_q_tmp2_ecc_a = 0;
			i_q_tmp2_b = 0;
			i_q_tmp2_ecc_b = 0;
			i_q_reg_a = 0;
			i_q_reg_ecc_a = 0;
			i_q_reg_b = 0;
			i_q_reg_ecc_b = 0;
                        i_q_ecc_status_reg_b = 0;
                        i_q_ecc_reg_b = 0;
		end

        good_to_go_a = 0;
        good_to_go_b = 0;

        same_clock_pulse0 = 1'b0;
        same_clock_pulse1 = 1'b0;

        i_byteena_count = 0;
       
		i_good_to_write_a2 = 1;
		i_good_to_write_b2 = 1;

    end


// SIGNAL ASSIGNMENT

    // Clock enable signal assignment

    // port a clock enable assignments:
    assign i_outdata_clken_a              = (clock_enable_output_a == "BYPASS") ?
                                            1'b1 : ((clock_enable_output_a == "ALTERNATE") && (outdata_reg_a == "CLOCK1")) ?
                                            clocken3_dly : ((clock_enable_output_a == "ALTERNATE") && (outdata_reg_a == "CLOCK0")) ?
                                            clocken2_dly : (outdata_reg_a == "CLOCK1") ?
                                            clocken1_dly : (outdata_reg_a == "CLOCK0") ?
                                            clocken0_dly : 1'b1;
    // port b clock enable assignments:
    assign i_outdata_clken_b              = (clock_enable_output_b == "BYPASS") ?
                                            1'b1 : ((clock_enable_output_b == "ALTERNATE") && (outdata_reg_b == "CLOCK1")) ?
                                            clocken3_dly : ((clock_enable_output_b == "ALTERNATE") && (outdata_reg_b == "CLOCK0")) ?
                                            clocken2_dly : (outdata_reg_b == "CLOCK1") ?
                                            clocken1_dly : (outdata_reg_b == "CLOCK0") ?
                                            clocken0_dly : 1'b1;

    // port a output latch clock enable assignments:
    assign i_outlatch_clken_a              = ((clock_enable_output_b == "NORMAL") && (outdata_reg_a == "UNREGISTERED") && (outdata_reg_b == "CLOCK0") && 
											 ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT")))?
                                            clocken0_dly : 1'b1;
    // port b clock enable assignments:
    assign i_outlatch_clken_b              = ((clock_enable_output_a == "NORMAL") && (outdata_reg_b == "UNREGISTERED") && 
											((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT")))?
											(((address_reg_b == "CLOCK0") && (outdata_reg_a == "CLOCK0")) ? clocken0_dly : 
											(((address_reg_b == "CLOCK1") && (outdata_reg_a == "CLOCK1")) ? clocken1_dly : 1'b1))
											: 1'b1;
											
    assign i_clocken0                     = (clock_enable_input_a == "BYPASS") ?
                                            1'b1 : (clock_enable_input_a == "NORMAL") ?
                                            clocken0_dly : clocken2_dly;

    assign i_clocken0_b                   = (clock_enable_input_b == "BYPASS") ?
                                            1'b1 : (clock_enable_input_b == "NORMAL") ?
                                            clocken0_dly : clocken2_dly;

    assign i_clocken1_b                   = (clock_enable_input_b == "BYPASS") ?
                                            1'b1 : (clock_enable_input_b == "NORMAL") ?
                                            clocken1_dly : clocken3_dly;

    assign i_core_clocken_a              = (clock_enable_core_a == "BYPASS") ?
                                            1'b1 : ((clock_enable_core_a == "USE_INPUT_CLKEN") ?
                                            i_clocken0 : ((clock_enable_core_a == "NORMAL") ?
                                            clocken0_dly : clocken2_dly));
    
    assign i_core_clocken0_b              = (clock_enable_core_b == "BYPASS") ?
                                            1'b1 : ((clock_enable_core_b == "USE_INPUT_CLKEN") ?
                                            i_clocken0_b : ((clock_enable_core_b == "NORMAL") ?
                                            clocken0_dly : clocken2_dly));

    assign i_core_clocken1_b              = (clock_enable_core_b == "BYPASS") ?
                                            1'b1 : ((clock_enable_core_b == "USE_INPUT_CLKEN") ?
                                            i_clocken1_b : ((clock_enable_core_b == "NORMAL") ?
                                            clocken1_dly : clocken3_dly));

    assign i_core_clocken_b               = (address_reg_b == "CLOCK0") ?
                                            i_core_clocken0_b : i_core_clocken1_b;

    // Async clear signal assignment

    // port a clear assigments:

    assign i_indata_aclr_a    = 1'b0; //disconnected
    assign i_address_aclr_a   = (address_aclr_a == "CLEAR0") ? aclr0 : 1'b0;
    assign i_wrcontrol_aclr_a = 1'b0; //disconnected
    assign i_byteena_aclr_a   = 1'b0; //disconnected
    assign i_outdata_aclr_a   = (outdata_aclr_a == "CLEAR0") ?
                                aclr0 : ((outdata_aclr_a == "CLEAR1") ?
                                aclr1 : 1'b0);
    assign i_outdata_sclr_a   = (outdata_sclr_a == "SCLEAR") ? sclr : 1'b0;
                                                                
    // port b clear assignments:
    assign i_indata_aclr_b    = 1'b0; //disconnected
    assign i_address_aclr_b   = (address_aclr_b == "CLEAR0") ?
                                aclr0 : ((address_aclr_b == "CLEAR1") ?
                                aclr1 : 1'b0);
    assign i_wrcontrol_aclr_b = 1'b0; //disconnected
    assign i_rdcontrol_aclr_b = 1'b0; //disconnected
    assign i_byteena_aclr_b   = 1'b0; //disconnected
    assign i_outdata_aclr_b   = (outdata_aclr_b == "CLEAR0") ?
                                aclr0 : ((outdata_aclr_b == "CLEAR1") ?
                                aclr1 : 1'b0);
    assign i_outdata_sclr_b   = (outdata_sclr_b == "SCLEAR") ? sclr : 1'b0;

    assign i_byteena_a = byteena_a_dly;
    assign i_byteena_b = byteena_b_dly;
    

    assign i_out_addr_a = (operation_mode == "QUAD_PORT")? i_address_reg_a2 : i_address_reg_a;
    assign i_out_addr_b = (operation_mode == "QUAD_PORT")? i_address_reg_b2 : i_address_reg_b;
        
    // Ready to write setting
    
    assign i_good_to_write_a = (((is_bidir_and_wrcontrol_addb_clk0 == 1) || (dual_port_addreg_b_clk0 == 1)) && (i_core_clocken0_b) && (~clock0)) ?
                                    1'b1 : (((is_bidir_and_wrcontrol_addb_clk1 == 1) || (dual_port_addreg_b_clk1 == 1)) && (i_core_clocken1_b) && (~clock1)) ?
                                    1'b1 : i_good_to_write_a2;
                                    
    assign i_good_to_write_b = ((i_core_clocken0_b) && (~clock0)) ? 1'b1 : i_good_to_write_b2;
    
    always @(i_good_to_write_a)
    begin
        i_good_to_write_a2 = i_good_to_write_a;
    end
    
    always @(i_good_to_write_b)
    begin
        i_good_to_write_b2 = i_good_to_write_b;
    end
    
     
    // Port A inputs registered : indata, address, byeteena, wren
    // Aclr status flags get updated here for M-RAM ram_block_type

    always @(posedge clock0)
    begin
    
        if (i_force_reread_a && i_outlatch_clken_a)
        begin
            i_force_reread_a_signal <= ~ i_force_reread_a_signal;
            i_force_reread_a <= 0;
        end
        
        if (i_force_reread_b && ((is_bidir_and_wrcontrol_addb_clk0 == 1) || (dual_port_addreg_b_clk0 == 1)) && i_outlatch_clken_b)
        begin
            i_force_reread_b_signal <= ~ i_force_reread_b_signal;
            i_force_reread_b <= 0;
        end

        if (clock1)
            same_clock_pulse0 <= 1'b1;
        else
            same_clock_pulse0 <= 1'b0;

        if (i_address_aclr_a && (is_rom == 1))
            i_address_reg_a <= 0;

        i_core_clocken_a_reg <= i_core_clocken_a;
        i_core_clocken0_b_reg <= i_core_clocken0_b;

        if (i_core_clocken_a)
        begin

            if (i_force_reread_a1)
            begin
                i_force_reread_a_signal <= ~ i_force_reread_a_signal;
                i_force_reread_a1 <= 0;
            end
            i_read_flag_a <= ~ i_read_flag_a;
            if (i_force_reread_b1 && ((is_bidir_and_wrcontrol_addb_clk0 == 1) || (dual_port_addreg_b_clk0 == 1)))
            begin
                i_force_reread_b_signal <= ~ i_force_reread_b_signal;
                i_force_reread_b1 <= 0;
            end
            if (is_write_on_positive_edge == 1)
            begin
                if (i_wren_reg_a || wren_a_dly)
                begin
                    i_write_flag_a <= ~ i_write_flag_a;
                end
                if (operation_mode != "ROM")
                    i_nmram_write_a <= 1'b0;
            end
            else
            begin
                if (operation_mode != "ROM")
                    i_nmram_write_a <= 1'b1;
            end

            //!! Titan's and later family's wren & rden is controlled by core CE
            if (is_lutram != 1)
            begin
                //!! for independent rden_a implementation, no aclr involved because in Titan / Barracuda, no aclr to control input registers
                //!! this port only available in Titan/Cuda
                good_to_go_a <= 1;
                
                i_rden_reg_a <= rden_a_dly;

                if (i_wrcontrol_aclr_a)
                    i_wren_reg_a <= 0;
                else
                begin
                    i_wren_reg_a <= wren_a_dly;
                end
            end
        end
        else
            i_nmram_write_a <= 1'b0;

        if (i_core_clocken_b)    
            i_address_aclr_b_flag <= 0;

        if (is_lutram)
        begin
            if (i_wrcontrol_aclr_a)
                i_wren_reg_a <= 0;
            else if (i_core_clocken_a)
            begin
                i_wren_reg_a <= wren_a_dly;
            end
        end

        if (i_clocken0)
        begin

            // Port A inputs
            i_outdata_sclr_a_reg <=  i_outdata_sclr_a;
            if (i_indata_aclr_a)
                i_data_reg_a <= 0;
            else
                i_data_reg_a <= data_a_dly;

            if (i_address_aclr_a && (is_rom == 1))
                i_address_reg_a <= 0;
            else if (!addressstall_a_dly)
                i_address_reg_a <= address_a_dly;

            i_address_reg_a2 <= address2_a_dly;
            
            if (i_byteena_aclr_a)
            begin
                i_byteena_mask_reg_a <= {width_a{1'b1}};
                i_byteena_mask_reg_a_out <= 0;
                i_byteena_mask_reg_a_x <= 0;
                i_byteena_mask_reg_a_out_b <= {width_a{1'bx}};
            end
            else
            begin
               
                if (width_byteena_a == 1)
                begin
                    i_byteena_mask_reg_a <= {width_a{i_byteena_a[0]}};
                    i_byteena_mask_reg_a_out <= (i_byteena_a[0])? {width_a{1'b0}} : {width_a{1'bx}};
                    i_byteena_mask_reg_a_out_b <= (i_byteena_a[0])? {width_a{1'bx}} : {width_a{1'b0}};
                    i_byteena_mask_reg_a_x <= ((i_byteena_a[0]) || (i_byteena_a[0] == 1'b0))? {width_a{1'b0}} : {width_a{1'bx}};
                end
                else
                    for (k = 0; k < width_a; k = k+1)
                    begin
                        i_byteena_mask_reg_a[k] <= i_byteena_a[k/i_byte_size]=== 1'bx ? 1'b1: i_byteena_a[k/i_byte_size];
                        i_byteena_mask_reg_a_out_b[k] <= (i_byteena_a[k/i_byte_size])? 1'bx: 1'b0;
                        i_byteena_mask_reg_a_out[k] <= (i_byteena_a[k/i_byte_size])? 1'b0: 1'bx;
                        i_byteena_mask_reg_a_x[k] <= ((i_byteena_a[k/i_byte_size]) || (i_byteena_a[k/i_byte_size] == 1'b0))? 1'b0: 1'bx;
                    end
               
            end

            //!! Titan's wren is control by core CE, others are not
            if (is_lutram == 1)
            begin
                good_to_go_a <= 1;
            
                i_rden_reg_a <= rden_a_dly;
                
                if (i_wrcontrol_aclr_a)
                    i_wren_reg_a <= 0;
                else
                begin
                    i_wren_reg_a <= wren_a_dly;
                end
            end

        end
        
        //!! Aclr handling for port A inputs, input registers should be cleared though CE is held low
        
        if (i_indata_aclr_a)
            i_data_reg_a <= 0;

        if (i_address_aclr_a && (is_rom == 1))
            i_address_reg_a <= 0;

        if (i_byteena_aclr_a)
        begin
            i_byteena_mask_reg_a <= {width_a{1'b1}};
            i_byteena_mask_reg_a_out <= 0;
            i_byteena_mask_reg_a_x <= 0;
            i_byteena_mask_reg_a_out_b <= {width_a{1'bx}};
        end
        
        
        // Port B

        if (is_bidir_and_wrcontrol_addb_clk0)
        begin

            if (i_core_clocken0_b)
            begin
				good_to_go_b <= 1;
				
				i_rden_reg_b <= rden_b_dly;

				if (i_wrcontrol_aclr_b)
					i_wren_reg_b <= 0;
				else
				begin
					i_wren_reg_b <= wren_b_dly;
				end
                
                i_read_flag_b <= ~i_read_flag_b;
                    
                if (is_write_on_positive_edge == 1)
                begin
                    if (i_wren_reg_b || wren_b_dly)
                    begin
                        i_write_flag_b <= ~ i_write_flag_b;
                    end
                    i_nmram_write_b <= 1'b0;
                end
                else
                    i_nmram_write_b <= 1'b1;
            
            end
            else
                i_nmram_write_b <= 1'b0;
                
                
            if (i_clocken0_b)
            begin

                // Port B inputs
                i_outdata_sclr_b_reg <=  i_outdata_sclr_b;
                if (i_indata_aclr_b)
                    i_data_reg_b <= 0;
                else
                    i_data_reg_b <= data_b_dly;

                if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                    i_address_reg_b <= 0;
                else if (!addressstall_b_dly)
                    i_address_reg_b <= address_b_dly;

                i_address_reg_b2 <= address2_b_dly;
                if (i_byteena_aclr_b)
                begin
                    i_byteena_mask_reg_b <= {width_b{1'b1}};
                    i_byteena_mask_reg_b_out <= 0;
                    i_byteena_mask_reg_b_x <= 0;
                    i_byteena_mask_reg_b_out_a <= {width_b{1'bx}};
                end
                else
                begin
                   
                    if (width_byteena_b == 1)
                    begin
                        i_byteena_mask_reg_b <= {width_b{i_byteena_b[0]}};
                        i_byteena_mask_reg_b_out_a <= (i_byteena_b[0])? {width_b{1'bx}} : {width_b{1'b0}};
                        i_byteena_mask_reg_b_out <= (i_byteena_b[0])? {width_b{1'b0}} : {width_b{1'bx}};
                        i_byteena_mask_reg_b_x <= ((i_byteena_b[0]) || (i_byteena_b[0] == 1'b0))? {width_b{1'b0}} : {width_b{1'bx}};
                    end
                    else
                        for (k2 = 0; k2 < width_b; k2 = k2 + 1)
                        begin
                            i_byteena_mask_reg_b[k2] <= i_byteena_b[k2/i_byte_size];
                            i_byteena_mask_reg_b_out_a[k2] <= (i_byteena_b[k2/i_byte_size])? 1'bx : 1'b0;
                            i_byteena_mask_reg_b_out[k2] <= (i_byteena_b[k2/i_byte_size])? 1'b0 : 1'bx;
                            i_byteena_mask_reg_b_x[k2] <= ((i_byteena_b[k2/i_byte_size]) || (i_byteena_b[k2/i_byte_size] == 1'b0))? 1'b0 : 1'bx;
                        end
                    
                end

            end
            
            //!! Aclr handling for Port B when CE held low
            
            if (i_indata_aclr_b)
                i_data_reg_b <= 0;

            if (i_wrcontrol_aclr_b)
                i_wren_reg_b <= 0;

            if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                i_address_reg_b <= 0;

            if (i_byteena_aclr_b)
            begin
                i_byteena_mask_reg_b <= {width_b{1'b1}};
                i_byteena_mask_reg_b_out <= 0;
                i_byteena_mask_reg_b_x <= 0;
                i_byteena_mask_reg_b_out_a <= {width_b{1'bx}};
            end
        end
            
        if (dual_port_addreg_b_clk0)
        begin
            if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                i_address_reg_b <= 0;

            if (i_core_clocken0_b)
            begin
                if (!is_lutram)
                begin
                    good_to_go_b <= 1;
                    
                    if (i_rdcontrol_aclr_b)
                        i_rden_reg_b <= 1'b1;
                    else
                        i_rden_reg_b <= rden_b_dly;
                end
                
                i_read_flag_b <= ~ i_read_flag_b;
            end
            else if(i_rden_reg_b_bypass)
			begin
				i_read_flag_b <= ~i_read_flag_b;
			end
			
            if (i_clocken0_b)
            begin
                i_outdata_sclr_b_reg <=  i_outdata_sclr_b;
                if (is_lutram)
                begin
                    good_to_go_b <= 1;
                
                    if (i_rdcontrol_aclr_b)
                        i_rden_reg_b <= 1'b1;
                    else
                        i_rden_reg_b <= rden_b_dly;
                end

                if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                    i_address_reg_b <= 0;
                else if (!addressstall_b)
                    i_address_reg_b <= address_b_dly;
                
                i_address_reg_b2 <= address2_b_dly;
            end
            
            //!! Aclr handling for Port B when CE held low
            
            if (i_rdcontrol_aclr_b)
                i_rden_reg_b <= 1'b1;

            if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                i_address_reg_b <= 0;

        end

    end


    always @(negedge clock0)
    begin
       
        if (clock1)
            same_clock_pulse0 <= 1'b0;

        if (is_write_on_positive_edge == 0)
        begin
            if (i_nmram_write_a == 1'b1)
            begin
                i_write_flag_a <= ~ i_write_flag_a;
                
                if (is_lutram)
                    i_read_flag_a <= ~i_read_flag_a;
            end 

            
            if (is_bidir_and_wrcontrol_addb_clk0)
            begin
                if (i_nmram_write_b == 1'b1)
                    i_write_flag_b <= ~ i_write_flag_b;
            end
        end

//!! Not sure if the clocken will give effect on the new data read by LUTRAM. Temporary put it here.
        if (i_core_clocken0_b && (lutram_dual_port_fast_read == 1) && (dual_port_addreg_b_clk0 == 1))
        begin
            i_read_flag_b <= ~i_read_flag_b;
        end

    end



    always @(posedge clock1)
    begin
        i_core_clocken1_b_reg <= i_core_clocken1_b;

        if (i_force_reread_b && ((is_bidir_and_wrcontrol_addb_clk1 == 1) || (dual_port_addreg_b_clk1 == 1)))
        begin
            i_force_reread_b_signal <= ~ i_force_reread_b_signal;
            i_force_reread_b <= 0;
        end
        
        if (clock0)
            same_clock_pulse1 <= 1'b1;
        else
            same_clock_pulse1 <= 1'b0;

        if (i_core_clocken_b)    
            i_address_aclr_b_flag <= 0;

        if (is_bidir_and_wrcontrol_addb_clk1)
        begin

            if (i_core_clocken1_b)
            begin
                i_read_flag_b <= ~i_read_flag_b;
    
				good_to_go_b <= 1;
				
				i_rden_reg_b <= rden_b_dly;

				if (i_wrcontrol_aclr_b)
					i_wren_reg_b <= 0;
				else
				begin
					i_wren_reg_b <= wren_b_dly;
				end
                
                if (is_write_on_positive_edge == 1)
                begin
                    if (i_wren_reg_b || wren_b_dly)
                    begin
                        i_write_flag_b <= ~ i_write_flag_b;
                    end
                    i_nmram_write_b <= 1'b0;
                end
                else
                    i_nmram_write_b <= 1'b1;
            end
            else
                i_nmram_write_b <= 1'b0;
                
        
            if (i_clocken1_b)
            begin
                
                // Port B inputs
                
                if (address_reg_b == "CLOCK1")
                begin
                    if (i_indata_aclr_b)
                        i_data_reg_b <= 0;
                    else
                        i_data_reg_b <= data_b_dly;
                end

                if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                    i_address_reg_b <= 0;
                else if (!addressstall_b)
                    i_address_reg_b <= address_b_dly;

                i_address_reg_b2 <= address2_b_dly;    
                if (i_byteena_aclr_b)
                begin
                    i_byteena_mask_reg_b <= {width_b{1'b1}};
                    i_byteena_mask_reg_b_out <= 0;
                    i_byteena_mask_reg_b_x <= 0;
                    i_byteena_mask_reg_b_out_a <= {width_b{1'bx}};
                end
                else
                begin
                    if (width_byteena_b == 1)
                    begin
                        i_byteena_mask_reg_b <= {width_b{i_byteena_b[0]}};
                        i_byteena_mask_reg_b_out_a <= (i_byteena_b[0])? {width_b{1'bx}} : {width_b{1'b0}};
                        i_byteena_mask_reg_b_out <= (i_byteena_b[0])? {width_b{1'b0}} : {width_b{1'bx}};
                        i_byteena_mask_reg_b_x <= ((i_byteena_b[0]) || (i_byteena_b[0] == 1'b0))? {width_b{1'b0}} : {width_b{1'bx}};
                    end
                    else
                        for (k2 = 0; k2 < width_b; k2 = k2 + 1)
                        begin
                            i_byteena_mask_reg_b[k2] <= i_byteena_b[k2/i_byte_size];
                            i_byteena_mask_reg_b_out_a[k2] <= (i_byteena_b[k2/i_byte_size])? 1'bx : 1'b0;
                            i_byteena_mask_reg_b_out[k2] <= (i_byteena_b[k2/i_byte_size])? 1'b0 : 1'bx;
                            i_byteena_mask_reg_b_x[k2] <= ((i_byteena_b[k2/i_byte_size]) || (i_byteena_b[k2/i_byte_size] == 1'b0))? 1'b0 : 1'bx;
                        end
                
                end

            end
            
            //!! Aclr handling for Port B when CE held low
            
            if (i_indata_aclr_b)
                i_data_reg_b <= 0;

            if (i_wrcontrol_aclr_b)
                i_wren_reg_b <= 0;

            if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                i_address_reg_b <= 0;

            if (i_byteena_aclr_b)
            begin
                i_byteena_mask_reg_b <= {width_b{1'b1}};
                i_byteena_mask_reg_b_out <= 0;
                i_byteena_mask_reg_b_x <= 0;
                i_byteena_mask_reg_b_out_a <= {width_b{1'bx}};
            end
        end

        if (dual_port_addreg_b_clk1)
        begin
            if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                i_address_reg_b <= 0;

            if (i_core_clocken1_b)
            begin
                if (i_force_reread_b1)
                begin
                    i_force_reread_b_signal <= ~ i_force_reread_b_signal;
                    i_force_reread_b1 <= 0;
                end
                if (!is_lutram)
                begin
                    good_to_go_b <= 1;
                    
                    if (i_rdcontrol_aclr_b)
                    begin
                        i_rden_reg_b <= 1'b1;
                    end
                    else
                    begin
                        i_rden_reg_b <= rden_b_dly;
                    end
                end

                i_read_flag_b <= ~i_read_flag_b;
            end
			else if(i_rden_reg_b_bypass)
			begin
				i_read_flag_b <= ~i_read_flag_b;
			end
            
            if (i_clocken1_b)
            begin
                if (is_lutram)
                begin
                    good_to_go_b <= 1;
                end
    
                if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                    i_address_reg_b <= 0;
                else if (!addressstall_b)
                    i_address_reg_b <= address_b_dly;

                i_address_reg_b2 <= address2_b_dly;
            end
            
            //!! Aclr handling for Port B when CE held low
            
            if (i_rdcontrol_aclr_b)
                i_rden_reg_b <= 1'b1;

            if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                i_address_reg_b <= 0;
                
        end

    end

    always @(negedge clock1)
    begin
       
        if (clock0)
            same_clock_pulse1 <= 1'b0;
            
        if (is_write_on_positive_edge == 0)
        begin
           
            if (is_bidir_and_wrcontrol_addb_clk1)
            begin
                if (i_nmram_write_b == 1'b1)
                    i_write_flag_b <= ~ i_write_flag_b;
            end
        end

//!! Not sure of clocken to give impact on LUTRAM read new data :
        if (i_core_clocken1_b && (lutram_dual_port_fast_read == 1) && (dual_port_addreg_b_clk1 ==1))
        begin
            i_read_flag_b <= ~i_read_flag_b;
        end

    end
    
    always @(posedge i_address_aclr_b)
    begin
        if ((is_lutram == 1) && (operation_mode == "DUAL_PORT") && (i_address_aclr_family_b == 0))
            i_read_flag_b <= ~i_read_flag_b;
    end

    always @(posedge i_address_aclr_a)
    begin
        if ((is_lutram == 1) && (operation_mode == "ROM"))
            i_read_flag_a <= ~i_read_flag_a;
    end
    
    always @(posedge i_outdata_aclr_a or posedge i_outdata_sclr_a_reg)
    begin
        if ((outdata_reg_a != "CLOCK0") && (outdata_reg_a != "CLOCK1"))
            i_read_flag_a <= ~i_read_flag_a;
    end

    always @(posedge i_outdata_aclr_b or posedge i_outdata_sclr_b_reg)
    begin
        if ((outdata_reg_b != "CLOCK0") && (outdata_reg_b != "CLOCK1"))
            i_read_flag_b <= ~i_read_flag_b;
    end
	
    always @(negedge i_outdata_aclr_b or negedge i_outdata_sclr_b_reg)
    begin
        if ((enable_ecc == "TRUE") && (outdata_reg_b != "CLOCK0") && (outdata_reg_b != "CLOCK1"))
		begin
            i_rden_reg_b_bypass <= 1'b1;
		end
    end    
    // Port A writting -------------------------------------------------------------

    always @(posedge i_write_flag_a or negedge i_write_flag_a)
    begin
        if ((operation_mode == "BIDIR_DUAL_PORT") ||
            (operation_mode == "QUAD_PORT") ||
            (operation_mode == "DUAL_PORT") ||
            (operation_mode == "SINGLE_PORT"))
        begin

            if ((i_wren_reg_a) && (i_good_to_write_a))
            begin
                i_aclr_flag_a = 0;

                if (i_indata_aclr_a)
                begin
                    if (i_data_reg_a != 0)
                    begin
                        mem_data[i_address_reg_a] = {width_a{1'bx}};

                        if (enable_mem_data_b_reading)
                        begin
                            j3 = i_address_reg_a * width_a;
                            for (i5 = 0; i5 < width_a; i5 = i5+1)
                            begin
                                    j3_plus_i5 = j3 + i5;
                                    temp_wb = mem_data_b[j3_plus_i5 / width_b];
                                    temp_wb[j3_plus_i5 % width_b] = {1'bx};
                                    mem_data_b[j3_plus_i5 / width_b] = temp_wb;
                            end
                        end
                        i_aclr_flag_a = 1;
                    end
                end
                else if (i_byteena_aclr_a)
                begin
                    if (i_byteena_mask_reg_a != {width_a{1'b1}})
                    begin
                        mem_data[i_address_reg_a] = {width_a{1'bx}};
                        
                        if (enable_mem_data_b_reading)
                        begin
                            j3 = i_address_reg_a * width_a;
                            for (i5 = 0; i5 < width_a; i5 = i5+1)
                            begin
                                    j3_plus_i5 = j3 + i5;
                                    temp_wb = mem_data_b[j3_plus_i5 / width_b];
                                    temp_wb[j3_plus_i5 % width_b] = {1'bx};
                                    mem_data_b[j3_plus_i5 / width_b] = temp_wb;
                            end
                        end
                        i_aclr_flag_a = 1;
                    end
                end
                else if (i_address_aclr_a && (is_rom == 1))
                begin
                    if (i_address_reg_a != 0)
                    begin
                        wa_mult_x_ii = {width_a{1'bx}};
                        for (i4 = 0; i4 < i_numwords_a; i4 = i4 + 1)
                            mem_data[i4] = wa_mult_x_ii;
                            
                        if (enable_mem_data_b_reading)
                        begin
                            for (i4 = 0; i4 < i_numwords_b; i4 = i4 + 1)
                                mem_data_b[i4] = {width_b{1'bx}};
                        end

                        i_aclr_flag_a = 1;
                    end
                end

                if (i_aclr_flag_a == 0)
                begin
                    i_original_data_a = mem_data[i_address_reg_a];
                    i_original_address_a = i_address_reg_a;
                    i_data_write_time_a = $time;
                    temp_wa = mem_data[i_address_reg_a];
		    temp_ecc_a = ecc_data[i_address_reg_a];
                    
                    port_a_bit_count_low = i_address_reg_a * width_a;
                    port_b_bit_count_low = i_address_reg_b * width_b;
                    port_b_bit_count_high = port_b_bit_count_low + width_b;
                    
                    for (i5 = 0; i5 < width_a; i5 = i5 + 1)
                    begin
                        i_byteena_count = port_a_bit_count_low % width_b;

		       if((i_wren_reg_b && (i_address_reg_a == i_address_reg_b))&& i_byteena_mask_reg_a[i5] && enable_non_corrupted_behav)
		       begin
			//temp_wb[i5] = temp_wb[i5] ^ i_byteena_mask_reg_a[i5];
			temp_wa[i5] =temp_wb;
			temp_wa[i5] = i_data_reg_a[i5];
		      end

                        else if ((port_a_bit_count_low >= port_b_bit_count_low) && (port_a_bit_count_low < port_b_bit_count_high) &&
                            ((i_core_clocken0_b_reg && (is_bidir_and_wrcontrol_addb_clk0 == 1)) || (i_core_clocken1_b_reg && (is_bidir_and_wrcontrol_addb_clk1 == 1))) && 
                            (i_wren_reg_b) && ((same_clock_pulse0 && same_clock_pulse1) || (address_reg_b == "CLOCK0")) &&
                            (i_byteena_mask_reg_b[i_byteena_count]) && (i_byteena_mask_reg_a[i5]))
                            temp_wa[i5] = {1'bx};
                        else if (i_byteena_mask_reg_a[i5])
                            temp_wa[i5] = i_data_reg_a[i5];
							
                        if (enable_mem_data_b_reading)
                        begin
                            temp_wb = mem_data_b[port_a_bit_count_low / width_b];
                            temp_wb[port_a_bit_count_low % width_b] = temp_wa[i5];
                            mem_data_b[port_a_bit_count_low / width_b] = temp_wb;
                        end

                        port_a_bit_count_low = port_a_bit_count_low + 1;
                    end

                    mem_data[i_address_reg_a] = temp_wa;
		    if (eccencbypass)
		    begin
                    	temp_ecc_a = mem.ecc_parity(eccencparity_dly);
		    	ecc_data[i_address_reg_a] = temp_ecc_a;
		    end
		    else
		    begin
			temp_ecc_a = mem.ecc_parity(8'h0);
		        ecc_data[i_address_reg_a] = 2'h0;
		    end

                    if ((dual_port_addreg_b_clk0 == 1) ||								//SIMPLE DUAL PORT same clock
						(is_bidir_and_wrcontrol_addb_clk0 == 1) || 						//TRUE DUAL PORT same clock
                        ((lutram_dual_port_fast_read == 1) && (operation_mode == "DUAL_PORT")))
                        i_read_flag_b = ~i_read_flag_b;
                        
                    if ((read_during_write_mode_port_a == "OLD_DATA") ||
                        ((is_lutram == 1) && (read_during_write_mode_port_a == "DONT_CARE")))
                        i_read_flag_a = ~i_read_flag_a;
                end

            end
        end
    end    // Port A writting ----------------------------------------------------


    // Port B writting -----------------------------------------------------------

    always @(posedge i_write_flag_b or negedge i_write_flag_b)
    begin
        if ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT"))
        begin

            if ((i_wren_reg_b) && (i_good_to_write_b))
            begin
            
                i_aclr_flag_b = 0;

                // RAM content is following width_a
                // if Port B is of different width, need to make some adjustments

                if (i_indata_aclr_b)
                begin
                    if (i_data_reg_b != 0)
                    begin
                        if (enable_mem_data_b_reading)
                            mem_data_b[i_address_reg_b] = {width_b{1'bx}};
                       
                        if (width_a == width_b)
                            mem_data[i_address_reg_b] = {width_b{1'bx}};
                        else
                        begin
                            j = i_address_reg_b * width_b;
                            for (i2 = 0; i2 < width_b; i2 = i2+1)
                            begin
                                    j_plus_i2 = j + i2;
                                    temp_wa = mem_data[j_plus_i2 / width_a];
                                    temp_wa[j_plus_i2 % width_a] = {1'bx};
                                    mem_data[j_plus_i2 / width_a] = temp_wa;
                            end
                        end
                        i_aclr_flag_b = 1;
                    end
                end
                else if (i_byteena_aclr_b)
                begin
                    if (i_byteena_mask_reg_b != {width_b{1'b1}})
                    begin
                        if (enable_mem_data_b_reading)
                            mem_data_b[i_address_reg_b] = {width_b{1'bx}};
                        
                        if (width_a == width_b)
                            mem_data[i_address_reg_b] = {width_b{1'bx}};
                        else
                        begin
                            j = i_address_reg_b * width_b;
                            for (i2 = 0; i2 < width_b; i2 = i2+1)
                            begin
                                j_plus_i2 = j + i2;
                                j_plus_i2_div_a = j_plus_i2 / width_a;
                                temp_wa = mem_data[j_plus_i2_div_a];
                                temp_wa[j_plus_i2 % width_a] = {1'bx};
                                mem_data[j_plus_i2_div_a] = temp_wa;
                            end
                        end
                        i_aclr_flag_b = 1;
                    end
                end
                else if (i_address_aclr_b && (i_address_aclr_family_b == 0))
                begin
                    if (i_address_reg_b != 0)
                    begin
                        
                        if (enable_mem_data_b_reading)
                        begin
                            for (i2 = 0; i2 < i_numwords_b; i2 = i2 + 1)
                            begin
                                mem_data_b[i2] = {width_b{1'bx}};
                            end
                        end
                        
                        wa_mult_x_iii = {width_a{1'bx}};
                        for (i2 = 0; i2 < i_numwords_a; i2 = i2 + 1)
                        begin
                            mem_data[i2] = wa_mult_x_iii;
                        end
                        i_aclr_flag_b = 1;
                    end
                end

                if (i_aclr_flag_b == 0)
                begin
                        port_b_bit_count_low = i_address_reg_b * width_b;
                        port_a_bit_count_low = i_address_reg_a * width_a;
                        port_a_bit_count_high = port_a_bit_count_low + width_a;
                        i_data_write_time_b = $time;
                        for (i2 = 0; i2 < width_b; i2 = i2 + 1)
                        begin
                            port_b_bit_count_high = port_b_bit_count_low + i2;
                            temp_wa = mem_data[port_b_bit_count_high / width_a];
			    temp_ecc_a = ecc_data[port_b_bit_count_high / width_a];
                            i_original_data_b[i2] = temp_wa[port_b_bit_count_high % width_a];
                            
			if ((i_wren_reg_a && (i_address_reg_a == i_address_reg_b))&& i_byteena_mask_reg_a[i2] && enable_non_corrupted_behav)
			begin
				temp_wa[port_b_bit_count_high % width_a] = i_data_reg_a[i2];
			end

                           
			else if ((port_b_bit_count_high >= port_a_bit_count_low) && (port_b_bit_count_high < port_a_bit_count_high) &&
                                ((same_clock_pulse0 && same_clock_pulse1) || (address_reg_b == "CLOCK0")) &&
                                (i_core_clocken_a_reg) && (i_wren_reg_a) &&
                                (i_byteena_mask_reg_a[port_b_bit_count_high % width_a]) && (i_byteena_mask_reg_b[i2]))
                                temp_wa[port_b_bit_count_high % width_a] = {1'bx};
                            else if (i_byteena_mask_reg_b[i2])
                                temp_wa[port_b_bit_count_high % width_a] = i_data_reg_b[i2];
                            
                            mem_data[port_b_bit_count_high / width_a] = temp_wa;
                            temp_wb[i2] = temp_wa[port_b_bit_count_high % width_a];
                        end

                        if (enable_mem_data_b_reading)
                            mem_data_b[i_address_reg_b] = temp_wb;
			    ecc_data_b[i_address_reg_b] = temp_ecc_b;

                    if ((read_during_write_mode_port_b == "OLD_DATA") && (is_write_on_positive_edge == 1))
                        i_read_flag_b = ~i_read_flag_b;
                        
                    if (((cread_during_write_mode_mixed_ports == "OLD_DATA") || (cread_during_write_mode_mixed_ports == "NEW_A_OLD_B"))&& (address_reg_b == "CLOCK0") && (is_write_on_positive_edge == 1))
                        i_read_flag_a = ~i_read_flag_a;

                end

            end
            
        end
    end


    // Port A reading

    always @(i_read_flag_a)
    begin
        if ((operation_mode == "BIDIR_DUAL_PORT") ||
            (operation_mode == "QUAD_PORT") ||
            (operation_mode == "SINGLE_PORT") ||
            (operation_mode == "ROM"))
        begin
            if (~good_to_go_a && (is_lutram == 0))
            begin
				i_q_tmp2_a = 0;
				i_q_tmp2_ecc_a = 0;
            end
            else
            begin //!! good_to_go_a
                if (i_rden_reg_a)
                begin
                    // read from RAM content or flow through for write cycle
                    if (i_wren_reg_a)
                    begin
                        if (i_core_clocken_a)
                        begin
							if (read_during_write_mode_port_a == "NEW_DATA_NO_NBE_READ")
							begin
								i_q_tmp2_a = ((i_data_reg_a & i_byteena_mask_reg_a) | ({width_a{1'bx}} & ~i_byteena_mask_reg_a));
								i_q_tmp2_ecc_a = ((i_data_reg_a & i_byteena_mask_reg_a) | ({width_a{1'bx}} & ~i_byteena_mask_reg_a));
                                                        end
							else if (read_during_write_mode_port_a == "NEW_DATA_WITH_NBE_READ")
								begin
									//NEW_DATA for lutram
									if (is_lutram && clock0)
										i_q_tmp2_a = mem_data[i_address_reg_a];
									else
                                //NEW_DATA_NO_NBE_READ
										i_q_tmp2_a = ((i_data_reg_a & i_byteena_mask_reg_a) | ({width_a{1'bx}} & ~i_byteena_mask_reg_a));
								end
							else if (operation_mode == "QUAD_PORT")
							begin
								if (i_address_reg_a2 == i_address_reg_a)
								begin
									i_q_tmp2_a = {width_a{1'bx}};
								end
								else
								begin
									i_q_tmp2_a = mem_data[i_address_reg_a2];
								end 
							end
					
							
							else //!! DONT_CARE
									i_q_tmp2_a = {width_a{1'bx}};
                        end
                        else
                        begin
                            if(operation_mode == "QUAD_PORT")
                                i_q_tmp2_a = mem_data[i_address_reg_a2];
                            else
                                i_q_tmp2_a = mem_data[i_address_reg_a];
				i_q_tmp2_ecc_a = ecc_data[i_address_reg_a];
                        end
                                
                    end
                    else
                    begin
                        if(operation_mode == "QUAD_PORT")
                            i_q_tmp2_a = mem_data[i_address_reg_a2];
                        else
                            i_q_tmp2_a = mem_data[i_address_reg_a];
			    i_q_tmp2_ecc_a = ecc_data[i_address_reg_a];
                    end
                    
                    if (is_write_on_positive_edge == 1)
                    begin

                        if (is_bidir_and_wrcontrol_addb_clk0 || (same_clock_pulse0 && same_clock_pulse1)) //TRUE DUAL PORT same clock
                        begin
                            // B write, A read
                          if ((i_wren_reg_b & ~i_wren_reg_a) & 
                            ((((is_bidir_and_wrcontrol_addb_clk0 & i_clocken0_b) || 
                            (is_bidir_and_wrcontrol_addb_clk1 & i_clocken1_b))) ||
                            (((is_bidir_and_wrcontrol_addb_clk0 & i_core_clocken0_b) || 
                            (is_bidir_and_wrcontrol_addb_clk1 & i_core_clocken1_b))))
                            & (i_data_write_time_b == $time))
                            begin
                                if(operation_mode == "QUAD_PORT") begin
				    if (i_address_reg_a2 == i_address_reg_b) begin
                                    add_reg_a_mult_wa = i_address_reg_a2 * width_a;
                                    add_reg_b_mult_wb = i_address_reg_b2 * width_b;
                                    end
				    else begin                                
                                    add_reg_a_mult_wa = i_address_reg_a * width_a;
                                    add_reg_b_mult_wb = i_address_reg_b * width_b;
                                    end
                                end
                                else begin                                
                                    add_reg_a_mult_wa = i_address_reg_a * width_a;
                                    add_reg_b_mult_wb = i_address_reg_b * width_b;
                                end
                                add_reg_a_mult_wa_pl_wa = add_reg_a_mult_wa + width_a;
                                add_reg_b_mult_wb_pl_wb = add_reg_b_mult_wb + width_b;

                                if (
                                    ((add_reg_a_mult_wa >=
                                        add_reg_b_mult_wb) &&
                                    (add_reg_a_mult_wa <=
                                        (add_reg_b_mult_wb_pl_wb - 1)))
                                        ||
                                    (((add_reg_a_mult_wa_pl_wa - 1) >=
                                        add_reg_b_mult_wb) &&
                                    ((add_reg_a_mult_wa_pl_wa - 1) <=
                                        (add_reg_b_mult_wb_pl_wb - 1)))
                                        ||
                                    ((add_reg_b_mult_wb >=
                                        add_reg_a_mult_wa) &&
                                    (add_reg_b_mult_wb <=
                                        (add_reg_a_mult_wa_pl_wa - 1)))
                                        ||
                                    (((add_reg_b_mult_wb_pl_wb - 1) >=
                                        add_reg_a_mult_wa) &&
                                    ((add_reg_b_mult_wb_pl_wb - 1) <=
                                        (add_reg_a_mult_wa_pl_wa - 1)))
                                    )
                                        for (i3 = add_reg_a_mult_wa;
                                                i3 < add_reg_a_mult_wa_pl_wa;
                                                i3 = i3 + 1)
                                        begin
                                            if ((i3 >= add_reg_b_mult_wb) &&
                                                (i3 <= (add_reg_b_mult_wb_pl_wb - 1)))
                                            begin
                                            
                                                if (cread_during_write_mode_mixed_ports == "OLD_DATA")
                                                begin
                                                    i_byteena_count = i3 - add_reg_b_mult_wb;
                                                    i_q_tmp2_a_idx = (i3 - add_reg_a_mult_wa);
                                                    i_q_tmp2_a[i_q_tmp2_a_idx] = i_original_data_b[i_byteena_count];
                                                end
 						else if (cread_during_write_mode_mixed_ports == "NEW_A_OLD_B")
                                                begin
                                                    i_byteena_count = i3 - add_reg_b_mult_wb;
                                                    i_q_tmp2_a_idx = (i3 - add_reg_a_mult_wa);
                                                    i_q_tmp2_a[i_q_tmp2_a_idx] = i_q_tmp2_a[i_byteena_count];
                                                end
                                                else
                                                begin
                                                    i_byteena_count = i3 - add_reg_b_mult_wb;
                                                    i_q_tmp2_a_idx = (i3 - add_reg_a_mult_wa);
                                                    i_q_tmp2_a[i_q_tmp2_a_idx] = i_q_tmp2_a[i_q_tmp2_a_idx] ^ i_byteena_mask_reg_b_out_a[i_byteena_count];
                                                end
                                                
                                            end
                                        end
                            end
                        end
                    end
                end
                
                if ((is_lutram == 1) && i_address_aclr_a && (is_rom == 1) && (operation_mode == "ROM"))
                    i_q_tmp2_a = mem_data[0];
                
                if ((is_lutram != 1) &&
                    (i_outdata_aclr_a || i_outdata_sclr_a_reg || i_force_reread_a) &&
                    (outdata_reg_a != "CLOCK0") && (outdata_reg_a != "CLOCK1"))
		begin
                    i_q_tmp2_a = {width_a{1'b0}};
 		    i_q_tmp2_ecc_a = {width_eccstatus{1'b0}};
		end

            end // end good_to_go_a
        end
    end


    // assigning the correct output values for i_q_tmp_a (non-registered output)
    always @(i_q_tmp2_a or i_q_tmp2_ecc_a or i_wren_reg_a  or i_rden_reg_a or i_data_reg_a or i_address_aclr_a or
             i_out_addr_a or i_byteena_mask_reg_a_out or i_numwords_a or i_outdata_aclr_a or i_outdata_sclr_a_reg or i_force_reread_a_signal or i_original_data_a)
    begin
        if (i_out_addr_a >= i_numwords_a)
        begin
            if (i_wren_reg_a && i_core_clocken_a)
            begin
                i_q_tmp_a <= i_q_tmp2_a;
		i_q_tmp_ecc_a <= i_q_tmp2_ecc_a;
            end
            else
                i_q_tmp_a <= {width_a{1'bx}};
            if (i_rden_reg_a == 1)
            begin
                $display("Warning : Address pointed at port A is out of bound!");
                $display("Time: %0t  Instance: %m", $time);
            end
        end
        else 
            begin
                if (i_outdata_aclr_a_prev && ~ i_outdata_aclr_a && 
                    (is_lutram != 1))
                begin
                    i_outdata_aclr_a_prev = i_outdata_aclr_a;
                    i_force_reread_a <= 1;
                end 
                else if (((i_outdata_sclr_a_prev && ~ i_outdata_sclr_a_reg)) && 
                    (is_lutram != 1))
                begin
                    i_outdata_sclr_a_prev <= i_outdata_sclr_a_reg;
                    i_force_reread_a <= 1;
                end
                else if (~i_address_aclr_a_prev && i_address_aclr_a && (is_rom == 1) && block_ram_output_unreg)
                begin
                    if (i_rden_reg_a)
                        i_q_tmp_a <= {width_a{1'bx}};
                    i_force_reread_a1 <= 1;
                end
                else if ((i_force_reread_a == 0) && (i_force_reread_a1 == 0) && !(i_address_aclr_a_prev && ~i_address_aclr_a && (is_rom == 1) && block_ram_output_unreg)) //!! SPR 268781: exclude possibility of falling address_aclr
                begin
                    i_q_tmp_a <= i_q_tmp2_a;
                    i_q_tmp_ecc_a <= i_q_tmp2_ecc_a;
                end
            end
            if ((i_outdata_aclr_a) && (block_ram_output_unreg))
            begin
                i_q_tmp_a <= {width_a{1'b0}};
                i_outdata_aclr_a_prev <= i_outdata_aclr_a;
            end
            if ((i_outdata_sclr_a_reg) && (block_ram_output_unreg))
            begin
                i_q_tmp_a <= {width_a{1'b0}};
              //  i_outdata_sclr_a_prev <= i_outdata_sclr_a_reg;
            end
	    if (enable_force_to_zero == "TRUE" && ~i_rden_reg_a && (block_ram_output_unreg))
	    begin
		i_q_tmp_a <=0;
	    end
            i_address_aclr_a_prev <= i_address_aclr_a;
    end


    //!! SimQoR: Replace intermediate clock signal by generate-if statements
    // Port A outdata output registered
    generate if (outdata_reg_a == "CLOCK1")
        begin: clk1_on_outa_gen
            always @(posedge clock1 or posedge i_outdata_aclr_a)
            begin
                if (i_outdata_aclr_a)
                    i_q_reg_a <= 0;
                else if (i_outdata_clken_a)
                begin           
                    i_q_reg_a <= i_q_tmp_a;
		    i_q_reg_ecc_a <= i_q_tmp_ecc_a;
                    if (i_core_clocken_a)
                    i_address_aclr_a_flag <= 0;
		    if (i_outdata_sclr_a)
		    	i_q_reg_a <= 0;
		    if (enable_force_to_zero == "TRUE" && ~i_rden_reg_a)
			i_q_reg_a <=0;
                end
                else if (i_core_clocken_a)
                    i_address_aclr_a_flag <= 0;
            end
        end
        else if (outdata_reg_a == "CLOCK0")
        begin: clk0_on_outa_gen
            always @(posedge clock0 or posedge i_outdata_aclr_a)
            begin
                if (i_outdata_aclr_a)
                    i_q_reg_a <= 0;
                else if (i_outdata_clken_a)
                begin           
                    if ((i_address_aclr_a_flag == 1) && (!is_lutram))
                        i_q_reg_a <= 'bx;
                    else
		    begin
                        i_q_reg_a <= i_q_tmp_a;
			i_q_reg_ecc_a <= i_q_tmp_ecc_a;
		    end
                    if (i_core_clocken_a)
                    i_address_aclr_a_flag <= 0;
		    if (i_outdata_sclr_a)
			i_q_reg_a <= 0;
		    if (enable_force_to_zero == "TRUE" && ~i_rden_reg_a)
			i_q_reg_a <=0;
                end
                else if (i_core_clocken_a)
                    i_address_aclr_a_flag <= 0;
            end
        end
    endgenerate

    // Latch for address aclr till outclock enabled
    always @(posedge i_address_aclr_a or posedge i_outdata_aclr_a)
    begin
        if (i_outdata_aclr_a)
            i_address_aclr_a_flag <= 0;
        else
            if (i_rden_reg_a && (is_rom == 1))
                i_address_aclr_a_flag <= 1;
    end

    // Port A : assigning the correct output values for q_a
    assign q_a = (operation_mode == "DUAL_PORT") ?
                    {width_a{1'b0}} : (((outdata_reg_a == "CLOCK0") ||
                            (outdata_reg_a == "CLOCK1")) ?
                    i_q_reg_a : i_q_tmp_a);


    // Port B reading
    always @(i_read_flag_b)
    begin
        if ((operation_mode == "BIDIR_DUAL_PORT") ||
            (operation_mode == "QUAD_PORT") ||
            (operation_mode == "DUAL_PORT"))
        begin
            if (~good_to_go_b && (is_lutram == 0))
            begin
				i_q_tmp2_b = 0;
				i_q_tmp2_ecc_b = 0;
            end
            else //!! good_to_go_b
            begin
                if (i_rden_reg_b || (i_rden_reg_b_bypass))
                begin
                    //If width_a is equal to b, no address calculation is needed
                    if (width_a == width_b)
                    begin

                        // read from memory or flow through for write cycle
                        if (i_wren_reg_b && (((is_bidir_and_wrcontrol_addb_clk0 == 1) && i_core_clocken0_b) || 
                            ((is_bidir_and_wrcontrol_addb_clk1 == 1) && i_core_clocken1_b)))
                        begin
                            if (read_during_write_mode_port_b == "NEW_DATA_NO_NBE_READ")
			    begin
                                temp_wb = ((i_data_reg_b & i_byteena_mask_reg_b) |
                                            ({width_b{1'bx}} & ~i_byteena_mask_reg_b));
				temp_ecc_b = ((i_data_reg_b & i_byteena_mask_reg_b) |
                                            ({width_b{1'b0}} & ~i_byteena_mask_reg_b));
			    end
			    else if (operation_mode == "QUAD_PORT")
			    begin
				if (i_address_reg_b2 == i_address_reg_b)
				begin
					//temp_wb = i_data_reg_b;
					temp_wb = {width_b{1'bx}};
				end
				else if (i_address_reg_b2 == i_address_reg_a && i_wren_reg_a)
				begin
					temp_wb = i_original_data_a;
				end
				else 
					temp_wb = mem_data[i_address_reg_b2];		
			    end

			    //No longer support "NEW_DATA_WITH_NBE_READ" and "OLD_DATA" for same port read during write
			    else 
				begin
					temp_wb = {width_b{1'bx}};
				end
                        end
                        else
						begin
							if(~i_rden_reg_b_bypass || 
							((dual_port_addreg_b_clk0 && i_core_clocken0_b) ||
							(dual_port_addreg_b_clk0 && i_core_clocken0_b)))
							begin
                                if(operation_mode == "QUAD_PORT")
                                    temp_wb = mem_data[i_address_reg_b2];
                                else
                                    temp_wb = mem_data[i_address_reg_b];
				    temp_ecc_b = ecc_data[i_address_reg_b];
							end
						end

                        if (is_write_on_positive_edge == 1)
                        begin
                            if ((dual_port_addreg_b_clk0 == 1) ||								//SIMPLE DUAL PORT same clock
                                (is_bidir_and_wrcontrol_addb_clk0 == 1) || 						//TRUE DUAL PORT same clock
								(same_clock_pulse0 && same_clock_pulse1))						//Different clock source, same pulse
                            begin
                                // A write, B read
                                if ((i_wren_reg_a & ~i_wren_reg_b) && (i_core_clocken_a) && (i_data_write_time_a == $time))
                                begin
                                    // if A write to the same Ram address B is reading from
				    if (operation_mode == "QUAD_PORT") 
				    begin
                                    	if (i_address_reg_b2 == i_address_reg_a) 
					begin					
                                        	if (cread_during_write_mode_mixed_ports == "NEW_A_OLD_B" && (mem_data[i_address_reg_b2] === ((i_data_reg_a & i_byteena_mask_reg_a) | (mem_data[i_address_reg_a2] & ~i_byteena_mask_reg_a) ^ i_byteena_mask_reg_a_x)))
                                                begin
							temp_wb = i_original_data_a;
						end
                                        	else//DONT_CARE
						begin
                                                	temp_wb = mem_data[i_address_reg_b2] ^ i_byteena_mask_reg_a_out_b;
                                        	end
					end
                                    end
                                    else begin
                                        if (i_address_reg_b == i_address_reg_a)
                                        begin
                                            if (lutram_dual_port_fast_read == 1)
                                                temp_wb = (i_data_reg_a & i_byteena_mask_reg_a) | (i_q_tmp2_a & ~i_byteena_mask_reg_a) ^ i_byteena_mask_reg_a_x;
                                            else
                                                if (cread_during_write_mode_mixed_ports == "OLD_DATA" &&
                                                    (mem_data[i_address_reg_b] === ((i_data_reg_a & i_byteena_mask_reg_a) | (mem_data[i_address_reg_a] & ~i_byteena_mask_reg_a) ^ i_byteena_mask_reg_a_x)))
                                                        temp_wb = i_original_data_a;
                                                else//DONT_CARE
						begin
                                                    temp_wb = mem_data[i_address_reg_b] ^ i_byteena_mask_reg_a_out_b;
                                                    temp_ecc_b = 2'b00;
						end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    else //!! width_a != width_b
                    begin
                        if(operation_mode == "QUAD_PORT")
                            j2 = i_address_reg_b2 * width_b;
                        else
                            j2 = i_address_reg_b * width_b;
                            
                        for (i5=0; i5<width_b; i5=i5+1)
                        begin
                            j2_plus_i5 = j2 + i5;
                            temp_wa2b = mem_data[j2_plus_i5 / width_a];
                            temp_wb[i5] = temp_wa2b[j2_plus_i5 % width_a];
                        end
                        
                        if (i_wren_reg_b && ((is_bidir_and_wrcontrol_addb_clk0 && i_core_clocken0_b) || 
                            (is_bidir_and_wrcontrol_addb_clk1 && i_core_clocken1_b)))
                        begin
                            if (read_during_write_mode_port_b == "NEW_DATA_NO_NBE_READ")
                                temp_wb = i_data_reg_b ^ i_byteena_mask_reg_b_out;
			  //  else if (cread_during_write_mode_mixed_ports == "NEW_A_OLD_B")												
			//	temp_wb = i_original_data_b;									
			    //No longer support "NEW_DATA_WITH_NBE_READ" and "OLD_DATA" for same port read during write
                            else 
                                temp_wb = {width_b{1'bx}};
                        end

                        if (is_write_on_positive_edge == 1)
                        begin
                            if (((address_reg_b == "CLOCK0") & dual_port_addreg_b_clk0) ||						//SIMPLE DUAL PORT same clock
                                ((wrcontrol_wraddress_reg_b == "CLOCK0") & is_bidir_and_wrcontrol_addb_clk0) || //TRUE DUAL PORT same clock
								(same_clock_pulse0 && same_clock_pulse1))										//Different clock source, same pulse
                            begin
                                // A write, B read
                                if ((i_wren_reg_a & ~i_wren_reg_b) && (i_core_clocken_a) && (i_data_write_time_a == $time))
                                begin
                                    for (i5=0; i5<width_b; i5=i5+1)
                                    begin
                                        j2_plus_i5 = j2 + i5;
                                        j2_plus_i5_div_a = j2_plus_i5 / width_a;
                                        
                                        // if A write to the same Ram address B is reading from
                                        if (j2_plus_i5_div_a == i_address_reg_a)
                                        begin
											//Removed, Lutram doesn't support mixed port width
                                            if(i_data_write_time_a == $time) 
                                            begin
                                                if (cread_during_write_mode_mixed_ports == "OLD_DATA")
                                                    temp_wa2b = i_original_data_a;
                                                else
                                                begin
                                                    temp_wa2b = mem_data[j2_plus_i5_div_a];
                                                    temp_wa2b = temp_wa2b ^ i_byteena_mask_reg_a_out_b;
                                                end
                                            end
                                            else
                                            begin
                                                temp_wa2b = i_original_data_a;
                                            end
                                                
                                            temp_wb[i5] = temp_wa2b[j2_plus_i5 % width_a];
                                        end
                                            
                                    end
                                end
                            end
                        end
                    end 
                    //end of width_a != width_b
                    
                    i_q_tmp2_b = temp_wb;
                    i_q_tmp2_ecc_b = temp_ecc_b;
		    i_rden_reg_b_bypass = 1'b0;
                end
                
                if ((is_lutram == 1) && i_address_aclr_b && (i_address_aclr_family_b == 0) && (operation_mode == "DUAL_PORT"))
                begin
                    for (init_i = 0; init_i < width_b; init_i = init_i + 1)
                    begin
                        init_temp = mem_data[init_i / width_a];
                        i_q_tmp_b[init_i] = init_temp[init_i % width_a];
                        i_q_tmp2_b[init_i] = init_temp[init_i % width_a];
                    end
                end
                else if ((is_lutram == 1) && (operation_mode == "DUAL_PORT"))
                begin
                    j2 = i_address_reg_b * width_b;

                    for (i5=0; i5<width_b; i5=i5+1)
                    begin
                        j2_plus_i5 = j2 + i5;
                        temp_wa2b = mem_data[j2_plus_i5 / width_a];
                        i_q_tmp2_b[i5] = temp_wa2b[j2_plus_i5 % width_a];
                    end
                end
                
                if ((i_outdata_aclr_b || i_force_reread_b || i_outdata_sclr_b_reg ) && 
                    (is_lutram != 1) &&
                    (outdata_reg_b != "CLOCK0") && (outdata_reg_b != "CLOCK1"))
		begin
                    i_q_tmp2_b = {width_b{1'b0}};
		    i_q_tmp2_ecc_b =  {width_eccstatus{1'b0}};
		end
            end //!! end good_to_go_b
        end
    end


    // assigning the correct output values for i_q_tmp_b (non-registered output)
    always @(i_q_tmp2_b or i_q_tmp2_ecc_b or i_wren_reg_b or i_data_reg_b or i_address_aclr_b or
                 i_out_addr_b or i_byteena_mask_reg_b_out or i_rden_reg_b or
                 i_numwords_b or i_outdata_aclr_b  or i_outdata_sclr_b_reg or i_force_reread_b_signal)
    begin
        if (i_out_addr_b >= i_numwords_b)
        begin
            if (i_wren_reg_b && ((i_core_clocken0_b && (is_bidir_and_wrcontrol_addb_clk0 == 1)) || (i_core_clocken1_b && (is_bidir_and_wrcontrol_addb_clk1 == 1))))
            begin   
		i_q_tmp_b <= i_q_tmp2_b;
		i_q_tmp_ecc_b <= i_q_tmp2_ecc_b;
	    end
            else
                i_q_tmp_b <= {width_b{1'bx}};
            if (i_rden_reg_b == 1)
            begin
                $display("Warning : Address pointed at port B is out of bound!");
                $display("Time: %0t  Instance: %m", $time);
            end
        end
        else
            if ((operation_mode == "BIDIR_DUAL_PORT") || (operation_mode == "QUAD_PORT"))
            begin
            
                if (i_outdata_aclr_b_prev && ~ i_outdata_aclr_b && (is_lutram != 1))
                begin
                    i_outdata_aclr_b_prev <= i_outdata_aclr_b;
                    i_force_reread_b <= 1;
                end
                else if (i_outdata_sclr_b_prev && ~ i_outdata_sclr_b_reg && (is_lutram != 1))
                begin
                    i_outdata_sclr_b_prev <= i_outdata_sclr_b_reg;
                    i_force_reread_b <= 1;
                end
                else
                begin
			if( i_force_reread_b == 0)
				i_q_tmp_b <= i_q_tmp2_b;
                end               
            end
            else if (operation_mode == "DUAL_PORT")
            begin

                if (i_outdata_aclr_b_prev && ~ i_outdata_aclr_b && (is_lutram != 1))
                begin
                    i_outdata_aclr_b_prev <= i_outdata_aclr_b;
                    i_force_reread_b <= 1;
                end
                else if (i_outdata_sclr_b_prev && ~ i_outdata_sclr_b_reg && (is_lutram != 1))
                begin
                    i_outdata_sclr_b_prev <= i_outdata_sclr_b_reg;
                    i_force_reread_b <= 1;
                end
                else if (~i_address_aclr_b_prev && i_address_aclr_b && (i_address_aclr_family_b == 0) && s3_address_aclr_b)
                begin
                    if (i_rden_reg_b)
                        i_q_tmp_b <= {width_b{1'bx}};
                    i_force_reread_b1 <= 1;
                end
                else if ((i_force_reread_b1 == 0) && !(i_address_aclr_b_prev && ~i_address_aclr_b && (i_address_aclr_family_b == 0) && s3_address_aclr_b)) //!! SPR 268781: exclude possibility of falling address_aclr
                begin
                //!! OLD_DATA mode is not supported for unregistered data outputs.
		//!! We allow it only for SV and newer device families because of the full
		//!! cycle of delay between the write operation and the output registers.
                if ((is_lutram == 1) && (is_write_on_positive_edge) && (cread_during_write_mode_mixed_ports == "OLD_DATA") && (width_a == width_b) && (i_address_reg_a == i_address_reg_b) && i_wren_reg_a && i_rden_reg_b)
                    i_q_tmp_b <= i_original_data_a;
		else
                    i_q_tmp_b <= i_q_tmp2_b;
                    i_q_tmp_ecc_b <= i_q_tmp2_ecc_b;
                end
            end
        
        if ((i_outdata_aclr_b) && (s3_address_aclr_b))
        begin
            i_q_tmp_b <= {width_b{1'b0}};
	    i_q_tmp_ecc_b <= {width_b{1'b0}};
            i_outdata_aclr_b_prev <= i_outdata_aclr_b;
        end

 	if ((i_outdata_sclr_b) && (s3_address_aclr_b))
        begin
	    if (i_outdata_clken_b)
	    begin
		i_q_tmp_b <= {width_b{1'b0}};
		i_q_tmp_ecc_b <= {width_b{1'b0}};
	    end
	end
	if (enable_force_to_zero == "TRUE" && ~i_rden_reg_b)
	begin
	    i_q_tmp_b <=0;
	    i_q_tmp_ecc_b <= 0;
	end			
        i_address_aclr_b_prev <= i_address_aclr_b;
    end

    //!! SimQoR: Replace intermediate clock signal by generate-if statements
    //!! output latch for lutram (only used when read_during_write_mode_mixed_ports == "OLD_DATA")
    generate if (outdata_reg_b == "CLOCK1")
        begin: clk1_on_outb_fall_gen
            always @(negedge clock1)
            begin
                if (i_core_clocken_a)
		begin
                    if ((width_a == width_b) && (i_out_addr_a == i_out_addr_b) && i_wren_reg_a && i_rden_reg_b)
		    begin
                        i_q_output_latch <= i_original_data_a;
			i_q_output_latch_ecc <= i_original_data_a;
		    end
	            else
		    begin
                        i_q_output_latch <= i_q_tmp2_b;
			i_q_output_latch_ecc <= i_q_tmp2_ecc_b;
		   end
                end
	    end
        end
        else if (outdata_reg_b == "CLOCK0")
        begin: clk0_on_outb_fall_gen
            always @(negedge clock0)
            begin
                if (i_core_clocken_a)
		begin
                    if ((width_a == width_b) && (i_out_addr_a == i_out_addr_b) && i_wren_reg_a && i_rden_reg_b)
		    begin
                        i_q_output_latch <= i_original_data_a;
			i_q_output_latch_ecc <= i_original_data_a;
		    end
	            else
		    begin
                        i_q_output_latch <= i_q_tmp2_b;
			i_q_output_latch_ecc <= i_q_tmp2_ecc_b;
		    end
                end
            end
        end
    endgenerate

    //!! SimQoR: Replace intermediate clock signal by generate-if statements
    // Port B outdata output registered
    generate if (outdata_reg_b == "CLOCK1")
        begin: clk1_on_outb_rise_gen
            always @(posedge clock1 or posedge i_outdata_aclr_b)
            begin
                if (i_outdata_aclr_b)
		begin
                    i_q_reg_b <= 0;
		    i_q_reg_ecc_b <= 0;
		end
                else if (i_outdata_clken_b)
                begin
                    if ((i_address_aclr_b_flag == 1) && (is_lutram != 1))
                        i_q_reg_b <= 'bx;
		    else if (i_outdata_sclr_b)
		    begin
                        i_q_reg_b <= 0;
			i_q_reg_ecc_b <= 0;
		    end
		    else if (enable_force_to_zero == "TRUE" && ~i_rden_reg_b)
		    begin
			i_q_reg_b <= 0;
			i_q_reg_ecc_b <= 0;
		    end
                    else
		    begin
                    	i_q_reg_b <= i_q_tmp_b;
		    	i_q_reg_ecc_b <= i_q_tmp_ecc_b;
		    end
                end
            end
        end
        else if (outdata_reg_b == "CLOCK0")
        begin: clk0_on_outb_rise_gen
            always @(posedge clock0 or posedge i_outdata_aclr_b)
            begin
                if (i_outdata_aclr_b )
		begin
                    i_q_reg_b <= 0;
		    i_q_reg_ecc_b <= 0;
		end			
                else if (i_outdata_clken_b)
                begin
                    if ((is_lutram == 1) && (cread_during_write_mode_mixed_ports == "OLD_DATA"))
                        i_q_reg_b <= i_q_output_latch;
                    else if (i_outdata_sclr_b)
		    begin
                        i_q_reg_b <= 0; 
			i_q_reg_ecc_b <= 0; 
		    end   
		    else if (enable_force_to_zero == "TRUE" && ~i_rden_reg_b)
		    begin
			i_q_reg_b <=0;
			i_q_reg_ecc_b <= 0;
		    end						
                    else
                    begin           
                        if ((i_address_aclr_b_flag == 1) && (is_lutram != 1))
                            i_q_reg_b <= 'bx;
                        else
			begin
                            i_q_reg_b <= i_q_tmp2_b;
			    i_q_reg_ecc_b <= i_q_tmp2_ecc_b;
			end
                    end
                end             
            end
        end
    endgenerate

	generate if (outdata_reg_b == "CLOCK0" && ecc_pipeline_stage_enabled == "TRUE")
	begin: clk0_on_ecc_pipeline_reg_rise_gen
		 always @(posedge clock0 or posedge i_outdata_aclr_b)
		begin
			if (i_outdata_aclr_b)
			begin
				i_q_ecc_reg_b <= 0;
				i_q_ecc_status_reg_b <= 0;
			end
			else if (enable_force_to_zero == "TRUE" && ~i_rden_reg_b)
			begin
				i_q_reg_b <= 0;
				i_q_ecc_reg_b <= i_q_reg_b;
				i_q_reg_ecc_b <= 0;
				i_q_ecc_status_reg_b <= i_q_reg_ecc_b;
			end
			else if (i_outdata_clken_b)
			begin
				if (i_outdata_sclr_b)
				begin
					i_q_ecc_reg_b <= 0;
					i_q_ecc_status_reg_b <= 0;
				end
				else
				begin 
					i_q_ecc_reg_b <= i_q_reg_b;
					i_q_ecc_status_reg_b <= i_q_reg_ecc_b;
				end
			end
		end
	end
	else if (outdata_reg_b == "CLOCK1" && ecc_pipeline_stage_enabled == "TRUE")
	begin: clk1_on_ecc_pipeline_reg_rise_gen
		always @(posedge clock1 or posedge i_outdata_aclr_b)
		begin
			if (i_outdata_aclr_b)
			begin
				i_q_ecc_reg_b <= 0;
				i_q_ecc_status_reg_b <= 0;
			end
			else if (enable_force_to_zero == "TRUE" && ~i_rden_reg_b)
			begin
				i_q_reg_b <= 0;
				i_q_ecc_reg_b <= i_q_reg_b;
				i_q_reg_ecc_b <= 0;
				i_q_ecc_status_reg_b <= i_q_reg_ecc_b;
			end
			else if (i_outdata_clken_b)
			begin
				if (i_outdata_sclr_b) 
				begin
					i_q_ecc_reg_b <= 0;
					i_q_ecc_status_reg_b <= 0;
				end
				else
				begin 
					i_q_ecc_reg_b <= i_q_reg_b;
                                	i_q_ecc_status_reg_b <= i_q_reg_ecc_b;
				end
			end
		end
	end
	endgenerate
	
    //Coherent Read Module
    wire fwd_logic_flag;
    wire [width_a - 1 : 0] fwd_logic_output;
	
wire dataout_b_clear   = (i_outdata_aclr_b || i_outdata_sclr_b)? 1'b1 : 1'b0;

    generate if (enable_coherent_read == "TRUE")
    begin: coherent_read_gen
    altera_syncram_forwarding_logic forwarding_logic (
    .wrdata_reg(i_data_reg_a),
    .wren(wren_a_dly),
	.rden(rden_b_dly),
    .wraddr(address_a),
	.rdaddr(address_b),
	.clr (dataout_b_clear),
	.ena(i_outdata_clken_b), 
    .wren_reg(i_wren_reg_a),
	.rden_reg(i_rden_reg_b),
    .wraddr_reg(i_address_reg_a),
    .rdaddr_reg(i_address_reg_b),
    .clock(clock0), //temporary put it as clock0 but should need pulse to allocate delay
    .fwd_out(fwd_logic_output),
    .stage2_cmp_out(fwd_logic_flag)
     );
    
	defparam forwarding_logic.enable_force_to_zero = enable_force_to_zero;
    defparam forwarding_logic.dwidth = width_a;
    defparam forwarding_logic.awidth = widthad_a;
    defparam forwarding_logic.fwd_stage1_enabled = (enable_coherent_read == "TRUE" && outdata_reg_b == "UNREGISTERED")? 1 : 0;

    end
    endgenerate
    
    // Latch for address aclr till outclock enabled
    always @(posedge i_address_aclr_b or posedge i_outdata_aclr_b)
        if (i_outdata_aclr_b)
            i_address_aclr_b_flag <= 0;
        else
        begin
            if (i_rden_reg_b)
                i_address_aclr_b_flag <= 1;
        end

    //Output for Coherent Read
   // wire forward_logic_sel = (enable_coherent_read == "TRUE")? fwd_logic_flag : 1'b0;
    wire forward_logic_sel = (enable_coherent_read == "TRUE" && fwd_logic_flag == 1'b1)? 1'b1 : 1'b0;

    // Port B : assigning the correct output values for q_b
    assign q_b = ((operation_mode == "SINGLE_PORT") ||
                    (operation_mode == "ROM")) ?
                        {width_b{1'b0}} : ((forward_logic_sel == 1'b1)? fwd_logic_output : 
                        (((outdata_reg_b == "CLOCK0") || (outdata_reg_b == "CLOCK1")) ?
							((ecc_pipeline_stage_enabled == "TRUE")?(i_q_ecc_reg_b) : (i_q_reg_b)):
							((ecc_pipeline_stage_enabled == "TRUE")?(i_q_ecc_tmp_b) : (i_q_tmp_b)))); //i_q_ecc_tmp_b has 'x' output

    assign eccstatus = (((outdata_reg_b == "CLOCK0") || (outdata_reg_b == "CLOCK1")) ?
							((ecc_pipeline_stage_enabled == "TRUE")?(i_q_ecc_status_reg_b) : (i_q_reg_ecc_b)):
							((ecc_pipeline_stage_enabled == "TRUE")?(i_q_ecc_status_tmp_b) : (i_q_tmp_ecc_b)));


endmodule // ALTERA_SYNCRAM

module altera_syncram_forwarding_logic (
                                    wrdata_reg,
                                    wren,
									rden,
                                    wraddr,
									rdaddr,
									clr,
									ena,
                                    wren_reg,
									rden_reg,
                                    wraddr_reg,
                                    rdaddr_reg,
                                    clock,
                                    fwd_out,
                                    stage2_cmp_out
                                   );


parameter dwidth = 1;
parameter awidth = 1;
parameter fwd_stage1_enabled = 0;
parameter enable_force_to_zero = "FALSE";

output  [dwidth - 1 : 0]    fwd_out;
output                      stage2_cmp_out;
input   [dwidth - 1 : 0]    wrdata_reg;
input                       clock;
input                       wren;
input                       wren_reg;
input 			    rden;
input			    rden_reg;
input						clr;
input						ena;
input   [awidth - 1 : 0]    wraddr;
input   [awidth - 1 : 0]    rdaddr;
input   [awidth - 1 : 0]    wraddr_reg;
input   [awidth - 1 : 0]    rdaddr_reg;


wire    stage1_cohr_chk;
wire    stage2_cohr_chk;
reg     stage1_cohr_chk_1;
wire    [dwidth - 1 : 0] stage1_mux_out;
reg     stage1_cmp_reg;
reg     stage2_cmp_reg;
reg     [dwidth - 1 : 0]    fwd_data_reg;

initial begin
    stage1_cmp_reg  = 'b0;
    stage2_cmp_reg  = 'b0;
    fwd_data_reg    = 'b0;
end
//stage-1 comparator
    assign stage1_cohr_chk  = (wraddr == rdaddr_reg ) ? wren : 1'b0;
    assign stage1_mux_out   = (fwd_stage1_enabled ) ? wrdata_reg : ((stage1_cmp_reg )? wrdata_reg :  fwd_data_reg);

//stage-2 comparator    
    assign stage2_cohr_chk  = (stage1_cohr_chk )? 1'b1 : ((wraddr_reg == rdaddr_reg ) ? wren_reg : 1'b0);

///output
	assign stage2_cmp_out   = (rden_reg )? (fwd_stage1_enabled )? stage1_cmp_reg  : stage2_cmp_reg : 1'b0;
    assign fwd_out          = stage1_mux_out;

always @ (posedge clock) begin
    //reset?
	if (rden_reg == 1'b1)
	begin
	if (ena == 1'b1)
	begin
			stage1_cmp_reg  =  stage1_cohr_chk;
			stage2_cmp_reg  =  stage2_cohr_chk;
			fwd_data_reg    =  wrdata_reg;
		end
	end
	if (rden_reg == 1'b0 && enable_force_to_zero == "TRUE")
	begin
		if (ena == 1'b1)
		begin
			stage1_cmp_reg  =  1'b0;
			stage2_cmp_reg  =  1'b0;
		fwd_data_reg    = wrdata_reg;
		end
	end
	
// Case:405332 Mimic silicon behavioural whereby clear (sclr and aclr) would not hold forwarding data	
	if (clr ==1'b1)
	begin
			stage1_cmp_reg  =  1'b0;
			stage2_cmp_reg  =  1'b0;
	end
	
end

endmodule// END OF ALTERA_SYNCRAM_FORWARDING_LOGIC

// BEGINNING OF MODULE

`define TRUE 1 
`define FALSE 0 
`define NULL 0
`define EOF -1
`define MAX_BUFFER_SZ   2048
`define MAX_NAME_SZ     256
`define MAX_WIDTH       1024
`define COLON           ":"
`define DOT             "."
`define NEWLINE         "\n"
`define CARRIAGE_RETURN  8'h0D
`define SPACE           " "
`define TAB             "\t"
`define OPEN_BRACKET    "["
`define CLOSE_BRACKET   "]"
`define OFFSET          9
`define H10             8'h10
`define H10000          20'h10000
`define AWORD           8
`define MASK15          32'h000000FF
`define EXT_STR         "ver"
`define PERCENT         "%"
`define MINUS           "-"
`define SEMICOLON       ";"
`define EQUAL           "="

// MODULE DECLARATION
module ALTERA_LNSIM_MEMORY_INITIALIZATION;

/****************************************************************/
/* convert uppercase character values to lowercase.             */
/****************************************************************/
function [8:1] tolower;
    input [8:1] given_character;
    reg [8:1] conv_char;

begin
    if ((given_character >= 65) && (given_character <= 90)) // ASCII number of 'A' is 65, 'Z' is 90
    begin
        conv_char = given_character + 32; // 32 is the difference in the position of 'A' and 'a' in the ASCII char set
        tolower = conv_char;
    end
    else
        tolower = given_character;    
end
endfunction
  
/****************************************************************/
/* function for ecc parity                                      */
/****************************************************************/
function [7:0] ecc_parity;
    input [7:0] i_eccencparity;
    integer pointer,pointer_max,pointer_min,flag_err,flag,flag_double,flag_triple,flag_single,flag_no_err ,flag_uncorr; 
    integer n;
    integer err,found ;
    integer found_2;
begin
    pointer=0;
    pointer_max=0;
    pointer_min=0;
    flag_err=0;
    flag=0;
    flag_double=0;
    flag_triple=0;
    flag_single=0;
    flag_no_err =0;
    flag_uncorr=0;
    err=0;
    found=0;
    found_2=0;

		for (n = 0 ; n<8 ;n=n+1)
		begin
			if (i_eccencparity[n] == 'b1 && found == 0 )
			begin
				pointer_min = n;
				found = 1;
			end	 
		end

		for (n = 7 ; n>=0 ;n=n-1)
		begin
			if (i_eccencparity[n] == 'b1 && found_2 == 0)
			begin
				pointer_max = n;
				found_2 = 1;
			end	 
		end

		pointer = pointer_max - pointer_min ;

		if (i_eccencparity == 8'h0) 
		begin
			flag_no_err =1;
			ecc_parity = 2'b00;
		end

		else if (pointer == 0)
		begin
			flag_single =1;
			ecc_parity = 2'b10;
		end 

		else if (pointer == 1)
		begin
			flag_double =1;
			ecc_parity = 2'b10;
		end 

		else if (pointer == 2)
		begin
			flag_triple =1;
			ecc_parity = 2'b10;
		end 
		
		else if (pointer > 2)
		begin
			flag_uncorr =1;
			ecc_parity = 2'b11;
		end
end//function
endfunction
  
/****************************************************************/
/* Read in Altera-mif format data to verilog format data.       */
/****************************************************************/
task convert_mif2ver;
    input[`MAX_NAME_SZ*8 : 1] in_file;
    input width;
    output [`MAX_NAME_SZ*8 : 1] out_file;
    reg [`MAX_NAME_SZ*8 : 1] in_file;
    reg [`MAX_NAME_SZ*8 : 1] out_file;
    reg [`MAX_NAME_SZ*8 : 1] buffer;
    reg [`MAX_WIDTH : 0] memory_data1, memory_data2;
    reg [8 : 1] c;
    reg [3 : 0] hex, tmp_char;
    reg [24 : 1] address_radix, data_radix;
    reg get_width;
    reg get_depth;
    reg get_data_radix;
    reg get_address_radix;
    reg width_found;
    reg depth_found;
    reg data_radix_found;
    reg address_radix_found;
    reg get_address_data_pairs;
    reg get_address;
    reg get_data;
    reg display_address;
    reg invalid_address;
    reg get_start_address;
    reg get_end_address;
    reg done;
    reg error_status;
    reg first_rec;
    reg last_rec;

    integer width;
    integer memory_width, memory_depth;
    integer value;
    integer ifp, ofp, r, r2;
    integer i, j, k, m, n;
    integer negative;
    integer off_addr, nn, address, tt, cc, aah, aal, dd, sum ;
    integer start_address, end_address;
    integer line_no;
    integer character_count;
    integer comment_with_percent_found;
    integer comment_with_double_minus_found;

begin
        done = `FALSE;
        error_status = `FALSE;
        first_rec = `FALSE;
        last_rec = `FALSE;
        comment_with_percent_found = `FALSE;
        comment_with_double_minus_found = `FALSE;

        off_addr= 0;
        nn= 0;
        address = 0;
        start_address = 0;
        end_address = 0;
        tt= 0;
        cc= 0;
        aah= 0;
        aal= 0;
        dd= 0;
        sum = 0;
        line_no = 1;
        c = 0;
        hex = 0;
        value = 0;
        buffer = "";
        character_count = 0;
        memory_width = 0;
        memory_depth = 0;
        memory_data1 = {(`MAX_WIDTH+1) {1'b0}};
        memory_data2 = {(`MAX_WIDTH+1) {1'b0}};
        address_radix = "hex";
        data_radix = "hex";
        get_width = `FALSE;
        get_depth = `FALSE;
        get_data_radix = `FALSE;
        get_address_radix = `FALSE;
        width_found = `FALSE;
        depth_found = `FALSE;
        data_radix_found = `FALSE;
        address_radix_found = `FALSE;
        get_address_data_pairs = `FALSE;
        display_address = `FALSE;
        invalid_address = `FALSE;
        get_start_address = `FALSE;
        get_end_address = `FALSE;

        if((in_file[4*8 : 1] == ".dat") || (in_file[4*8 : 1] == ".DAT"))
            out_file = in_file;
        else
        begin
            ifp = $fopen(in_file, "r");

            if (ifp == `NULL)
            begin
//!! coverage_off
                $display("ERROR: cannot read %0s.", in_file);
                done = `TRUE;
//!! coverage_on
            end
        
            out_file = in_file;
            
            if((out_file[4*8 : 1] == ".mif") || (out_file[4*8 : 1] == ".MIF"))
                out_file[3*8 : 1] = `EXT_STR;
            else
            begin
//!! coverage_off
                $display("ERROR: Invalid input file name %0s. Expecting file with .mif extension and Altera-mif data format.", in_file);
                done = `TRUE;
//!! coverage_on
            end

            if (!done)
            begin            
                ofp = $fopen(out_file, "w");

                if (ofp == `NULL)
                begin
//!! coverage_off
                    $display("ERROR : cannot write %0s.", out_file);
                    done = `TRUE;
//!! coverage_on
                end
            end
            
            while((!done) && (!error_status))
            begin : READER
 
                r = $fgetc(ifp);

                if (r == `EOF)
                begin
                // to do : add more checking on whether a particular assigment(width, depth, memory/address) are mising
                    if(!first_rec)
                    begin
                        error_status = `TRUE;
                        $display("WARNING: %0s, Intel-hex data file is empty.", in_file);
                        $display ("Time: %0t  Instance: %m", $time);
                    end
                    else if (!get_address_data_pairs)
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Missing `content begin` statement.", in_file, line_no);
                    end
                    else if(!last_rec)
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Missing `end` statement.", in_file, line_no);
                    end
                    done = `TRUE;
                end
                else if ((r == `NEWLINE) || (r == `CARRIAGE_RETURN))
                begin                    
                    if ((buffer == "contentbegin") && (get_address_data_pairs == `FALSE))
                    begin
                        get_address_data_pairs = `TRUE;
                        get_address = `TRUE;
                        buffer = "";
                    end
                    else if (buffer == "content")
                    begin
                        // continue to next character
                    end
                    else
                    if (buffer != "")
                    begin
                        // found invalid syntax in the particular line.
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid Altera-mif record.", in_file, line_no);
                        disable READER;
                    end
                    line_no = line_no +1;
                    
                end
                else if ((r == `SPACE) || (r == `TAB))
                begin
                    // continue to next character;
                end
                else if (r == `PERCENT)
                begin
                    // Ignore all the characters which which is part of comment.
                    r = $fgetc(ifp);

                    while ((r != `PERCENT) && (r != `NEWLINE) && (r != `CARRIAGE_RETURN))
                    begin
                        r = $fgetc(ifp);                      
                    end

                    if ((r == `NEWLINE) || (r == `CARRIAGE_RETURN))
                    begin
                        line_no = line_no +1;

                        if ((buffer == "contentbegin") && (get_address_data_pairs == `FALSE))
                        begin
                            get_address_data_pairs = `TRUE;
                            get_address = `TRUE;
                            buffer = "";
                        end
                    end
                end
                else if (r == `MINUS)
                begin
                    if(get_data == `TRUE && data_radix == "dec")begin
                        negative = 1;
                    end
                    else begin
                    r = $fgetc(ifp);
                    if (r == `MINUS)
                    begin
                        // Ignore all the characters which which is part of comment.
                        r = $fgetc(ifp);

                        while ((r != `NEWLINE) && (r != `CARRIAGE_RETURN))
                        begin
                            r = $fgetc(ifp);
                            
                        end

                        if ((r == `NEWLINE) || (r == `CARRIAGE_RETURN))
                        begin
                            line_no = line_no +1;

                            if ((buffer == "contentbegin") && (get_address_data_pairs == `FALSE))
                            begin
                                get_address_data_pairs = `TRUE;
                                get_address = `TRUE;
                                buffer = "";
                            end
                        end
                    end
                    else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid Altera-mif record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                    end
                end
                else if (r == `EQUAL)
                begin
                    if (buffer == "width")
                    begin
                        if (width_found == `FALSE)
                        begin
                            get_width = `TRUE;
                            buffer = "";
                        end
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Width has already been specified once.", in_file, line_no);
                        end
                    end
                    else if (buffer == "depth")
                    begin
                        get_depth = `TRUE;
                        buffer = ""; 
                    end
                    else if (buffer == "data_radix")
                    begin
                        get_data_radix = `TRUE;
                        buffer = "";
                    end
                    else if (buffer == "address_radix")
                    begin
                        get_address_radix = `TRUE;
                        buffer = "";
                    end
                    else
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Unknown setting (%0s).", in_file, line_no, buffer);
                    end
                end
                else if (r == `COLON)
                begin
                    if (!get_address_data_pairs)
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Missing `content begin` statement.", in_file, line_no);
                    end
                    else if (invalid_address == `TRUE)
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
                    end
                    begin
                        get_address = `FALSE;
                        get_data = `TRUE;
                        display_address = `TRUE;
                        negative = 0;
                    end
                end
                else if (r == `DOT)
                begin
                    r = $fgetc(ifp);
                    if (r == `DOT)
                    begin
                        if (get_start_address == `TRUE)
                        begin
                            start_address = address;
                            address = 0; 
                            get_start_address = `FALSE;
                            get_end_address = `TRUE;
                        end
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid Altera-mif record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                    end
                    else
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid Altera-mif record.", in_file, line_no);
                        done = `TRUE;
                        disable READER;
                    end
                end
                else if (r == `OPEN_BRACKET)
                begin
                    get_start_address = `TRUE;
                end
                else if (r == `CLOSE_BRACKET)
                begin
                    if (get_end_address == `TRUE)
                    begin
                        end_address = address;
                        address = 0; 
                        get_end_address = `FALSE;
                    end
                    else
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid Altera-mif record.", in_file, line_no);
                        done = `TRUE;
                        disable READER;
                    end
                end                
                else if (r == `SEMICOLON)
                begin
                    if (get_width == `TRUE)
                    begin
                        width_found = `TRUE;
                        memory_width = value;
                        value = 0;
                        get_width = `FALSE;
                    end
                    else if (get_depth == `TRUE)
                    begin
                        depth_found = `TRUE;
                        memory_depth = value;
                        value = 0;
                        get_depth = `FALSE;
                    end
                    else if (get_data_radix == `TRUE)
                    begin
                        data_radix_found = `TRUE;
                        get_data_radix = `FALSE;

                        if ((buffer == "bin") || (buffer == "oct") || (buffer == "dec") || (buffer == "uns") ||
                            (buffer == "hex"))
                        begin
                            data_radix = buffer[24 : 1];
                        end
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid assignment (%0s) to data_radix.", in_file, line_no, buffer);
                        end
                        buffer = "";
                    end
                    else if (get_address_radix == `TRUE)
                    begin
                        address_radix_found = `TRUE;
                        get_address_radix = `FALSE;

                        if ((buffer == "bin") || (buffer == "oct") || (buffer == "dec") || (buffer == "uns") ||
                            (buffer == "hex"))
                        begin
                            address_radix = buffer[24 : 1];
                        end
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid assignment (%0s) to address radix.", in_file, line_no, buffer);
                        end
                        buffer = "";
                    end
                    else if (buffer == "end")
                    begin
                        if (get_address_data_pairs == `TRUE)
                        begin
                            last_rec = `TRUE;
                            buffer = "";
                        end
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Missing `content begin` statement.", in_file, line_no);
                        end
                    end
                    else if (get_data == `TRUE)
                    begin
                        get_address = `TRUE;
                        get_data = `FALSE;
                        buffer = "";
                        character_count = 0;
                        
                        if (start_address != end_address)
                        begin
                            for (address = start_address; address <= end_address; address = address+1)
                            begin
                                $fdisplay(ofp,"@%0h", address);
                                if (negative == 1) begin
                                    memory_data1 = memory_data1 * -1;									
                                end
                                for (i = memory_width -1; i >= 0; i = i-1 )
                                begin
                                    hex[(i % 4)] =  memory_data1[i];
                                    
                                    if ((i % 4) == 0)
                                    begin
                                        $fwrite(ofp, "%0h", hex);
                                        hex = 0;
                                    end
                                end
        
                                $fwrite(ofp, "\n");
                            end
                            start_address = 0;
                            end_address = 0;
                            address = 0;
                            hex = 0;
                            memory_data1 = {(`MAX_WIDTH+1) {1'b0}};
                        end
                        else
                        begin
                            if (display_address == `TRUE)
                            begin
                                $fdisplay(ofp,"@%0h", address);
                                display_address = `FALSE;
                            end
                            
                            if (negative == 1) begin
                                memory_data1 = memory_data1 * -1;									
                            end
                            for (i = memory_width -1; i >= 0; i = i-1 )
                            begin
                                hex[(i % 4)] =  memory_data1[i];
                                
                                if ((i % 4) == 0)
                                begin
                                    $fwrite(ofp, "%0h", hex);
                                    hex = 0;
                                end
                            end
    
                            $fwrite(ofp, "\n");                      
                            address = 0;
                            hex = 0;
                            memory_data1 = {(`MAX_WIDTH+1) {1'b0}};
                        end
                    end
                    else
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid assigment.", in_file, line_no);
                    end
                end
                else if ((get_width == `TRUE) || (get_depth == `TRUE))
                begin
                    if ((r >= "0") && (r <= "9"))
                        value = (value * 10) + (r - 'h30);
                    else
                    begin
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid assignment to width/depth.", in_file, line_no);
                    end
                end
                else if (get_address == `TRUE)
                begin
                    if (address_radix == "hex")
                    begin
                        if ((r >= "0") && (r <= "9"))
                            value = (r - 'h30);
                        else if ((r >= "A") && (r <= "F"))
                            value = 10 + (r - 'h41);
                        else if ((r >= "a") && (r <= "f"))
                            value = 10 + (r - 'h61);
                        else
                        begin
                            invalid_address = `TRUE;
                        end
                            
                        address = (address * 16) + value;
                    end
                    else if ((address_radix == "dec"))
                    begin
                        if ((r >= "0") && (r <= "9"))
                            value = (r - 'h30);
                        else
                        begin
                            invalid_address = `TRUE;
                        end
                            
                        address = (address * 10) + value;
                    end
                    else if (address_radix == "uns")
                    begin
                        if ((r >= "0") && (r <= "9"))
                            value = (r - 'h30);
                        else
                        begin
                            invalid_address = `TRUE;
                        end
                            
                        address = (address * 10) + value; 
                    end
                    else if (address_radix == "bin")
                    begin
                        if ((r >= "0") && (r <= "1"))
                            value = (r - 'h30);
                        else
                        begin
                            invalid_address = `TRUE;
                        end
                            
                        address = (address * 2) + value;
                    end
                    else if (address_radix == "oct")
                    begin
                        if ((r >= "0") && (r <= "7"))
                            value = (r - 'h30);
                        else
                        begin
                            invalid_address = `TRUE;
                        end
                            
                        address = (address * 8) + value;
                    end
                    
                    if ((r >= 65) && (r <= 90))
                        c = tolower(r); 
                    else
                        c = r;

                    {tmp_char,buffer} = {buffer, c};                    
                end
                else if (get_data == `TRUE)
                begin                    
                    character_count = character_count +1;

                    if (data_radix == "hex")
                    begin
                        if ((r >= "0") && (r <= "9"))
                            value = (r - 'h30);
                        else if ((r >= "A") && (r <= "F"))
                            value = 10 + (r - 'h41);
                        else if ((r >= "a") && (r <= "f"))
                            value = 10 + (r - 'h61);
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                            
                        memory_data1 = (memory_data1 * 16) + value;
                    end
                    else if ((data_radix == "dec"))
                    begin
                        if ((r >= "0") && (r <= "9"))
                            value = (r - 'h30);
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                            
                        memory_data1 = (memory_data1 * 10) + value;
                    end
                    else if (data_radix == "uns")
                    begin
                        if ((r >= "0") && (r <= "9"))
                            value = (r - 'h30);
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                            
                        memory_data1 = (memory_data1 * 10) + value; 
                    end
                    else if (data_radix == "bin")
                    begin
                        if ((r >= "0") && (r <= "1"))
                            value = (r - 'h30);
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                            
                        memory_data1 = (memory_data1 * 2) + value;
                    end
                    else if (data_radix == "oct")
                    begin
                        if ((r >= "0") && (r <= "7"))
                            value = (r - 'h30);
                        else
                        begin
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
                        end
                            
                        memory_data1 = (memory_data1 * 8) + value;
                    end
                end
                else
                begin
                    first_rec = `TRUE;
                    
                    if ((r >= 65) && (r <= 90))
                        c = tolower(r); 
                    else
                        c = r;

                    {tmp_char,buffer} = {buffer, c};                    
                end
            end
            $fclose(ifp);
            $fclose(ofp);
        end
end
endtask // convert_mif2ver

/****************************************************************/
/* Read in Intel-hex format data to verilog format data.        */
/*  Intel-hex format    :nnaaaaattddddcc                        */
/****************************************************************/
task convert_hex2ver;
    input[`MAX_NAME_SZ*8 : 1] in_file;
    input width;
    output [`MAX_NAME_SZ*8 : 1] out_file;
    reg [`MAX_NAME_SZ*8 : 1] in_file;
    reg [`MAX_NAME_SZ*8 : 1] out_file;
    reg [8:1] c;
    reg [3:0] hex, tmp_char;
    reg done;
    reg error_status;
    reg first_rec;
    reg last_rec;
    reg first_normal_record;
    reg is_word_address_format;

    integer width;
    integer ifp, ofp, r, r2;
    integer i, j, k, m, n;
    
    integer off_addr, nn, aaaa, aaaa_pre, tt, cc, aah, aal, dd, sum ;
    integer line_no;
    integer divide_factor;

begin
        done = `FALSE;
        error_status = `FALSE;
        first_rec = `FALSE;
        last_rec = `FALSE;
        first_normal_record = `TRUE;
        is_word_address_format = `FALSE;
        off_addr= 0;
        nn= 0;
        aaaa= 0;
        aaaa_pre = 0;
        tt= 0;
        cc= 0;
        aah= 0;
        aal= 0;
        dd= 0;
        sum = 0;
        line_no = 1;
        c = 0;
        hex = 0;
        divide_factor = 1;

        if((in_file[4*8 : 1] == ".dat") || (in_file[4*8 : 1] == ".DAT"))
            out_file = in_file;
        else
        begin
            ifp = $fopen(in_file, "r");
            if (ifp == `NULL)
            begin
//!! coverage_off
                $display("ERROR: cannot read %0s.", in_file);
                done = `TRUE;
//!! coverage_on
            end
        
            out_file = in_file;
            
            if((out_file[4*8 : 1] == ".hex") || (out_file[4*8 : 1] == ".HEX"))
                out_file[3*8 : 1] = `EXT_STR;
            else
            begin
//!! coverage_off
                $display("ERROR: Invalid input file name %0s. Expecting file with .hex extension and Intel-hex data format.", in_file);
                done = `TRUE;
//!! coverage_on
            end
            
            if (!done)
            begin            
                ofp = $fopen(out_file, "w");
                if (ofp == `NULL)
                begin
//!! coverage_off
                    $display("ERROR : cannot write %0s.", out_file);
                    done = `TRUE;
//!! coverage_on
                end
            end
            
            while((!done) && (!error_status))
            begin : READER
        
                r = $fgetc(ifp);
        
                if (r == `EOF)
                begin
                    if(!first_rec)
                    begin
//!! coverage_off
                        error_status = `TRUE;
                        $display("WARNING: %0s, Intel-hex data file is empty.", in_file);
                        $display ("Time: %0t  Instance: %m", $time);
//!! coverage_on
                    end
                    else if(!last_rec)
                    begin
//!! coverage_off
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Missing the last record.", in_file, line_no);
//!! coverage_on
                    end
                end
                else if (r == `COLON)
                begin
                    first_rec = `TRUE;
                    nn= 0;
                    aaaa_pre = aaaa;
                    aaaa= 0;
                    tt= 0;
                    cc= 0;
                    aah= 0;
                    aal= 0;
                    dd= 0;
                    sum = 0;
        
                    // get record length bytes
                    for (i = 0; i < 2; i = i+1)
                    begin
                        r = $fgetc(ifp);
                        
                        if ((r >= "0") && (r <= "9"))
                            nn = (nn * 16) + (r - 'h30);
                        else if ((r >= "A") && (r <= "F"))
                            nn = (nn * 16) + 10 + (r - 'h41);
                        else if ((r >= "a") && (r <= "f"))
                            nn = (nn * 16) + 10 + (r - 'h61);
                        else
                        begin
//!! coverage_off
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
//!! coverage_on
                        end
                    end
        
                    // get address bytes
                    for (i = 0; i < 4; i = i+1)
                    begin
                        r = $fgetc(ifp);
                        
                        if ((r >= "0") && (r <= "9"))
                            hex = (r - 'h30);
                        else if ((r >= "A") && (r <= "F"))
                            hex = 10 + (r - 'h41);
                        else if ((r >= "a") && (r <= "f"))
                            hex = 10 + (r - 'h61);
                        else
                        begin
//!! coverage_off
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
//!! coverage_on
                        end
                        
                        aaaa = (aaaa * 16) + hex;
                        
                        if (i < 2)
                            aal = (aal * 16) + hex;
                        else
                            aah = (aah * 16) + hex;
                    end
                    
                    // get record type bytes   
                    for (i = 0; i < 2; i = i+1)
                    begin
                        r = $fgetc(ifp);
                        
                        if ((r >= "0") && (r <= "9"))
                            tt = (tt * 16) + (r - 'h30);
                        else if ((r >= "A") && (r <= "F"))
                            tt = (tt * 16) + 10 + (r - 'h41);
                        else if ((r >= "a") && (r <= "f"))
                            tt = (tt * 16) + 10 + (r - 'h61);
                        else
                        begin
//!! coverage_off
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                            done = `TRUE;
                            disable READER;
//!! coverage_on
                        end
                    end
        
                    if((tt == 2) && (nn != 2) )
                    begin
//!! coverage_off
                        error_status = `TRUE;
                        $display("ERROR: %0s, line %0d, Invalid data record.", in_file, line_no);
//!! coverage_on
                    end
                    else
                    begin
        
                        // get the sum of all the bytes for record length, address and record types
                        sum = nn + aah + aal + tt ; 
                   
                        // check the record type
                        case(tt)
                            // normal_record
                            8'h00 :
                            begin
                                first_rec = `TRUE;
                                i = 0;
                                k = width / `AWORD;
                                if ((width % `AWORD) != 0)
                                    k = k + 1; 
        
                                if ((first_normal_record == `FALSE) &&(aaaa != k))
                                    is_word_address_format = `TRUE;
                                
                                first_normal_record = `FALSE;

                                if ((aaaa == k) && (is_word_address_format == `FALSE))
                                    divide_factor = k;

                                // k = no. of bytes per entry.
                                while (i < nn)
                                begin
                                    $fdisplay(ofp,"@%0h", (aaaa + off_addr)/divide_factor);

                                    for (j = 1; j <= k; j = j +1)
                                    begin
                                        if ((k - j +1) > nn)
                                        begin
                                            for(m = 1; m <= 2; m= m+1)
                                            begin
                                                if((((k-j)*8) + ((3-m)*4) - width) < 4)
                                                    $fwrite(ofp, "0");
                                            end
                                        end
                                        else
                                        begin
                                            // get the data bytes
                                            for(m = 1; m <= 2; m= m+1)
                                            begin                    
                                                r = $fgetc(ifp);
                            
                                                if ((r >= "0") && (r <= "9"))
                                                    hex = (r - 'h30);
                                                else if ((r >= "A") && (r <= "F"))
                                                    hex = 10 + (r - 'h41);
                                                else if ((r >= "a") && (r <= "f"))
                                                    hex = 10 + (r - 'h61);
                                                else
                                                begin
//!! coverage_off
                                                    error_status = `TRUE;
                                                    $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                                                    done = `TRUE;
                                                    disable READER;
//!! coverage_on
                                                end
            
                                                if((((k-j)*8) + ((3-m)*4) - width) < 4)
                                                    $fwrite(ofp, "%h", hex);
                                                dd = (dd * 16) + hex;
            
                                                if(m % 2 == 0)
                                                begin
                                                    sum = sum + dd;
                                                    dd = 0;
                                                end
                                            end
                                        end
                                    end
                                    $fwrite(ofp, "\n");
        
                                    i = i + k;
                                    aaaa = aaaa + 1;
                                end // end of while (i < nn)
                            end
                            // last record
                            8'h01: 
                            begin
                                last_rec = `TRUE;
                                done = `TRUE;
                            end
                            // address base record
                            8'h02:
                            begin
                                off_addr= 0;

                                // get the extended segment address record
                                for(i = 1; i <= (nn*2); i= i+1)
                                begin                    
                                    r = $fgetc(ifp);
                
                                    if ((r >= "0") && (r <= "9"))
                                        hex = (r - 'h30);
                                    else if ((r >= "A") && (r <= "F"))
                                        hex = 10 + (r - 'h41);
                                    else if ((r >= "a") && (r <= "f"))
                                        hex = 10 + (r - 'h61);
                                    else
                                    begin
//!! coverage_off
                                        error_status = `TRUE;
                                        $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                                        done = `TRUE;
                                        disable READER;
//!! coverage_on
                                    end
        
                                    off_addr = (off_addr * `H10) + hex;        
                                    dd = (dd * 16) + hex;
        
                                    if(i % 2 == 0)
                                    begin
                                        sum = sum + dd;
                                        dd = 0;
                                    end
                                end
            
                                off_addr = off_addr * `H10;
                            end
                            // address base record
                            8'h03:
                                // get the start segment address record
                                for(i = 1; i <= (nn*2); i= i+1)
                                begin                    
                                    r = $fgetc(ifp);

                                    if ((r >= "0") && (r <= "9"))
                                        hex = (r - 'h30);
                                    else if ((r >= "A") && (r <= "F"))
                                        hex = 10 + (r - 'h41);
                                    else if ((r >= "a") && (r <= "f"))
                                        hex = 10 + (r - 'h61);
                                    else
                                    begin
//!! coverage_off
                                        error_status = `TRUE;
                                        $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                                        done = `TRUE;
                                        disable READER;
//!! coverage_off
                                    end
                                    dd = (dd * 16) + hex;
        
                                    if(i % 2 == 0)
                                    begin
                                        sum = sum + dd;
                                        dd = 0;
                                    end
                                end
                            // address base record
                            8'h04:
                            begin
                                off_addr= 0;

                                // get the extended linear address record
                                for(i = 1; i <= (nn*2); i= i+1)
                                begin                    
                                    r = $fgetc(ifp);

                                    if ((r >= "0") && (r <= "9"))
                                        hex = (r - 'h30);
                                    else if ((r >= "A") && (r <= "F"))
                                        hex = 10 + (r - 'h41);
                                    else if ((r >= "a") && (r <= "f"))
                                        hex = 10 + (r - 'h61);
                                    else
                                    begin
//!! coverage_off
                                        error_status = `TRUE;
                                        $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                                        done = `TRUE;
                                        disable READER;
//!! coverage_off
                                    end
        
                                    off_addr = (off_addr * `H10) + hex;        
                                    dd = (dd * 16) + hex;
        
                                    if(i % 2 == 0)
                                    begin
                                        sum = sum + dd;
                                        dd = 0;
                                    end
                                end
            
                                off_addr = off_addr * `H10000;
                            end
                            // address base record
                            8'h05:
                                // get the start linear address record
                                for(i = 1; i <= (nn*2); i= i+1)
                                begin                    
                                    r = $fgetc(ifp);

                                    if ((r >= "0") && (r <= "9"))
                                        hex = (r - 'h30);
                                    else if ((r >= "A") && (r <= "F"))
                                        hex = 10 + (r - 'h41);
                                    else if ((r >= "a") && (r <= "f"))
                                        hex = 10 + (r - 'h61);
                                    else
                                    begin
//!! coverage_off
                                        error_status = `TRUE;
                                        $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                                        done = `TRUE;
                                        disable READER;
//!! coverage_off
                                    end
                                    dd = (dd * 16) + hex;
        
                                    if(i % 2 == 0)
                                    begin
                                        sum = sum + dd;
                                        dd = 0;
                                    end
                                end
                            default:
                            begin
//!! coverage_off
                                error_status = `TRUE;
                                $display("ERROR: %0s, line %0d, Unknown record type.", in_file, line_no);
//!! coverage_on
                            end
                        endcase
                        
                        // get the checksum bytes
                        for (i = 0; i < 2; i = i+1)
                        begin
                            r = $fgetc(ifp);
                            
                            if ((r >= "0") && (r <= "9"))
                                cc = (cc * 16) + (r - 'h30);
                            else if ((r >= "A") && (r <= "F"))
                                cc = 10 + (cc * 16) + (r - 'h41);
                            else if ((r >= "a") && (r <= "f"))
                                cc = 10 + (cc * 16) + (r - 'h61);
                            else
                            begin
//!! coverage_off
                                error_status = `TRUE;
                                $display("ERROR: %0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                                done = `TRUE;
                                disable READER;
//!! coverage_on
                            end
                        end
                        
                        // Perform check sum.
                        if(((~sum+1)& `MASK15) != cc)
                        begin
//!! coverage_off
                            error_status = `TRUE;
                            $display("ERROR: %0s, line %0d, Invalid checksum.", in_file, line_no);
//!! coverage_on
                        end
                    end
                end
                else if ((r == `NEWLINE) || (r == `CARRIAGE_RETURN))
                begin
                    line_no = line_no +1;
                end
                else if (r == `SPACE)
                begin
                    // continue to next character;
                end
                else
                begin
//!! coverage_off
                    error_status = `TRUE;
                    $display("ERROR:%0s, line %0d, Invalid INTEL HEX record.", in_file, line_no);
                    done = `TRUE;
//!! coverage_on
                end
            end
            $fclose(ifp);
            $fclose(ofp);
        end
end
endtask // convert_hex2ver

task convert_to_ver_file;
    input[`MAX_NAME_SZ*8 : 1] in_file;
    input width;
    output [`MAX_NAME_SZ*8 : 1] out_file;
    reg [`MAX_NAME_SZ*8 : 1] in_file;
    reg [`MAX_NAME_SZ*8 : 1] out_file;
    integer width;
begin    
           
        if((in_file[4*8 : 1] == ".hex") || (in_file[4*8 : 1] == ".HEX") ||
            (in_file[4*8 : 1] == ".dat") || (in_file[4*8 : 1] == ".DAT"))
            convert_hex2ver(in_file, width, out_file);
        else if((in_file[4*8 : 1] == ".mif") || (in_file[4*8 : 1] == ".MIF"))
            convert_mif2ver(in_file, width, out_file);
        else
//!! coverage_off
            $display("ERROR: Invalid input file name %0s. Expecting file with .hex extension (with Intel-hex data format) or .mif extension (with Altera-mif data format).", in_file);
//!! coverage_on
end
endtask // convert_to_ver_file

endmodule // ALTERA_LNSIM_MEMORY_INITIALIZATION


