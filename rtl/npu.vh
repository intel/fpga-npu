`ifndef _NPU_VH_
`define _NPU_VH_

`define max(a,b) ((a > b) ? a : b)
`define roundup_power2(a) ((2) ** ($clog2(a)))

/***********************************/
/*    USER-SPECIFIED PARAMETERS    */
/***********************************/
`define NTILE     			7			// Number of MVU tiles
`define NDPE      			40  		// Number of dot product engines (DPEs) per tile
`define DOTW      			40			// Number of lanes per DPE
`define VRFD					512			// Vector register file depth
`define MRFD      			512		// Matrix register file depth
`define EW        			8   		// Input bitwidth {8 or 4}
`define ACCW      			32  		// Accumulation/Output bitwidth
`define QDEPTH    			512			// FIFO depth
`define INPUT_BUFFER_SIZE	512
`define OUTPUT_BUFFER_SIZE	512
`define INST_DEPTH			512			// Instruction memory depth
`define RTL_DIR				"/nfs/sc/disks/swuser_work_aboutros/npu_demo/npu-s10-nx/rtl/"	// Directory for RTL source code
`define TILES_THRESHOLD 	8			// Number of tiles implemented using hard DSP blocks
`define DPES_THRESHOLD  	0			// Number of DPEs/tile implemented using hard DSPs
`define TARGET_FPGA			"S10-Prime"		// Target FPGA {"Arria 10" or "Stratix 10" or "S10-Prime"}

/***********************************/
/*    IMPLEMENTATION PARAMETERS    */
/***********************************/
//DO NOT change these parameters unless you really know what you are doing
`define PRIME_DOTW			10
`define DOT_PER_DSP			3
`define NUM_DSP				DOTW / PRIME_DOTW
`define MULT_LATENCY       2 + (NUM_DSP-1)*2
`define DPE_PIPELINE    	MULT_LATENCY
`define VRFIDW					$clog2(NUM_DSP)
`define MRFIDW					$clog2(NUM_DSP*NTILE)
`define NUM_ACCUM				DOT_PER_DSP * NUM_DSP
`define ACCIDW					$clog2(2*NUM_ACCUM)
`define VRFAW     			$clog2(VRFD)
`define MRFAW     			$clog2(MRFD)
`define NMFU      			2
`define NVRF      			NTILE+1+(2*NMFU)
`define NMRF      			NTILE*NDPE
`define NSIZE     			`max(VRFD, MRFD)
`define NSIZEW    			$clog2(NSIZE)+1
`define NTAG      			512
`define NTAGW     			$clog2(NTAG)
`define MIW_MVU				3*VRFAW+2*NSIZEW+MRFAW+NSIZEW+NTAGW+1
`define UIW_MVU   			8+NTAGW+MRFAW+1+VRFIDW+VRFAW
`define MIW_EVRF  			3*VRFAW+NSIZEW+1+NTAGW+3
`define UIW_EVRF  			VRFAW+2+NTAGW
`define MIW_MFU   			6*VRFAW+NSIZEW+NTAGW+9
`define UIW_MFU   			VRFAW+VRFAW+NTAGW+6
`define MIW_LD    			(2*NVRF)+6*VRFAW+NSIZEW+6
`define UIW_LD    			(2*NVRF)+VRFAW+VRFAW+4
`define MICW     				MIW_MVU+MIW_EVRF+(2*MIW_MFU)+MIW_LD
`define WB_LMT    			QDEPTH/2
`define WB_LMTW   			$clog2(WB_LMT)+1
`define SIM_FLAG				0
`define PRECISION				EW
`define BRAM_RD_LATENCY 	2
`define INST_ADDRW			$clog2(INST_DEPTH)
`define CACHELINE_SIZE		512
`define MDATA_SIZE			16
`define ROB_DEPTH				INPUT_BUFFER_SIZE
`define ROB_ADDRW				$clog2(ROB_DEPTH)
`define FILLED_MRFD			26
`define NUM_INPUTS			42
`define NUM_OUTPUTS			39
`define DEPLOY					1

/***********************************/
/* 	      MACRO DEFINITIONS       */
/***********************************/
`define DISPLAY_MVU
`define DISPLAY_MVU_TILE
`define DISPLAY_EVRF
`define DISPLAY_MFU
`define DISPLAY_LD
`define DISPLAY_INST

// NPU Instruction definition
`define mvu_minst(minst_chain)  \
    ``minst_chain``[MIW_LD+(2*MIW_MFU)+MIW_EVRF+:MIW_MVU]
`define evrf_minst(minst_chain) \
    ``minst_chain``[MIW_LD+(2*MIW_MFU)+:MIW_EVRF]
`define mfu0_minst(minst_chain) \
    ``minst_chain``[MIW_LD+MIW_MFU+:MIW_MFU]
`define mfu1_minst(minst_chain) \
    ``minst_chain``[MIW_LD+:MIW_MFU]
`define ld_minst(minst_chain)   \
    ``minst_chain``[0+:MIW_LD]
`define loop_size(minst_chain)   \
    ``minst_chain``[0+:16]

// MVU macro-instruction definition
`define mvu_minst_vrf_base0(minst) \
    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+NSIZEW+2*VRFAW +:VRFAW]
`define mvu_minst_vrf_base1(minst) \
    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+NSIZEW+VRFAW +:VRFAW]
`define mvu_minst_vrf_base2(minst) \
    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+NSIZEW +:VRFAW]
`define mvu_minst_vrf_size(minst) \
    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+:NSIZEW]
`define mvu_minst_mrf_base(minst) \
    ``minst``[1+NTAGW+2*NSIZEW+:MRFAW]
`define mvu_minst_mrf_size(minst) \
    ``minst``[1+NTAGW+NSIZEW+:NSIZEW]
`define mvu_minst_words_per_row(minst) \
    ``minst``[1+NTAGW+:NSIZEW]
`define mvu_minst_tag(minst) \
    ``minst``[1+:NTAGW]
`define mvu_minst_op(minst) \
    ``minst``[0+:1]

// MVU micro-instruction definition
`define mvu_uinst_vrf_addr(uinst) \
	``uinst``[8+NTAGW+MRFAW+1+VRFIDW +:VRFAW]
`define mvu_uinst_vrf_rd_id(uinst) \
	``uinst``[8+NTAGW+MRFAW+1 +:VRFIDW]
`define mvu_uinst_reg_sel(uinst) \
	``uinst``[8+NTAGW+MRFAW +:1]
`define mvu_uinst_mrf_addr(uinst) \
	``uinst``[8+NTAGW +:MRFAW]
`define mvu_uinst_tag(uinst) \
	``uinst``[8+:NTAGW]
`define mvu_uinst_acc_op(uinst)   \
	``uinst``[6+:2]
`define mvu_uinst_acc_size(uinst) \
    ``uinst``[1+:5]
`define mvu_uinst_vrf_en(uinst) \
    ``uinst``[0+:1]

// eVRF macro-instruction definition
`define evrf_minst_vrf_base0(minst) \
    ``minst``[3+NTAGW+1+NSIZEW+2*VRFAW+:VRFAW]
`define evrf_minst_vrf_base1(minst) \
    ``minst``[3+NTAGW+1+NSIZEW+VRFAW+:VRFAW]
`define evrf_minst_vrf_base2(minst) \
    ``minst``[3+NTAGW+1+NSIZEW+:VRFAW]
`define evrf_minst_vrf_size(minst) \
    ``minst``[3+NTAGW+1+:NSIZEW]
`define evrf_minst_src_sel(minst) \
    ``minst``[3+NTAGW+:1]
`define evrf_minst_tag(minst) \
    ``minst``[3+:NTAGW]
`define evrf_minst_op(minst) \
    ``minst``[2+:1]
`define evrf_minst_batch(minst) \
    ``minst``[0+:2]

// eVRF micro-instruction definition
`define evrf_uinst_vrf_addr(uinst) \
    ``uinst``[NTAGW+2+:VRFAW]
`define evrf_uinst_src_sel(uinst)   \
    ``uinst``[NTAGW+:2]
`define evrf_uinst_tag(uinst)   \
    ``uinst``[0+:NTAGW]

//  MFU macro-instruction definition
`define mfu_minst_vrf0_base0(minst) \
    ``minst``[9+NTAGW+NSIZEW+5*VRFAW+:VRFAW]
`define mfu_minst_vrf0_base1(minst) \
    ``minst``[9+NTAGW+NSIZEW+4*VRFAW+:VRFAW]
`define mfu_minst_vrf0_base2(minst) \
    ``minst``[9+NTAGW+NSIZEW+3*VRFAW+:VRFAW]
`define mfu_minst_vrf1_base0(minst) \
    ``minst``[9+NTAGW+NSIZEW+2*VRFAW+:VRFAW]
`define mfu_minst_vrf1_base1(minst) \
    ``minst``[9+NTAGW+NSIZEW+VRFAW+:VRFAW]
`define mfu_minst_vrf1_base2(minst) \
    ``minst``[9+NTAGW+NSIZEW+:VRFAW]
`define mfu_minst_size(minst) \
    ``minst``[9+NTAGW+:NSIZEW]
`define mfu_minst_tag(minst) \
    ``minst``[9+:NTAGW]
`define mfu_minst_op(minst) \
    ``minst``[2+:7]
`define mfu_minst_batch(minst) \
    ``minst``[0+:2]

// MFU micro-instruction definition
`define mfu_uinst_vrf0_addr(uinst) \
    ``uinst``[6+NTAGW+VRFAW+:VRFAW]
`define mfu_uinst_vrf1_addr(uinst) \
    ``uinst``[6+NTAGW+:VRFAW]
`define mfu_uinst_tag(uinst) \
    ``uinst``[6+:NTAGW]
`define mfu_uinst_func_op(uinst) \
    ``uinst``[0+:6]
`define mfu_uinst_act_op(uinst) \
    ``uinst``[4+:2]
`define mfu_uinst_add_op(uinst) \
    ``uinst``[1+:3]
`define mfu_uinst_mul_op(uinst) \
    ``uinst``[0+:1]

// LD macro-instruction definition
`define ld_minst_vrf_id(minst) \
    ``minst``[6+NSIZEW+6*VRFAW+:2*NVRF]
`define ld_minst_vrf0_base0(minst) \
    ``minst``[6+NSIZEW+5*VRFAW+:VRFAW]
`define ld_minst_vrf0_base1(minst) \
    ``minst``[6+NSIZEW+4*VRFAW+:VRFAW]
`define ld_minst_vrf0_base2(minst) \
    ``minst``[6+NSIZEW+3*VRFAW+:VRFAW]
`define ld_minst_vrf1_base0(minst) \
    ``minst``[6+NSIZEW+2*VRFAW+:VRFAW]
`define ld_minst_vrf1_base1(minst) \
    ``minst``[6+NSIZEW+VRFAW+:VRFAW]
`define ld_minst_vrf1_base2(minst) \
    ``minst``[6+NSIZEW+:VRFAW]
`define ld_minst_size(minst) \
    ``minst``[6+:NSIZEW]
`define ld_minst_src_sel(minst) \
    ``minst``[5+:1]
`define ld_minst_op(minst) \
    ``minst``[4+:1]
`define ld_minst_batch(minst) \
    ``minst``[2+:2]
`define ld_minst_interrupt(minst) \
    ``minst``[1+:1]
`define ld_minst_report_to_host(minst) \
	``minst``[0+:1]

// LD micro-instruction definition
`define ld_uinst_vrf_id(uinst) \
    ``uinst``[4+VRFAW+VRFAW+:2*NVRF]
`define ld_uinst_vrf0_addr(uinst) \
    ``uinst``[4+VRFAW+:VRFAW]
`define ld_uinst_vrf1_addr(uinst) \
    ``uinst``[4+:VRFAW]
`define ld_uinst_src_sel(uinst) \
    ``uinst``[3+:1]
`define ld_uinst_last(uinst) \
    ``uinst``[2+:1]
`define ld_uinst_interrupt(uinst) \
    ``uinst``[1+:1]
`define ld_uinst_report_to_host(uinst) \
    ``uinst``[0+:1]

`endif
