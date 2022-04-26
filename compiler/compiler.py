import math
import numpy as np
import warnings
import pickle
import sys
import copy
import subprocess
import os
import threading
import time
import re

from fsim import chain
from fsim import npu_isa_sim

'''
Current Limitations:
--------------------
- The NPU front-end does not have a software implementation of the non-linear activation functions in the MFU.
  The instructions to these units are always set to path-through, but the latency of executing them is always
  accounted for (in simulations) and the hardware lookup tables are implemented on the FPGA.
- The Keras front-end does not pass the actual weights/inputs of specified layers to the NPU performance simulator 
  or the RTL MIF files generation. Synthetic random weights/inputs are generated under the hood to match the NPU
  supported precisions.
- The NPU RTL implements 2 identical cores each operating at batch-3 (total batch-6). However, the front-end and 
  simulator views this as a single core for simplicity. During RTL simulation, both cores are fed the same set of
  inputs, and their outputs are verified against the functional and performance simulator.
- The Keras front-end supports a limited number of layers: Dense, SimpleRNN, GRU, LSTM
'''

'''
The main class in this code is the npu class. It is used to hold all the architecture parameters, architecture states 
(e.g. mrfs, vrfs, input buffer, output buffer, etc.), memory allocation book-keeping, tagging info, fsim class, and 
parameters for instruction field widths as well. 
'''
class npu:
	def __init__(self, arch_params, flow_opts):
		# Architecture parameters and used precisions
		self.arch_params 	= arch_params
		self.flow_opts		= flow_opts
		self.in_data_type	= np.int8
		self.ac_data_type	= np.int32

		# Memory spaces of the NPU and instruction tagging
		self.mem_space = {
			'mvu_vrf' 	: np.zeros(arch_params['vrf_depth'], dtype=int),
			'mvu_mrf' 	: np.zeros(arch_params['mrf_depth'], dtype=int),
			'evrf' 		: np.zeros(arch_params['vrf_depth'], dtype=int),
			'mfu0_add'  	: np.zeros(arch_params['vrf_depth'], dtype=int),
			'mfu0_mul' 	: np.zeros(arch_params['vrf_depth'], dtype=int),
			'mfu1_add' 	: np.zeros(arch_params['vrf_depth'], dtype=int),
			'mfu1_mul' 	: np.zeros(arch_params['vrf_depth'], dtype=int)
		}
		self.highest_tag_so_far = 0
		self.mrf_filled_depth = 0

		# Architecture states
		self.mrfs = np.zeros((self.arch_params['tiles'], self.arch_params['dpes'], self.arch_params['mrf_depth'], self.arch_params['lanes']), dtype=self.in_data_type)
		self.mvu_vrfs   = np.zeros((self.arch_params['tiles'], self.arch_params['vrf_depth'], self.arch_params['lanes']), dtype = self.in_data_type)
		self.ext_vrf = np.zeros((self.arch_params['vrf_depth'], self.arch_params['lanes']),dtype = self.ac_data_type)  
		self.mfu0_vrf0  = np.zeros((self.arch_params['vrf_depth'], self.arch_params['lanes']),dtype = self.ac_data_type)
		self.mfu0_vrf1  = np.zeros((self.arch_params['vrf_depth'], self.arch_params['lanes']),dtype = self.ac_data_type)
		self.mfu1_vrf0  = np.zeros((self.arch_params['vrf_depth'], self.arch_params['lanes']),dtype = self.ac_data_type)
		self.mfu1_vrf1  = np.zeros((self.arch_params['vrf_depth'], self.arch_params['lanes']),dtype = self.ac_data_type)

		# Instruction, input and golden output queues
		self.inst_q = []
		self.ibuf_q = []
		self.golden_obuf_q = []
		self.fsim = None

		# Instruction field width parameters
		self.NTAGW = 0
		self.NSIZEW = 0
		self.MRFAW = 0
		self.VRFAW = 0
		self.NTILE = 0
		self.NVRF = 0
		self.MIW_LD = 0
		self.MIW_MFU = 0
		self.MIW_EVRF = 0
		self.MIW_MVU = 0
		self.MICW = 0
		self.mvu_minst = 0
		self.evrf_minst = 0
		self.mfu0_minst = 0
		self.mfu1_minst = 0
		self.ld_minst = 0
		self.minst_chain = 0

		self.operands = []
		self.unsupported_layers = []
		self.ops = 0

	# This function is used to allocate memory of a specific number of words (size) in a specific memory space.
	# It returns the start address of the allocated memory or -1 if allocation failed.
	def alloc_space(self, space, size):
		alloc_addr = -1
		idx = 0
		assert space in self.mem_space.keys(), 'No such memory space exists'
		space_depth = self.mem_space[space].size

		# Start from address 0 in the specified memory space and look for the first empty contiguous location of the required size
		while (idx < space_depth and alloc_addr == -1):
			assert self.mem_space[space][idx] != -1, 'Something wrong with allocation'
			if (self.mem_space[space][idx] == 0):
				can_allocate = True
				for i in range(1, size):
					if(idx+i >= space_depth):
						can_allocate = False
						idx = space_depth
						break
					if (self.mem_space[space][idx+i] != 0):
						can_allocate = False
						idx = idx + i + self.mem_space[space][idx+i]
						break
				if (can_allocate):
					self.mem_space[space][idx] = size
					for i in range(1, size):
						self.mem_space[space][idx+i] = -1
					alloc_addr = idx
					idx = space_depth
			else:
				idx = idx + self.mem_space[space][idx]

		if(space == 'mvu_mrf'):
			self.mrf_filled_depth += size

		return alloc_addr

	# This function sets all the parameters for instruction field widths based on those specified by the user
	def set_inst_params(self):
		self.NTAGW = int(math.ceil(math.log(self.arch_params['max_tag'], 2)))
		self.NSIZEW = int(math.ceil(math.log(max(self.arch_params['mrf_depth'], self.arch_params['vrf_depth']), 2)) + 1)
		self.MRFAW = int(math.ceil(math.log(self.arch_params['mrf_depth'], 2)))
		self.VRFAW = int(math.ceil(math.log(self.arch_params['vrf_depth'], 2)))
		self.NTILE = int(self.arch_params['tiles'])
		self.NVRF = self.NTILE + 5
		self.MIW_LD = (2*self.NVRF) + (6*self.VRFAW) + self.NSIZEW + 6
		self.MIW_MFU = (6*self.VRFAW) + self.NSIZEW + self.NTAGW + 9
		self.MIW_EVRF = (3*self.VRFAW) + self.NSIZEW + self.NTAGW + 4
		self.MIW_MVU = (3*self.VRFAW) + (3*self.NSIZEW) + self.MRFAW + self.NTAGW + 1
		self.MICW = self.MIW_LD + (2*self.MIW_MFU) + self.MIW_EVRF + self.MIW_MVU
		if(self.flow_opts['verbose']):
			print('NTAGW = ' + str(self.NTAGW))
			print('NSIZEW = ' + str(self.NSIZEW))
			print('MRFAW = ' + str(self.MRFAW))
			print('VRFAW = ' + str(self.VRFAW))
			print('NTILE = ' + str(self.NTILE))
			print('NVRF = ' + str(self.NVRF))
			print('MIW_LD = ' + str(self.MIW_LD))
			print('MIW_MFU = ' + str(self.MIW_MFU))
			print('MIW_EVRF = ' + str(self.MIW_EVRF)) 

	# This function puts together the macro-instructions into one VLIW instruction (chain)
	def set_inst(self,inst):
		self.set_mvu_minst(inst)
		self.set_evrf_minst(inst)
		self.set_mfu0_minst(inst)
		self.set_mfu1_minst(inst)
		self.set_ld_minst(inst)
		self.minst_chain = 0
		shift = 0
		self.minst_chain += (int(self.ld_minst) << shift)
		shift += self.MIW_LD
		self.minst_chain += (int(self.mfu1_minst) << shift)
		shift += self.MIW_MFU
		self.minst_chain += (int(self.mfu0_minst) << shift)
		shift += self.MIW_MFU
		self.minst_chain += (int(self.evrf_minst) << shift)
		shift += self.MIW_EVRF
		self.minst_chain += (int(self.mvu_minst) << shift)

	# This function sets the fields of the MVU macro-instruction
	def set_mvu_minst(self, inst):		
		self.mvu_minst=0
		shift=0
		if inst.mvu_op_type!='nop':
			self.mvu_minst=1
			shift+=1
			self.mvu_minst+=(int(inst.mvu_tag) << shift)
			shift+=self.NTAGW
			self.mvu_minst =(int(inst.mvu_words_per_row) << shift) + self.mvu_minst
			shift+=self.NSIZEW 
			self.mvu_minst+=(int(inst.mvu_mrf_rd_sz) << shift)
			shift+=self.NSIZEW 
			self.mvu_minst+=(int(inst.mvu_mrf_rd_base) << shift)
			shift+=self.MRFAW
			self.mvu_minst+=(int(inst.mvu_vrf_rd_sz) <<shift)
			shift+=self.NSIZEW 
			self.mvu_minst =(int(inst.mvu_vrf_rd_base[2])<<shift) + self.mvu_minst
			shift+=self.VRFAW
			self.mvu_minst =(int(inst.mvu_vrf_rd_base[1])<<shift) + self.mvu_minst
			shift+=self.VRFAW
			self.mvu_minst =(int(inst.mvu_vrf_rd_base[0])<<shift) + self.mvu_minst
			if(self.mvu_minst < 0):
				digits = len(bin(self.mvu_minst)[2:])
				self.mvu_minst = self.mvu_minst + (2**digits)

	# This function sets the fields of the eVRF macro-instruction
	def set_evrf_minst(self, inst):
		self.evrf_minst=0
		shift=0
		if inst.extvrf_op_type!='nop':
			self.evrf_minst+=(int(inst.batch)<<shift)
			shift+=2
			self.evrf_minst+=(0x1<<shift) # MOV
			shift+=1
			self.evrf_minst+=(int(inst.extvrf_tag)<<shift)
			shift+=self.NTAGW
			if inst.extvrf_op_type=='move':
				self.evrf_minst+=(0x0<<shift)
			else:
				self.evrf_minst+=(0x1<<shift)
			shift+=1
			self.evrf_minst+=(int(inst.extvrf_rd_sz)<<shift)
			shift+=self.NSIZEW 
			self.evrf_minst+=(int(inst.extvrf_rd_base[2])<<shift)
			shift+=self.VRFAW
			self.evrf_minst+=(int(inst.extvrf_rd_base[1])<<shift)
			shift+=self.VRFAW
			self.evrf_minst+=(int(inst.extvrf_rd_base[0])<<shift)
			if(self.evrf_minst < 0):
				digits = len(bin(self.evrf_minst)[2:])
				self.evrf_minst = self.evrf_minst + (2**digits)

	# This function sets the fields of the MFU0 macro-instruction
	def set_mfu0_minst(self, inst):
		self.mfu0_minst=0
		shift=0
		if (inst.mfu0_act_op_type!='nop' and inst.mfu0_add_op_type!='nop' and inst.mfu0_mul_op_type!='nop'):
			self.mfu0_minst+=(int(inst.batch)<<shift)
			shift+=2
			self.mfu0_minst+=(0x40<<shift)
			# Activation functions set as pass-through (check limitations listed at the top of this file)
			#if(inst.mfu0_act_op_type=='relu'):
			#    self.mfu0_minst+=(0x10<<shift)
			#elif(inst.mfu0_act_op_type=='sig'):
			#    self.mfu0_minst+=(0x20<<shift)
			#elif(inst.mfu0_act_op_type=='tanh'):
			#    self.mfu0_minst+=(0x30<<shift)

			if(inst.mfu0_add_op_type=='add'):
				self.mfu0_minst+=(0x02<<shift)
			elif(inst.mfu0_add_op_type=='sub_a_b'):
				self.mfu0_minst+=(0x04<<shift)
			elif(inst.mfu0_add_op_type=='sub_b_a'):
				self.mfu0_minst+=(0x06<<shift)
			elif(inst.mfu0_add_op_type=='max'):
				self.mfu0_minst+=(0x08<<shift)

			if(inst.mfu0_mul_op_type=='mul'):
				self.mfu0_minst+=(0x01<<shift)

			shift+=7
			self.mfu0_minst+=(int(inst.mfu0_tag)<<shift)
			shift+=self.NTAGW 
			self.mfu0_minst+=(int(inst.mfu0_vrf_rd_size)<<shift)
			shift+=self.NSIZEW 
			self.mfu0_minst+=(int(inst.mfu0_vrf1_rd_base[2])<<shift)
			shift+=self.VRFAW
			self.mfu0_minst+=(int(inst.mfu0_vrf1_rd_base[1])<<shift)
			shift+=self.VRFAW
			self.mfu0_minst+=(int(inst.mfu0_vrf1_rd_base[0])<<shift)
			shift+=self.VRFAW
			self.mfu0_minst+=(int(inst.mfu0_vrf0_rd_base[2])<<shift)
			shift+=self.VRFAW
			self.mfu0_minst+=(int(inst.mfu0_vrf0_rd_base[1])<<shift)
			shift+=self.VRFAW
			self.mfu0_minst+=(int(inst.mfu0_vrf0_rd_base[0])<<shift)

	# This function sets the fields of the MFU1 macro-instruction
	def set_mfu1_minst(self, inst):
		self.mfu1_minst=0
		shift=0
		if (inst.mfu1_act_op_type!='nop' and inst.mfu1_add_op_type!='nop' and inst.mfu1_mul_op_type!='nop'):
			self.mfu1_minst+=(int(inst.batch)<<shift)
			shift+=2
			self.mfu1_minst+=(0x40<<shift)
			# Activation functions set as pass-through (check limitations listed at the top of this file)
			#if(inst.mfu1_act_op_type=='relu'):
			#    self.mfu1_minst+=(0x10<<shift)
			#elif(inst.mfu1_act_op_type=='sig'):
			#    self.mfu1_minst+=(0x20<<shift)
			#elif(inst.mfu1_act_op_type=='tanh'):
			#    self.mfu1_minst+=(0x30<<shift)

			if(inst.mfu1_add_op_type=='add'):
				self.mfu1_minst+=(0x02<<shift)
			elif(inst.mfu1_add_op_type=='sub_a_b'):
				self.mfu1_minst+=(0x04<<shift)
			elif(inst.mfu1_add_op_type=='sub_b_a'):
				self.mfu1_minst+=(0x06<<shift)
			elif(inst.mfu1_add_op_type=='max'):
				self.mfu1_minst+=(0x08<<shift)

			if(inst.mfu1_mul_op_type=='mul'):
				self.mfu1_minst+=(0x01<<shift)

			shift+=7
			self.mfu1_minst+=(int(inst.mfu1_tag)<<shift)
			shift+=self.NTAGW 
			self.mfu1_minst+=(int(inst.mfu1_vrf_rd_size)<<shift)
			shift+=self.NSIZEW 
			self.mfu1_minst+=(int(inst.mfu1_vrf1_rd_base[2])<<shift)
			shift+=self.VRFAW
			self.mfu1_minst+=(int(inst.mfu1_vrf1_rd_base[1])<<shift)
			shift+=self.VRFAW
			self.mfu1_minst+=(int(inst.mfu1_vrf1_rd_base[0])<<shift)
			shift+=self.VRFAW
			self.mfu1_minst+=(int(inst.mfu1_vrf0_rd_base[2])<<shift)
			shift+=self.VRFAW
			self.mfu1_minst+=(int(inst.mfu1_vrf0_rd_base[1])<<shift)
			shift+=self.VRFAW
			self.mfu1_minst+=(int(inst.mfu1_vrf0_rd_base[0])<<shift)


	# This function sets the fields of the Loader macro-instruction
	def set_ld_minst(self, inst):
		self.ld_minst=0
		shift=0
		if inst.loader_src!='nop':
			self.ld_minst=(int(inst.write_to_obuf)<<shift)
			shift+=1
			self.ld_minst+=(int(inst.last_flag)<<shift)
			shift+=1
			self.ld_minst+=(int(inst.batch)<<shift)
			shift+=2
			self.ld_minst+=(0x1<<shift)
			shift+=1
			if inst.loader_src=='wb':
				self.ld_minst+=(0x1<<shift)
			elif inst.loader_src=='flush':
				self.ld_minst+=(0x1<<shift)
			else:
				self.ld_minst+=(0x0<<shift)
			shift+=1 
			self.ld_minst+=(int(inst.vrf_id0_wr_size)<<shift)
			shift+=self.NSIZEW 
			self.ld_minst+=(int(inst.vrf_id1_wr_base[2])<<shift)
			shift+=self.VRFAW
			self.ld_minst+=(int(inst.vrf_id1_wr_base[1])<<shift)
			shift+=self.VRFAW
			self.ld_minst+=(int(inst.vrf_id1_wr_base[0])<<shift)
			shift+=self.VRFAW
			self.ld_minst+=(int(inst.vrf_id0_wr_base[2])<<shift)
			shift+=self.VRFAW
			self.ld_minst+=(int(inst.vrf_id0_wr_base[1])<<shift)
			shift+=self.VRFAW
			self.ld_minst+=(int(inst.vrf_id0_wr_base[0])<<shift)
			shift+=self.VRFAW
			if(inst.vrf_id0_op=='--'):
				vrf_id=0x0
			elif(inst.vrf_id0_op[0:3]=='mvu'):
				vrf_id=inst.vrf_id0_op.split(".")
				vrf_id=0x1<<(2*int(vrf_id[0][3:]))
			elif(inst.vrf_id0_op=='extvrf'):
				vrf_id=0x1<<(2*self.NTILE)
			elif(inst.vrf_id0_op=='mfu0.vrf0'):
				vrf_id=0x1<<(2*self.NTILE+2)
			elif(inst.vrf_id0_op=='mfu0.vrf1'):
				vrf_id=0x1<<(2*self.NTILE+4)
			elif(inst.vrf_id0_op=='mfu1.vrf0'):
				vrf_id=0x1<<(2*self.NTILE+6)
			elif(inst.vrf_id0_op=='mfu1.vrf1'):
				vrf_id=0x1<<(2*self.NTILE+8)
			else:
				vrf_id=0x0
			self.ld_minst+=vrf_id<<shift

			if(inst.vrf_id1_op=='--'):
				vrf_id=0x0
			elif(inst.vrf_id1_op[0:3]=='mvu'):
				vrf_id=inst.vrf_id1_op.split(".")
				vrf_id=0x3<<(2*int(vrf_id[0][3:]))
			elif(inst.vrf_id1_op=='extvrf'):
				vrf_id=0x3<<(2*self.NTILE)
			elif(inst.vrf_id1_op=='mfu0.vrf0'):
				vrf_id=0x3<<(2*self.NTILE+2)
			elif(inst.vrf_id1_op=='mfu0.vrf1'):
				vrf_id=0x3<<(2*self.NTILE+4)
			elif(inst.vrf_id1_op=='mfu1.vrf0'):
				vrf_id=0x3<<(2*self.NTILE+6)
			elif(inst.vrf_id1_op=='mfu1.vrf1'):
				vrf_id=0x3<<(2*self.NTILE+8)
			else:
				vrf_id=0x0
			self.ld_minst+=vrf_id<<shift

	'''
	This function is used for allocating memory for vectors and matrices depending on the dimensions
	and the memory space specified by the user. It is optional to specify data values for the vector.
	'''
	def malloc(self, name, dimension_x, dimension_y, space_name, values=[]):
		# Make sure user did not enter zero dimensions
		assert dimension_x != 0, 'Invalid X dimension: Dimension cannot be equal to 0'
		assert dimension_y != 0, 'Invalid X dimension: Dimension cannot be equal to 0'
		# Set number of tiles, DPEs, lanes
		tiles = self.arch_params['tiles']
		dpes  = self.arch_params['dpes']
		lanes = self.arch_params['lanes']
		# Make sure the memory space exists
		warnings.simplefilter(action='ignore', category=FutureWarning)
		assert self.mem_space.get(space_name, 'invalid') != 'invalid', 'Specified memory space does not exist'

		if(dimension_y == None):	
			allocated_mem = vector(name, dimension_x, space_name, tiles, dpes, lanes, self.in_data_type, self.ac_data_type, values)
			if (space_name != 'temp'):
				allocated_mem.alloc_addr = self.alloc_space(space_name, allocated_mem.word_count)
				assert allocated_mem.alloc_addr != -1, 'Cannot allocate vector ' + name
		else:
			assert values != [], 'You have to specify matrix data'
			allocated_mem = matrix(name, dimension_x, dimension_y, space_name, tiles, dpes, lanes, self.in_data_type, values)
			allocated_mem.alloc_addr = self.alloc_space(space_name, allocated_mem.word_count)
			assert allocated_mem.alloc_addr != -1, 'Cannot allocate matrix ' + name
			tile_cols = allocated_mem.dimension_x_padded / tiles
			tile_rows = allocated_mem.dimension_y_padded / dpes
			for y in range(allocated_mem.dimension_y_padded):
				for x in range(allocated_mem.dimension_x_padded):
					self.mrfs[int(x / tile_cols)][int(y % dpes)][allocated_mem.alloc_addr + int((x % tile_cols) / lanes) + (int(y / dpes) * int(tile_cols/lanes))][int(x % lanes)] = allocated_mem.data[y][x]

		return allocated_mem

	'''
	This function performs matrix-vector multiplication. Returns a vector data structure.
	vector_in: input vector that resides in the mvu_vrf memory space.
	matrix: persistent matrix that resides in the mvu_mrf memory space.
	'''
	def matvec_mult(self, vectors, matrix, batch=1):
		#Assertions to catch illegal inst order or invalid inputs
		assert self.inst_q, 'An NPU program should start with a load operation'
		for i in range(batch):
			assert vectors[i].space_name == 'mvu_vrf', 'Vector ' + vectors[i].name + ' does not exist in the mvu_vrf memory space'
		tiles = self.arch_params['tiles']
		dpes = self.arch_params['dpes']
		lanes = self.arch_params['lanes']

		#Create a new instruction chain
		tmp = []
		for i in range(batch):
			tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_0', matrix.dimension_y, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
		inst = chain(batch)
		tag = 0
		wb_count = self.inst_q[-1].wb_so_far

		#Get names of all input vectors to search for them in previous instructions
		names = []
		for i in range(batch):
			names.append(vectors[i].name)

		#Calculate the tag for this matvec operation based on the most recently committed vector
		for i in reversed(self.inst_q):
			if(i.results[-1] in names):
				tag = i.wb_so_far
				break
		if (tag > self.highest_tag_so_far):
			self.highest_tag_so_far = tag

		#Fill in the MVU mOP fields
		inst.mvu_mrf_rd_base = matrix.alloc_addr
		inst.mvu_mrf_rd_sz = matrix.word_count
		for i in range(batch):
			inst.mvu_vrf_rd_base[i] = vectors[i].alloc_addr
		inst.mvu_vrf_rd_sz = vectors[0].word_count
		inst.mvu_words_per_row = int(inst.mvu_mrf_rd_sz/inst.mvu_vrf_rd_sz)
		inst.mvu_op_type = 'matvec'
		inst.mvu_tag = tag

		#Set the eVRF mOP to move 
		evrf_word_count = int(tmp[0].word_count) #int(math.ceil(1.0 * matrix.dimension_y / dpes)) * dpes / lanes 
		inst.extvrf_rd_sz = evrf_word_count
		inst.extvrf_rd_base = [0] * batch
		inst.extvrf_op_type = 'move'
		inst.extvrf_tag = tag

		#Adjust WB count, flags and results of the chain and add it to instruction queue
		inst.wb_so_far = wb_count
		inst.flags[0] = True
		inst.results[0] = tmp[0].name
		self.inst_q.append(inst)

		#Functional model
		for i in range(batch):
			tmp[i].data = np.dot(matrix.data.astype(self.ac_data_type), vectors[i].data.astype(self.ac_data_type))
			tmp[i].useful_data = tmp[i].data[:tmp[i].dimension_x]
		return tmp

	'''
	This function reads a vector that resides in the external VRF (skipping the MVU block). Returns a vector data structure.
	vector_in: vector to be read from the evrf memory space.
	'''
	def read_evrf(self, vectors, batch=1):
		assert self.inst_q, 'An NPU program should start with a load operation'
		for b in range(batch):
			assert vectors[b].space_name == 'evrf', 'Vector ' + vectors[b].name + ' does not exist in the evrf memory space'
		tiles = self.arch_params['tiles']
		dpes  = self.arch_params['dpes']
		lanes = self.arch_params['lanes']

		inst = chain(batch)
		tag = 0
		wb_count = self.inst_q[-1].wb_so_far
		names = []
		for i in range(batch):
			names.append(vectors[i].name)

		for i in reversed(self.inst_q):
			if(i.results[-1] in names):
				tag = i.wb_so_far
				break
		if (tag > self.highest_tag_so_far):
			self.highest_tag_so_far = tag
		
		tmp = []
		for b in range(batch):
			tmp.append(vector('tmp_1', vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
			inst.extvrf_rd_base[b] = vectors[b].alloc_addr
		inst.extvrf_rd_sz = vectors[0].word_count
		inst.extvrf_op_type = 'extvrf'
		inst.extvrf_tag = tag
		inst.wb_so_far= wb_count
		inst.flags[0] = True
		inst.results[0] = tmp[0].name
		self.inst_q.append(inst)

		#Functional model
		for b in range(batch):
			tmp[b].data = vectors[b].data
			tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
		return tmp

	'''
	This function performs hyperbolic tangent activation function. Returns a vector data structure.
	vector_in: input vector (intermediate -- does not reside in one of the memory spaces).
	'''
	def tanh(self, vectors, batch=1):
		return self.activation(vectors, 'tanh', batch)


	'''
	This function performs sigmoid activation function. Returns a vector data structure.
	vector_in: input vector (intermediate -- does not reside in one of the memory spaces).
	'''
	def sigmoid(self, vectors, batch=1):
		return self.activation(vectors, 'sig', batch)

	'''
	This function performs rectified linear unit activation function. Returns a vector data structure.
	vector_in: input vector (intermediate -- does not reside in one of the memory spaces).
	'''
	def relu(self, vectors, batch=1):
		return self.activation(vectors, 'relu', batch)

	'''
	This function is a unified backend for all the activation functions (tanh, sigmoid, relu) to avoid
	code repetition.
	'''
	def activation(self, vectors, op, batch):
		for b in range(batch):
			assert vectors[b].alloc_addr == -1, 'Input vector is not a temp variable'
		assert self.inst_q, 'Cannot start a chain with a ' + op + ' function'
		tiles = self.arch_params['tiles']
		dpes  = self.arch_params['dpes']
		lanes = self.arch_params['lanes']
		prev_inst = self.inst_q[-1]
		input_vec_name = ''

		# If possible to schedule at MFU0
		if(prev_inst.flags[0] == True and prev_inst.flags[1] == False):
			input_vec_name = prev_inst.results[0]
			assert vectors[0].name == input_vec_name, 'Invalid input to ' + op + ' function'
			prev_inst.mfu0_act_op_type = op
			prev_inst.mfu0_tag = 0
			prev_inst.flags[1] = True
			tmp = []
			for b in range(batch):
				tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_1', vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
			prev_inst.mfu0_vrf_rd_size = tmp[0].word_count
			prev_inst.results[1] = tmp[0].name

			#Functional Model
			# The functional model treats activation functions as if they are bypassed since those
			# are approximate hardware cores and we do not support their verification yet (check limitations
			# listed at the top of this file).
			for b in range(batch):
				tmp[b].data = vectors[b].data.astype(self.ac_data_type)
				tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
			return tmp

		# If possible to schedule at MFU1
		elif(prev_inst.flags[0] == True and prev_inst.flags[4] == False):
			for i in range(4, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert vectors[0].name == input_vec_name, 'Invalid input to ' + op + ' function'
			prev_inst.mfu1_act_op_type = op
			prev_inst.mfu1_tag = 0
			for i in range(4, 1, -1):
				prev_inst.flags[i] = True
			tmp = []
			for b in range(batch):
				tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_4', vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
			prev_inst.mfu1_vrf_rd_size = tmp[0].word_count
			prev_inst.results[4] = tmp[0].name

			#Functional Model
			# The functional model treats activation functions as if they are bypassed since those
			# are approximate hardware cores and we do not support their verification yet (check limitations
			# listed at the top of this file).
			for b in range(batch):
				tmp[b].data = vectors[b].data.astype(self.ac_data_type)
				tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
			return tmp

		else:
			assert False, 'Cannot start a chain with a ' + op + ' function'	

	'''
	This function performs elementwise vector addition. Returns a vector data structure.
	temp_vector: input vector (intermediate -- does not reside in one of the memory spaces).
	vrf_vector: vector that resides in mfu0_add or mfu1_add memory spaces.
	'''
	def add(self, temp_vectors, vrf_vectors, batch=1):
		for b in range(batch):
			assert ((vrf_vectors[b].space_name == 'mfu0_add') | (vrf_vectors[b].space_name == 'mfu1_add')), 'Vector ' + vrf_vectors[b].name + ' does not exist in an MFU add memory space'
			assert (temp_vectors[b].space_name == 'temp'), 'Vector ' + temp_vectors[b].name + ' is not a temp variable'
		return self.add_sub_max(temp_vectors, vrf_vectors, 'add', batch)

	'''
	This function performs elementwise vector subtraction (temp_vector - vrf_vector). Returns a vector data structure.
	temp_vector: input vector (intermediate -- does not reside in one of the memory spaces)
	vrf_vector: vector that resides in mfu0_add or mfu1_add memory spaces
	'''
	def sub_a_b(self, temp_vectors, vrf_vectors, batch=1):
		for b in range(batch):
			assert ((vrf_vectors[b].space_name == 'mfu0_add') | (vrf_vectors[b].space_name == 'mfu1_add')), 'Vector ' + vrf_vectors[b].name + ' does not exist in an MFU add memory space'
			assert (temp_vectors[b].space_name == 'temp'), 'Vector ' + temp_vectors[b].name + ' is not a temp variable'
		return self.add_sub_max(temp_vectors, vrf_vectors, 'sub_a_b', batch)

	'''
	This function performs elementwise vector subtraction (vrf_vector - temp_vector). Returns a vector data structure.
	temp_vector: input vector (intermediate -- does not reside in one of the memory spaces)
	vrf_vector: vector that resides in mfu0_add or mfu1_add memory spaces
	'''
	def sub_b_a(self, temp_vectors, vrf_vectors, batch=1):
		for b in range(batch):
			assert ((vrf_vectors[b].space_name == 'mfu0_add') | (vrf_vectors[b].space_name == 'mfu1_add')), 'Vector ' + vrf_vectors[b].name + ' does not exist in an MFU add memory space'
			assert (temp_vectors[b].space_name == 'temp'), 'Vector ' + temp_vectors[b].name + ' is not a temp variable'
		return self.add_sub_max(temp_vectors, vrf_vectors, 'sub_b_a', batch)

	'''
	Performs elementwise vector maximum operation. Returns a vector data structure.
	temp_vector: input vector (intermediate -- does not reside in one of the memory spaces)
	vrf_vector: vector that resides in mfu0_add or mfu1_add memory spaces
	'''
	def mfu_max(self, temp_vectors, vrf_vectors, batch=1):
		for b in range(batch):
			assert ((vrf_vectors[b].space_name == 'mfu0_add') | (vrf_vectors[b].space_name == 'mfu1_add')), 'Vector ' + vrf_vectors[b].name + ' does not exist in an MFU add memory space'
			assert (temp_vectors[b].space_name == 'temp'), 'Vector ' + temp_vectors[b].name + ' is not a temp variable'
		return self.add_sub_max(temp_vectors, vrf_vectors, 'max', batch)

	'''
	This function is a unified backend for all the mfu functions related to the addition unit (e.g. add,
	subtract, elementwise maximum)
	'''
	def add_sub_max(self, temp_vectors, vrf_vectors, op_name, batch):
		tiles = self.arch_params['tiles']
		dpes  = self.arch_params['dpes']
		lanes = self.arch_params['lanes']

		# Figure out vrf_vector dependency
		names = []
		for b in range(batch):
			names.append(vrf_vectors[b].name)
		tag = 0
		for i in reversed(self.inst_q):
			if(i.results[-1] in names):
				tag = i.wb_so_far
				break
		if (tag > self.highest_tag_so_far):
			self.highest_tag_so_far = tag
		prev_inst = self.inst_q[-1]
		input_vec_name = ''

		# Make sure that all VRF vectors reside in the same memory space
		all_vrf_vectors_in_same_space = True
		space_name = vrf_vectors[0].space_name
		for b in range(1, batch):
			all_vrf_vectors_in_same_space = all_vrf_vectors_in_same_space and (vrf_vectors[b].space_name == space_name)
		assert all_vrf_vectors_in_same_space, 'Not all the VRF vectors belong to the same memory space'

		# If possible to schedule at MFU0
		if(prev_inst.flags[0] == True and prev_inst.flags[2] == False and vrf_vectors[0].space_name == 'mfu0_add'):
			for i in range(2, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert temp_vectors[0].name == input_vec_name, 'Invalid input to ' + op_name + ' function'

			prev_inst.mfu0_add_op_type = op_name
			for i in range(2, 0, -1):
				prev_inst.flags[i] = True
			tmp = []
			for b in range(batch):
				tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_2', vrf_vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
				prev_inst.mfu0_vrf0_rd_base[b] = vrf_vectors[b].alloc_addr
			prev_inst.results[2] 		= tmp[0].name
			prev_inst.mfu0_vrf_rd_size 	= vrf_vectors[0].word_count
			prev_inst.mfu0_tag 			= tag

			#Functional Model
			for b in range(batch):
				if(op_name == 'add'):
					tmp[b].data = temp_vectors[b].data.astype(self.ac_data_type) + vrf_vectors[b].data.astype(self.ac_data_type)
				elif(op_name == 'sub_a_b'):
					tmp[b].data = temp_vectors[b].data.astype(self.ac_data_type) - vrf_vectors[b].data.astype(self.ac_data_type)
				elif(op_name == 'sub_b_a'):
					tmp[b].data = vrf_vectors[b].data.astype(self.ac_data_type) - temp_vectors[b].data.astype(self.ac_data_type)
				elif(op_name == 'max'):
					tmp[b].data = np.maximum(temp_vectors[b].data.astype(self.ac_data_type), vrf_vectors[b].data.astype(self.ac_data_type))
				else:
					assert False, 'Invalid op name'
				tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
			return tmp

		# If possible to schedule at MFU1
		elif(prev_inst.flags[0] == True and prev_inst.flags[5] == False and vrf_vectors[0].space_name == 'mfu1_add'):
			for i in range(5, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert temp_vectors[0].name == input_vec_name, 'Invalid input to ' + op_name + ' function'

			prev_inst.mfu1_add_op_type = op_name
			for i in range(5, 3, -1):
				prev_inst.flags[i] = True
			tmp = []
			for b in range(batch):
				tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_5', vrf_vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
				prev_inst.mfu1_vrf0_rd_base[b] = vrf_vectors[b].alloc_addr
			prev_inst.results[5] 		= tmp[0].name
			prev_inst.mfu1_vrf_rd_size 	= vrf_vectors[0].word_count
			prev_inst.mfu1_tag 			= tag

			#Functional Model
			for b in range(batch):
				if(op_name == 'add'):
					tmp[b].data = temp_vectors[b].data.astype(self.ac_data_type) + vrf_vectors[b].data.astype(self.ac_data_type)
				elif(op_name == 'sub_a_b'):
					tmp[b].data = temp_vectors[b].data.astype(self.ac_data_type) - vrf_vectors[b].data.astype(self.ac_data_type)
				elif(op_name == 'sub_b_a'):
					tmp[b].data = vrf_vectors[b].data.astype(self.ac_data_type) - temp_vectors[b].data.astype(self.ac_data_type)
				elif(op_name == 'max'):
					tmp[b].data = np.maximum(temp_vectors[b].data.astype(self.ac_data_type), vrf_vectors[b].data.astype(self.ac_data_type))
				else:
					assert False, 'Invalid op name'
				tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
			return tmp

		else:
			assert False, 'Cannot start a chain with a/an ' + op_name + ' function'

	'''
	This function performs elementwise vector multiplication. Returns a vector data structure.
	temp_vector: input vector (intermediate -- does not reside in one of the memory spaces)
	vrf_vector: vector that resides in mfu0_mul or mfu1_mul memory spaces
	'''
	def multiply(self, temp_vectors, vrf_vectors, batch=1):
		for b in range(batch):
			assert ((vrf_vectors[b].space_name == 'mfu0_mul') | (vrf_vectors[b].space_name == 'mfu1_mul')), 'Vector ' + vrf_vectors[b].name + ' does not exist in an MFU multiply memory space'
			assert (temp_vectors[b].space_name == 'temp'), 'Vector ' + temp_vectors[b].name + ' is not a temp variable'
		tiles = self.arch_params['tiles']
		dpes  = self.arch_params['dpes']
		lanes = self.arch_params['lanes']

		# Figure out vrf_vector dependency
		names = []
		for b in range(batch):
			names.append(vrf_vectors[b].name)
		tag = 0
		for i in reversed(self.inst_q):
			if(i.results[-1] in names):
				tag = i.wb_so_far
				break
		if (tag > self.highest_tag_so_far):
			self.highest_tag_so_far = tag
		prev_inst = self.inst_q[-1]
		input_vec_name = ''

		# Make sure that all VRF vectors reside in the same memory space
		all_vrf_vectors_in_same_space = True
		space_name = vrf_vectors[0].space_name
		for b in range(1, batch):
			all_vrf_vectors_in_same_space = all_vrf_vectors_in_same_space and (vrf_vectors[b].space_name == space_name)
		assert all_vrf_vectors_in_same_space, 'Not all the VRF vectors belong to the same memory space'

		# If possible to schedule at MFU0
		if(prev_inst.flags[0] == True and prev_inst.flags[3] == False and vrf_vectors[0].space_name == 'mfu0_mul'):
			for i in range(3, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert temp_vectors[0].name == input_vec_name, 'Invalid input to multiply function ' + temp_vectors[0].name + ' != ' + input_vec_name

			prev_inst.mfu0_mul_op_type = 'mul'
			for i in range(3, 0, -1):
				prev_inst.flags[i] = True
			tmp = []
			for b in range(batch):
				tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_3', vrf_vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
				prev_inst.mfu0_vrf1_rd_base[b] = vrf_vectors[b].alloc_addr
			prev_inst.results[3] 		= tmp[0].name	
			prev_inst.mfu0_vrf_rd_size 	= vrf_vectors[0].word_count
			prev_inst.mfu0_tag 			= tag

			#Functional Model
			for b in range(batch):
				tmp[b].data = (temp_vectors[b].data.astype(self.ac_data_type) * vrf_vectors[b].data.astype(self.ac_data_type)).astype(self.ac_data_type)
				tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
			return tmp

		# If possible to schedule at MFU1
		elif(prev_inst.flags[0] == True and prev_inst.flags[6] == False and vrf_vectors[0].space_name == 'mfu1_mul'):
			for i in range(6, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert temp_vectors[0].name == input_vec_name, 'Invalid input to multiply function'

			prev_inst.mfu1_mul_op_type = 'mul'
			for i in range(6, 3, -1):
				prev_inst.flags[i] = True
			tmp = []
			for b in range(batch):
				tmp.append(vector('tmp_' + str(len(self.inst_q)) + '_6', vrf_vectors[b].dimension_x, 'temp', tiles, dpes, lanes, self.in_data_type, self.ac_data_type))
				prev_inst.mfu1_vrf1_rd_base[b] = vrf_vectors[b].alloc_addr
			prev_inst.results[6] = tmp[0].name
			prev_inst.mfu1_vrf_rd_size 	= vrf_vectors[0].word_count
			prev_inst.mfu1_tag 			= tag

			#Functional Model
			for b in range(batch):
				tmp[b].data = (temp_vectors[b].data.astype(self.ac_data_type) * vrf_vectors[b].data.astype(self.ac_data_type)).astype(self.ac_data_type)
				tmp[b].useful_data = tmp[b].data[:tmp[b].dimension_x]
			return tmp

		else:
			assert False, 'Cannot start a chain with a multiply function'

	'''
	This function is backend function for writing back a result to any VRF outside of MVU to one or two
	destinations specified by the user. The write_to_obuf flag is set to high if the result is to be
	directed to the NPU output as well.
	'''
	def wb_to_vrfs(self, dst1, dst2, write_to_obuf, batch=1):
		# Assign the vrf_id based on the destination memory space
		tiles = self.arch_params['tiles']
		prev_inst = self.inst_q[-1]
		wb_count = self.inst_q[-1].wb_so_far
		prev_inst.wb_so_far = wb_count + 1

		# Make sure that all dst1 vectors belong to the same memory space
		space_name = dst1[0].space_name
		all_dst1_vectors_in_same_space = True
		for b in range(1, batch):
			all_dst1_vectors_in_same_space = all_dst1_vectors_in_same_space and (dst1[b].space_name == space_name)
		assert all_dst1_vectors_in_same_space, 'Not all dst1 vectors belong to the same memory space'

		# Write load instruction fields
		if (dst1[0].space_name == 'evrf'):
			prev_inst.vrf_id0_op = 'extvrf'
		elif (dst1[0].space_name == 'mfu0_add'):
			prev_inst.vrf_id0_op = 'mfu0.vrf0'
		elif (dst1[0].space_name == 'mfu0_mul'):
			prev_inst.vrf_id0_op = 'mfu0.vrf1'
		elif (dst1[0].space_name == 'mfu1_add'):
			prev_inst.vrf_id0_op = 'mfu1.vrf0'
		elif (dst1[0].space_name == 'mfu1_mul'):
			prev_inst.vrf_id0_op = 'mfu1.vrf1'
		for b in range(batch):
			prev_inst.vrf_id0_wr_base[b] = dst1[b].alloc_addr
		prev_inst.vrf_id0_wr_size = dst1[0].word_count
		prev_inst.vrf_id1_wr_size = 0
		prev_inst.write_to_obuf = write_to_obuf
		prev_inst.loader_src = 'wb'
		prev_inst.results[-1] = dst1[0].name

		# Do the same for second destination if exists
		if (dst2 != None):
			# Make sure that all dst2 vectors belong to the same memory space
			space_name = dst2[0].space_name
			all_dst2_vectors_in_same_space = True
			for b in range(1, batch):
				all_dst2_vectors_in_same_space = all_dst2_vectors_in_same_space and (dst2[b].space_name == space_name)
			assert all_dst2_vectors_in_same_space, 'Not all dst2 vectors belong to the same memory space'
			if (dst2[0].space_name == 'evrf'):
				prev_inst.vrf_id1_op = 'extvrf'
			elif (dst2[0].space_name == 'mfu0_add'):
				prev_inst.vrf_id1_op = 'mfu0.vrf0'
			elif (dst2[0].space_name == 'mfu0_mul'):
				prev_inst.vrf_id1_op = 'mfu0.vrf1'
			elif (dst2[0].space_name == 'mfu1_add'):
				prev_inst.vrf_id1_op = 'mfu1.vrf0'
			elif (dst2[0].space_name == 'mfu1_mul'):
				prev_inst.vrf_id1_op = 'mfu1.vrf1'
			for b in range(batch):
				prev_inst.vrf_id1_wr_base[b] = dst2[b].alloc_addr
			prev_inst.vrf_id1_wr_size = dst2[0].word_count

		# Set flags of all stages to be used 
		for i in range(7, -1, -1):
			prev_inst.flags[i] = True

	'''
	This function is backend function for writing back a result to MVU VRFs. The write_to_obuf flag 
	is set to high if the result is to be directed to the NPU output as well.
	'''
	def wb_to_mvu(self, dst, write_to_obuf, batch=1):
		# In case of mvu write back we write a new instruction for each tile
		tiles = self.arch_params['tiles']	
		wb_count = self.inst_q[-1].wb_so_far
		prev_inst = self.inst_q[-1]
		remaining_entries = prev_inst.mfu1_vrf_rd_size
		for i in range(tiles):
			if(remaining_entries > 0):
				inst = chain(batch);
				inst.results[-1] = dst[0].name
				wb_count = wb_count + 1
				inst.wb_so_far = wb_count
				inst.vrf_id0_op = 'mvu'+str(i)+'.vrf'
				for b in range(batch):
					inst.vrf_id0_wr_base[b] 	= dst[b].alloc_addr
				inst.vrf_id0_wr_size = min(dst[0].word_count, remaining_entries)
				inst.vrf_id1_wr_size = 0
				inst.write_to_obuf = write_to_obuf
				inst.loader_src = 'wb'
				for i in range(7, -1, -1):
					inst.flags[i] = True
				self.inst_q.append(inst)
				remaining_entries -= dst[0].word_count

	'''
	This function is backend function for writing back a result to two destinations, one of which is
	MVU VRFs and the other is any other VRF. The write_to_obuf flag is set to high if the result is 
	to be directed to the NPU output as well.
	'''
	def wb_to_mvu_and_vrfs(self, dst1, dst2, write_to_obuf, batch=1):
		# In case of mvu write back we write a new instruction for each tile
		#assert dst1[0].name != dst2[0].name, 'The two write back destination vectors must have the same name'
		tiles = self.arch_params['tiles']	
		
		# Make sure that all dst2 vectors belong to the same memory space
		space_name = dst2[0].space_name
		all_dst2_vectors_in_same_space = True
		for b in range(1, batch):
			all_dst2_vectors_in_same_space = all_dst2_vectors_in_same_space and (dst2[b].space_name == space_name)
		assert all_dst2_vectors_in_same_space, 'Not all dst2 vectors belong to the same memory space'

		if (dst2[0].space_name == 'evrf'):
			temp_vrf_id1_op = 'extvrf'
		elif (dst2[0].space_name == 'mfu0_add'):
			temp_vrf_id1_op = 'mfu0.vrf0'
		elif (dst2[0].space_name == 'mfu0_mul'):
			temp_vrf_id1_op = 'mfu0.vrf1'
		elif (dst2[0].space_name == 'mfu1_add'):
			temp_vrf_id1_op = 'mfu1.vrf0'
		elif (dst2[0].space_name == 'mfu1_mul'):
			temp_vrf_id1_op = 'mfu1.vrf1'

		wb_count = self.inst_q[-1].wb_so_far
		prev_inst = self.inst_q[-1]
		remaining_entries = prev_inst.mfu1_vrf_rd_size
		for i in range(tiles):
			if(remaining_entries > 0):
				inst = chain(batch);
				inst.results[-1] = dst1[0].name
				wb_count = wb_count + 1
				inst.wb_so_far = wb_count
				inst.vrf_id0_op 	 = 'mvu'+str(i)+'.vrf'
				inst.vrf_id1_op 	 = temp_vrf_id1_op
				for b in range(batch):
					inst.vrf_id0_wr_base[b] = dst1[b].alloc_addr
					inst.vrf_id1_wr_base[b] = dst2[b].alloc_addr + (i * dst1[b].word_count)
				inst.vrf_id0_wr_size = min(dst1[0].word_count, remaining_entries)
				inst.vrf_id1_wr_size = min(dst1[0].word_count, remaining_entries)
				inst.loader_src 	 = 'wb'
				inst.write_to_obuf = write_to_obuf
				inst.results[-1] = dst1[0].name
				for i in range(7, -1, -1):
					inst.flags[i] = True
				self.inst_q.append(inst)
				remaining_entries -= dst1[0].word_count

	'''
	This function writes back an intermediate vector to 1 or 2 destinations.
	vector_in: input intermediate vector
	dst1: destination vector allocated in one of the NPU vector memory spaces
	dst2 (optional): another destination vector allocated in one of the NPU vector memory spaces
	write_to_obuf (optional): if set to one, vector_in is also written to the NPU output buffer
	'''
	def write_back(self, vectors, dst1, dst2=None, write_to_obuf=0, batch=1):
		# Make sure that this is not the first instruction and that the write back is not the start of a new instruction
		assert self.inst_q, 'Cannot start a new chain with a write back'
		prev_inst = self.inst_q[-1]
		assert prev_inst.flags[-1] == False, 'Cannot start a new instruction with a write back'
		inst_check = False
		for i in prev_inst.flags:
			inst_check = inst_check | i
		assert inst_check == True, 'Cannot start a new instruction with a write back'

		# Make sure input vector is a temp variable and that it is the last one produced by the previous instruction
		for b in range(batch):
			assert vectors[b].space_name == 'temp', 'Input vector is not a temp variable'
			for i in range(6, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert vectors[b].name == input_vec_name, 'Invalid input to write back function'

		prev_inst.adjust_bypassed()
		# Single destination
		if (dst2 == None):
			if(dst1[0].space_name != 'mvu_vrf'):
				self.wb_to_vrfs(dst1, None, write_to_obuf, batch)
			else:
				self.wb_to_mvu(dst1, write_to_obuf, batch)

			#Functional Model
			temp_data = []
			for b in range(batch):
				for i in range(min(len(dst1[b].data), len(vectors[b].data))):
					dst1[b].data[i] = vectors[b].data[i]
				dst1[b].useful_data = dst1[b].data[:dst1[b].dimension_x]
				#for i in range(len(dst1[b].data)):
					#if (dst1[b].space_name == 'mvu_vrf' and dst1[b].data[i] == -128):
					#	dst1[b].data[i] = 0

				if(write_to_obuf == 1):
					temp_data.append(vectors[b].data[:min(len(vectors[b].data), len(dst1[b].data))].reshape((int(min(len(vectors[b].data), len(dst1[b].data))/self.arch_params['lanes']), self.arch_params['lanes'])))
			
			if(write_to_obuf == 1):
				for i in range(len(temp_data[0])):
					for b in range(batch):
						self.golden_obuf_q.append(list(temp_data[b][i]))

			if(len(vectors[0].data) > len(dst1[0].data)):
				wb_count = self.inst_q[-1].wb_so_far
				inst = chain(batch)
				#wb_count = wb_count + 1
				inst.wb_so_far = wb_count
				inst.vrf_id0_wr_size = int((len(vectors[0].data) - len(dst1[0].data))/self.arch_params['lanes'])
				inst.loader_src = 'flush'
				inst.write_to_obuf = 0
				for i in range(7, -1, -1):
					inst.flags[i] = True
				self.inst_q.append(inst)
			
		# Two destinations
		else:
			assert dst2[0].space_name != dst1[0].space_name, 'Cannot write back twice to the same memory space'
			if(dst1[0].space_name != 'mvu_vrf' and dst2[0].space_name != 'mvu_vrf'):
				self.wb_to_vrfs(dst1, dst2, write_to_obuf, batch)
			elif(dst1[0].space_name != 'mvu_vrf' and dst2[0].space_name == 'mvu_vrf'):
				self.wb_to_mvu_and_vrfs(dst2, dst1, write_to_obuf, batch)
			elif(dst1[0].space_name == 'mvu_vrf' and dst2[0].space_name != 'mvu_vrf'):
				self.wb_to_mvu_and_vrfs(dst1, dst2, write_to_obuf, batch)
			else:
				assert False, 'Something wrong with write back'

			#Functional Model
			temp_data = []
			for b in range(batch):
				for i in range(min(len(dst1[b].data), len(vectors[b].data))):
					dst1[b].data[i] = vectors[b].data[i]
					dst2[b].data[i] = vectors[b].data[i]
				dst1[b].useful_data = dst1[b].data[:dst1[b].dimension_x]
				dst2[b].useful_data = dst2[b].data[:dst2[b].dimension_x]
				#for i in range(len(dst1[b].data)):
					#if (dst1[b].space_name == 'mvu_vrf' and dst1[b].data[i] == -128):
					#	dst1[b].data[i] = 0
					#if (dst2[b].space_name == 'mvu_vrf' and dst2[b].data[i] == -128):
					#	dst2[b].data[i] = 0
				
				if(write_to_obuf == 1):
					temp_data.append(vectors[b].data[:min(len(vectors[b].data), len(dst1[b].data))].reshape((int(min(len(vectors[b].data), len(dst1[b].data))/self.arch_params['lanes']), self.arch_params['lanes'])))
			
			if(write_to_obuf == 1):
				for i in range(len(temp_data[0])):
					for b in range(batch):
						self.golden_obuf_q.append(list(temp_data[b][i]))

			if(len(vectors[0].data) > len(dst1[0].data)):
				wb_count = self.inst_q[-1].wb_so_far
				inst = chain(batch)
				#wb_count = wb_count + 1
				inst.wb_so_far = wb_count
				inst.vrf_id0_wr_size = int((len(vectors[0].data) - len(dst1[0].data))/self.arch_params['lanes'])
				inst.loader_src = 'flush'
				inst.write_to_obuf = 0
				for i in range(7, -1, -1):
					inst.flags[i] = True
				self.inst_q.append(inst)

	'''
	This function ends the instruction chain with a fake write back to MVU VRFs (i.e. only send outputs to ofifo).
	vector_in: input intermediate vector
	dst1: destination vector allocated in one of the NPU vector memory spaces
	'''
	def produce_output(self, vectors, dst1, batch=1):
		# Make sure that this is not the first instruction and that the write back is not the start of a new instruction
		assert self.inst_q, 'Cannot start a new chain with a write back'
		prev_inst = self.inst_q[-1]
		assert prev_inst.flags[-1] == False, 'Cannot start a new instruction with a write back'
		inst_check = False
		for i in prev_inst.flags:
			inst_check = inst_check | i
		assert inst_check == True, 'Cannot start a new instruction with a write back'

		# Make sure input vector is a temp variable and that it is the last one produced by the previous instruction
		for b in range(batch):
			assert vectors[b].space_name == 'temp', 'Input vector is not a temp variable'
			for i in range(6, -1, -1):
				if prev_inst.results[i] != '':
					input_vec_name = prev_inst.results[i]
					break
			assert vectors[b].name == input_vec_name, 'Invalid input to write back function'

		prev_inst.adjust_bypassed()

		tiles = self.arch_params['tiles']	
		wb_count = self.inst_q[-1].wb_so_far
		prev_inst = self.inst_q[-1]
		remaining_entries = prev_inst.mfu1_vrf_rd_size
		for i in range(tiles):
			if(remaining_entries > 0):
				inst = chain(batch);
				inst.results[-1] = dst1[0].name
				#wb_count = wb_count + 1
				inst.wb_so_far = wb_count
				inst.vrf_id0_op = '--'
				for b in range(batch):
					inst.vrf_id0_wr_base[b] 	= dst1[b].alloc_addr
				inst.vrf_id0_wr_size = min(dst1[0].word_count, remaining_entries)
				inst.vrf_id1_wr_size = 0
				inst.write_to_obuf = 1
				inst.loader_src = 'wb'
				for i in range(7, -1, -1):
					inst.flags[i] = True
				self.inst_q.append(inst)
				remaining_entries -= dst1[0].word_count

		#Functional Model
		temp_data = []
		for b in range(batch):
			for i in range(min(len(dst1[b].data), len(vectors[b].data))):
				dst1[b].data[i] = vectors[b].data[i]
			dst1[b].useful_data = dst1[b].data[:dst1[b].dimension_x]

			temp_data.append(vectors[b].data[:min(len(vectors[b].data), len(dst1[b].data))].reshape((int(min(len(vectors[b].data), len(dst1[b].data))/self.arch_params['lanes']), self.arch_params['lanes'])))
		
		for i in range(len(temp_data[0])):
			for b in range(batch):
				self.golden_obuf_q.append(list(temp_data[b][i]))

		if(len(vectors[0].data) > len(dst1[0].data)):
			wb_count = self.inst_q[-1].wb_so_far
			inst = chain(batch)
			#wb_count = wb_count + 1
			inst.wb_so_far = wb_count
			inst.vrf_id0_wr_size = int((len(vectors[0].data) - len(dst1[0].data))/self.arch_params['lanes'])
			inst.loader_src = 'flush'
			inst.write_to_obuf = 0
			for i in range(7, -1, -1):
				inst.flags[i] = True
			self.inst_q.append(inst)

	'''
	This function loads data from the NPU input buffer to a specific destination vector
	vector: destination vector allocated in one of the NPU vector memory spaces
	write_to_obuf (optional): if set to one, vector_in is also written to the NPU output buffer
	'''
	def load(self, vectors, write_to_obuf=0, batch=1):
		temp_data = []
		for b in range(batch):
			assert vectors[b].useful_data != [], 'Input vector data is not specified'
			# Add vector to input buffer queue
			temp_data.append(vectors[b].data.reshape((int(len(vectors[b].data)/self.arch_params['lanes']), self.arch_params['lanes'])))

		for i in range(len(temp_data[0])):
			for b in range(batch):
				self.ibuf_q.append(list(temp_data[b][i]))

		# Get number of tiles
		tiles = self.arch_params['tiles']	
		# Write instruction chains for loading input vectors
		if not self.inst_q:
			wb_count = 0
		else:
			wb_count = self.inst_q[-1].wb_so_far

		# Make sure that all vectors belong to the same memory space
		space_name = vectors[0].space_name
		all_vectors_in_same_space = True
		for b in range(1, batch):
			all_vectors_in_same_space = all_vectors_in_same_space and (vectors[b].space_name == space_name)
		assert all_vectors_in_same_space, 'Not all vectors belong to the same memory space'

		if(vectors[0].space_name == 'mvu_vrf'):
			for i in range(tiles):
				inst = chain(batch);
				inst.results[-1] = vectors[0].name
				wb_count = wb_count + 1
				inst.wb_so_far = wb_count
				inst.vrf_id0_op = 'mvu'+str(i)+'.vrf'
				for b in range(batch):
					inst.vrf_id0_wr_base[b] = vectors[b].alloc_addr
				inst.vrf_id0_wr_size = vectors[0].word_count
				inst.vrf_id1_wr_size = 0
				inst.loader_src	= 'in'
				inst.write_to_obuf = write_to_obuf
				inst.flags[-1] = True
				self.inst_q.append(inst)
		else:
			inst = chain(batch);
			inst.results[-1] = vectors[0].name
			wb_count = wb_count + 1
			inst.wb_so_far = wb_count
			if(vectors[0].space_name == 'evrf'):
				inst.vrf_id0_op = 'extvrf'
			elif(vectors[0].space_name == 'mfu0_add'):
				inst.vrf_id0_op = 'mfu0.vrf0'
			elif(vectors[0].space_name == 'mfu0_mul'):
				inst.vrf_id0_op = 'mfu0.vrf1'
			elif(vectors[0].space_name == 'mfu1_add'):
				inst.vrf_id0_op = 'mfu1.vrf0'
			else:
				inst.vrf_id0_op = 'mfu1.vrf1'
			for b in range(batch):
				inst.vrf_id0_wr_base[b] = vectors[b].alloc_addr
			inst.vrf_id0_wr_size = vectors[0].word_count
			inst.vrf_id1_wr_size = 0
			inst.loader_src	= 'in'
			inst.write_to_obuf = write_to_obuf
			inst.flags[-1] = True
			self.inst_q.append(inst)

		if(write_to_obuf == 1):
			temp_data = []
			for b in range(batch):
				temp_data.append(vectors[b].data.reshape((len(vectors[b].data)/self.arch_params['lanes'], self.arch_params['lanes'])))

			for i in range(len(temp_data[0])):
				for b in range(batch):
					self.golden_obuf_q.append(list(temp_data[b][i]))

	'''
	This function is used to mark the end of an NPU program by setting the "last instruction" flag for
	the latest instruction added to the queue. If multiple NPU routines are to be written in a single
	NPU program, each routine must end by calling the end_npu_program() function.
	'''
	def end_npu_program(self):
		idx = -1
		while True:
			if (self.inst_q[idx].loader_src == 'flush'):
				idx = idx - 1
			else:
				break
		self.inst_q[idx].last_flag = 1

	'''
	This function uses FSim to perform a functional simulation for the NPU program written by the user,
	and compare its results to the golden results generated by the functional model in each of the 
	compiler functions.
	'''
	def fsim_npu_program(self, verbose=0):
		# Initialize FSim
		inst_stream = copy.deepcopy(self.inst_q)
		input_buffer = copy.deepcopy(self.ibuf_q)
		initial_mvu_vrfs = copy.deepcopy(self.mvu_vrfs)
		initial_ext_vrf = copy.deepcopy(self.ext_vrf)
		initial_mfu0_vrf0 = copy.deepcopy(self.mfu0_vrf0)
		initial_mfu0_vrf1 = copy.deepcopy(self.mfu0_vrf1)
		initial_mfu1_vrf0 = copy.deepcopy(self.mfu1_vrf0)
		initial_mfu1_vrf1 = copy.deepcopy(self.mfu1_vrf1)
		inst_count = len(self.inst_q)
		self.fsim = npu_isa_sim(inst_stream, list(input_buffer), initial_mvu_vrfs, initial_ext_vrf, initial_mfu0_vrf0, initial_mfu0_vrf1, initial_mfu1_vrf0, initial_mfu1_vrf1,\
			self.arch_params['tiles'], self.arch_params['dpes'], self.arch_params['lanes'], self.arch_params['vrf_depth'])
		self.fsim.mvu_mrfs = self.mrfs

		# Simulate the instructions in instruction queue
		for i in range(inst_count):
			if(verbose):
				print("-------------- Starting simulation of instruction " + str(i+1) + " --------------")
			self.fsim.step(verbose) 
			if(verbose):
				print("-------------- Finished simulation of instruction " + str(i+1) + " --------------")

		# Verify results
		if (np.array_equal(self.fsim.obuf_q, self.golden_obuf_q)):
			print(bcolors.OKGREEN + 'Simulation finished successfully!' + bcolors.RESET)
		else:
			print(bcolors.FAIL + 'Simulation FAILED!' + bcolors.RESET)
			for r in range(len(self.fsim.obuf_q)):
				print('FSim: ' + str(self.fsim.obuf_q[r]))
				print('Gold: ' + str(self.golden_obuf_q[r]))

	'''
	This function dumps the FSim data structures containing the architecture states (i.e. MRFs, VRFs),
	as well as the instructions, input and output queues. These checkpoints are later used to generate
	the low-level binary checkpoints for the NPU.
	'''
	def generate_fsim_checkpoints(self, checkpoint_name, verbose=0):
		subprocess.call('mkdir dump', shell=True)
		count = 0
		# Instructions checkpoint
		instfile = open('./dump/' + checkpoint_name + '-inst', 'wb')
		pickle.dump(self.inst_q, instfile)
		instfile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-inst checkpoint')

		# Input checkpoint
		inputfile = open('./dump/' + checkpoint_name + '-input', 'wb')
		np.save(inputfile, self.ibuf_q)
		inputfile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-input checkpoint')

		# MRFs checkpoint
		mvumrffile = open('./dump/' + checkpoint_name + '-mvu_mrf', 'wb')
		np.save(mvumrffile, self.fsim.mvu_mrfs)
		mvumrffile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-mvu_mrf checkpoint')

		# VRFs checkpoints
		mvuvrffile = open('./dump/' + checkpoint_name + '-mvu_vrf', 'wb')
		np.save(mvuvrffile, self.mvu_vrfs)
		mvuvrffile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-mvu_vrf checkpoint')

		extvrffile = open('./dump/' + checkpoint_name + '-ext_vrf', 'wb')
		np.save(extvrffile, self.ext_vrf)
		extvrffile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-ext_vrf checkpoint')

		mfuvrffile = open('./dump/' + checkpoint_name + '-mfu_vrf', 'wb')
		np.save(mfuvrffile, self.mfu0_vrf0)
		mfuvrffile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-mfu_vrf checkpoint')

		# Output checkpoint
		outputfile = open('./dump/' + checkpoint_name + '-output', 'wb')
		np.save(outputfile, self.fsim.obuf_q)
		outputfile.close()
		count += 1
		if (verbose):
			print('Dumped ' + checkpoint_name + '-output checkpoint')

		return count

	def write_verilog_header_file(self, num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth, max_tag, mrf_filled_depth):
		dump_path = '../rtl/npu.vh'
		with open(dump_path, 'w') as header_file:
			header_file.write("`ifndef _NPU_VH_\n")
			header_file.write("`define _NPU_VH_\n\n")
			header_file.write("`define max(a,b) ((a > b) ? a : b)\n")
			header_file.write("`define roundup_power2(a) ((2) ** ($clog2(a)))\n\n")
			header_file.write("/***********************************/\n")
			header_file.write("/*    USER-SPECIFIED PARAMETERS    */\n")
			header_file.write("/***********************************/\n")
			header_file.write("`define NTILE     			"+str(num_tiles)+"			// Number of MVU tiles\n")
			header_file.write("`define NDPE      			"+str(num_dpes)+"  		// Number of dot product engines (DPEs) per tile\n")
			header_file.write("`define DOTW      			"+str(num_lanes)+"			// Number of lanes per DPE\n")
			header_file.write("`define VRFD					"+str(vrf_depth)+"			// Vector register file depth\n")
			header_file.write("`define MRFD      			"+str(mrf_depth)+"		// Matrix register file depth\n")
			header_file.write("`define EW        			8   		// Input bitwidth {8 or 4}\n")
			header_file.write("`define ACCW      			32  		// Accumulation/Output bitwidth\n")
			header_file.write("`define QDEPTH    			512			// FIFO depth\n")
			if(self.flow_opts['rtl_sim'] == 1):
				header_file.write("`define INPUT_BUFFER_SIZE	2048\n")
				header_file.write("`define OUTPUT_BUFFER_SIZE	2048\n")
			else:
				header_file.write("`define INPUT_BUFFER_SIZE	512\n")
				header_file.write("`define OUTPUT_BUFFER_SIZE	512\n")
			header_file.write("`define INST_DEPTH			512			// Instruction memory depth\n")
			rtl_dir = os.getcwd()
			idx = rtl_dir.rfind('/')
			rtl_dir = rtl_dir[:idx] + '/rtl/'
			header_file.write("`define RTL_DIR				\"" + rtl_dir + "\"	// Directory for RTL source code\n")
			header_file.write("`define TILES_THRESHOLD 	8			// Number of tiles implemented using hard DSP blocks\n")
			header_file.write("`define DPES_THRESHOLD  	0			// Number of DPEs/tile implemented using hard DSPs\n")
			header_file.write("`define TARGET_FPGA			\"S10-Prime\"		// Target FPGA {\"Arria 10\" or \"Stratix 10\" or \"S10-Prime\"}\n\n")
			header_file.write("/***********************************/\n")
			header_file.write("/*    IMPLEMENTATION PARAMETERS    */\n")
			header_file.write("/***********************************/\n")
			header_file.write("//DO NOT change these parameters unless you really know what you are doing\n")
			header_file.write("`define PRIME_DOTW			10\n")
			header_file.write("`define DOT_PER_DSP			3\n")
			header_file.write("`define NUM_DSP				DOTW / PRIME_DOTW\n")
			header_file.write("`define MULT_LATENCY       2 + (NUM_DSP-1)*2\n")
			header_file.write("`define DPE_PIPELINE    	MULT_LATENCY\n")
			header_file.write("`define VRFIDW					$clog2(NUM_DSP)\n")
			header_file.write("`define MRFIDW					$clog2(NUM_DSP*NTILE)\n")
			header_file.write("`define NUM_ACCUM				DOT_PER_DSP * NUM_DSP\n")
			header_file.write("`define ACCIDW					$clog2(2*NUM_ACCUM)\n")
			header_file.write("`define VRFAW     			$clog2(VRFD)\n")     
			header_file.write("`define MRFAW     			$clog2(MRFD)\n")     
			header_file.write("`define NMFU      			2\n")                
			header_file.write("`define NVRF      			NTILE+1+(2*NMFU)\n") 
			header_file.write("`define NMRF      			NTILE*NDPE\n")       
			header_file.write("`define NSIZE     			`max(VRFD, MRFD)\n")
			header_file.write("`define NSIZEW    			$clog2(NSIZE)+1\n")
			header_file.write("`define NTAG      			"+str(max_tag)+"\n")
			header_file.write("`define NTAGW     			$clog2(NTAG)\n")
			header_file.write("`define MIW_MVU				3*VRFAW+2*NSIZEW+MRFAW+NSIZEW+NTAGW+1\n")
			header_file.write("`define UIW_MVU   			8+NTAGW+MRFAW+1+VRFIDW+VRFAW\n")
			header_file.write("`define MIW_EVRF  			3*VRFAW+NSIZEW+1+NTAGW+3\n")
			header_file.write("`define UIW_EVRF  			VRFAW+2+NTAGW\n")
			header_file.write("`define MIW_MFU   			6*VRFAW+NSIZEW+NTAGW+9\n")
			header_file.write("`define UIW_MFU   			VRFAW+VRFAW+NTAGW+6\n")
			header_file.write("`define MIW_LD    			(2*NVRF)+6*VRFAW+NSIZEW+6\n")
			header_file.write("`define UIW_LD    			(2*NVRF)+VRFAW+VRFAW+4\n")
			header_file.write("`define MICW     				MIW_MVU+MIW_EVRF+(2*MIW_MFU)+MIW_LD\n")
			header_file.write("`define WB_LMT    			QDEPTH/2\n")        
			header_file.write("`define WB_LMTW   			$clog2(WB_LMT)+1\n") 
			if(self.flow_opts['rtl_sim'] == 1):
				header_file.write("`define SIM_FLAG				1\n")
			else:
				header_file.write("`define SIM_FLAG				0\n")
			header_file.write("`define PRECISION				EW\n")
			header_file.write("`define BRAM_RD_LATENCY 	2\n")
			header_file.write("`define INST_ADDRW			$clog2(INST_DEPTH)\n")
			header_file.write("`define CACHELINE_SIZE		512\n")
			header_file.write("`define MDATA_SIZE			16\n")
			header_file.write("`define ROB_DEPTH				INPUT_BUFFER_SIZE\n")
			header_file.write("`define ROB_ADDRW				$clog2(ROB_DEPTH)\n")
			header_file.write("`define FILLED_MRFD			"+str(mrf_filled_depth)+"\n")
			header_file.write("`define NUM_INPUTS			"+str(len(self.ibuf_q))+"\n")
			header_file.write("`define NUM_OUTPUTS			"+str(len(self.golden_obuf_q))+"\n")
			if(self.flow_opts['rtl_sim'] == 1):
				header_file.write("`define DEPLOY					0\n\n")
			else:
				header_file.write("`define DEPLOY					1\n\n")
			header_file.write("/***********************************/\n")
			header_file.write("/* 	      MACRO DEFINITIONS       */\n")
			header_file.write("/***********************************/\n")
			if(self.flow_opts['rtl_sim'] == 1):
				header_file.write("`define DISPLAY_MVU\n")
				header_file.write("`define DISPLAY_MVU_TILE\n")
				header_file.write("`define DISPLAY_EVRF\n")
				header_file.write("`define DISPLAY_MFU\n")
				header_file.write("`define DISPLAY_LD\n")
				header_file.write("`define DISPLAY_INST\n\n")
			header_file.write("// NPU Instruction definition\n")
			header_file.write("`define mvu_minst(minst_chain)  \\\n")
			header_file.write("    ``minst_chain``[MIW_LD+(2*MIW_MFU)+MIW_EVRF+:MIW_MVU]\n")
			header_file.write("`define evrf_minst(minst_chain) \\\n")
			header_file.write("    ``minst_chain``[MIW_LD+(2*MIW_MFU)+:MIW_EVRF]\n")
			header_file.write("`define mfu0_minst(minst_chain) \\\n")
			header_file.write("    ``minst_chain``[MIW_LD+MIW_MFU+:MIW_MFU]\n")
			header_file.write("`define mfu1_minst(minst_chain) \\\n")
			header_file.write("    ``minst_chain``[MIW_LD+:MIW_MFU]\n")
			header_file.write("`define ld_minst(minst_chain)   \\\n")
			header_file.write("    ``minst_chain``[0+:MIW_LD]\n\n")
			header_file.write("// MVU macro-instruction definition\n")
			header_file.write("`define mvu_minst_vrf_base0(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+NSIZEW+2*VRFAW +:VRFAW]\n")
			header_file.write("`define mvu_minst_vrf_base1(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+NSIZEW+VRFAW +:VRFAW]\n")
			header_file.write("`define mvu_minst_vrf_base2(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+NSIZEW +:VRFAW]\n")
			header_file.write("`define mvu_minst_vrf_size(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+2*NSIZEW+MRFAW+:NSIZEW]\n")
			header_file.write("`define mvu_minst_mrf_base(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+2*NSIZEW+:MRFAW]\n")
			header_file.write("`define mvu_minst_mrf_size(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+NSIZEW+:NSIZEW]\n")
			header_file.write("`define mvu_minst_words_per_row(minst) \\\n")
			header_file.write("    ``minst``[1+NTAGW+:NSIZEW]\n")
			header_file.write("`define mvu_minst_tag(minst) \\\n")
			header_file.write("    ``minst``[1+:NTAGW]\n")
			header_file.write("`define mvu_minst_op(minst) \\\n")
			header_file.write("    ``minst``[0+:1]\n\n")
			header_file.write("// MVU micro-instruction definition\n")
			header_file.write("`define mvu_uinst_vrf_addr(uinst) \\\n")
			header_file.write("	``uinst``[8+NTAGW+MRFAW+1+VRFIDW +:VRFAW]\n")
			header_file.write("`define mvu_uinst_vrf_rd_id(uinst) \\\n")
			header_file.write("	``uinst``[8+NTAGW+MRFAW+1 +:VRFIDW]\n")
			header_file.write("`define mvu_uinst_reg_sel(uinst) \\\n")
			header_file.write("	``uinst``[8+NTAGW+MRFAW +:1]\n")
			header_file.write("`define mvu_uinst_mrf_addr(uinst) \\\n")
			header_file.write("	``uinst``[8+NTAGW +:MRFAW]\n")
			header_file.write("`define mvu_uinst_tag(uinst) \\\n")
			header_file.write("	``uinst``[8+:NTAGW]\n")
			header_file.write("`define mvu_uinst_acc_op(uinst)   \\\n")
			header_file.write("	``uinst``[6+:2]\n")
			header_file.write("`define mvu_uinst_acc_size(uinst) \\\n")
			header_file.write("    ``uinst``[1+:5]\n")
			header_file.write("`define mvu_uinst_vrf_en(uinst) \\\n")
			header_file.write("    ``uinst``[0+:1]\n\n")
			header_file.write("// eVRF macro-instruction definition\n")
			header_file.write("`define evrf_minst_vrf_base0(minst) \\\n")
			header_file.write("    ``minst``[3+NTAGW+1+NSIZEW+2*VRFAW+:VRFAW]\n")
			header_file.write("`define evrf_minst_vrf_base1(minst) \\\n")
			header_file.write("    ``minst``[3+NTAGW+1+NSIZEW+VRFAW+:VRFAW]\n")
			header_file.write("`define evrf_minst_vrf_base2(minst) \\\n")
			header_file.write("    ``minst``[3+NTAGW+1+NSIZEW+:VRFAW]\n")
			header_file.write("`define evrf_minst_vrf_size(minst) \\\n")
			header_file.write("    ``minst``[3+NTAGW+1+:NSIZEW]\n")
			header_file.write("`define evrf_minst_src_sel(minst) \\\n")
			header_file.write("    ``minst``[3+NTAGW+:1]\n")
			header_file.write("`define evrf_minst_tag(minst) \\\n")
			header_file.write("    ``minst``[3+:NTAGW]\n")
			header_file.write("`define evrf_minst_op(minst) \\\n")
			header_file.write("    ``minst``[2+:1]\n")
			header_file.write("`define evrf_minst_batch(minst) \\\n")
			header_file.write("    ``minst``[0+:2]\n\n")
			header_file.write("// eVRF micro-instruction definition\n")
			header_file.write("`define evrf_uinst_vrf_addr(uinst) \\\n")
			header_file.write("    ``uinst``[NTAGW+2+:VRFAW]\n")
			header_file.write("`define evrf_uinst_src_sel(uinst)   \\\n")
			header_file.write("    ``uinst``[NTAGW+:2]\n")
			header_file.write("`define evrf_uinst_tag(uinst)   \\\n")
			header_file.write("    ``uinst``[0+:NTAGW]\n\n")
			header_file.write("//  MFU macro-instruction definition\n")
			header_file.write("`define mfu_minst_vrf0_base0(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+NSIZEW+5*VRFAW+:VRFAW]\n")
			header_file.write("`define mfu_minst_vrf0_base1(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+NSIZEW+4*VRFAW+:VRFAW]\n")
			header_file.write("`define mfu_minst_vrf0_base2(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+NSIZEW+3*VRFAW+:VRFAW]\n")
			header_file.write("`define mfu_minst_vrf1_base0(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+NSIZEW+2*VRFAW+:VRFAW]\n")
			header_file.write("`define mfu_minst_vrf1_base1(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+NSIZEW+VRFAW+:VRFAW]\n")
			header_file.write("`define mfu_minst_vrf1_base2(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+NSIZEW+:VRFAW]\n")
			header_file.write("`define mfu_minst_size(minst) \\\n")
			header_file.write("    ``minst``[9+NTAGW+:NSIZEW]\n")
			header_file.write("`define mfu_minst_tag(minst) \\\n")
			header_file.write("    ``minst``[9+:NTAGW]\n")
			header_file.write("`define mfu_minst_op(minst) \\\n")
			header_file.write("    ``minst``[2+:7]\n")
			header_file.write("`define mfu_minst_batch(minst) \\\n")
			header_file.write("    ``minst``[0+:2]\n\n")
			header_file.write("// MFU micro-instruction definition\n")
			header_file.write("`define mfu_uinst_vrf0_addr(uinst) \\\n")
			header_file.write("    ``uinst``[6+NTAGW+VRFAW+:VRFAW]\n")
			header_file.write("`define mfu_uinst_vrf1_addr(uinst) \\\n")
			header_file.write("    ``uinst``[6+NTAGW+:VRFAW]\n")
			header_file.write("`define mfu_uinst_tag(uinst) \\\n")
			header_file.write("    ``uinst``[6+:NTAGW]\n")
			header_file.write("`define mfu_uinst_func_op(uinst) \\\n")
			header_file.write("    ``uinst``[0+:6]\n")
			header_file.write("`define mfu_uinst_act_op(uinst) \\\n")
			header_file.write("    ``uinst``[4+:2]\n")
			header_file.write("`define mfu_uinst_add_op(uinst) \\\n")
			header_file.write("    ``uinst``[1+:3]\n")
			header_file.write("`define mfu_uinst_mul_op(uinst) \\\n")
			header_file.write("    ``uinst``[0+:1]\n\n")
			header_file.write("// LD macro-instruction definition\n")
			header_file.write("`define ld_minst_vrf_id(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+6*VRFAW+:2*NVRF]\n")
			header_file.write("`define ld_minst_vrf0_base0(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+5*VRFAW+:VRFAW]\n")
			header_file.write("`define ld_minst_vrf0_base1(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+4*VRFAW+:VRFAW]\n")
			header_file.write("`define ld_minst_vrf0_base2(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+3*VRFAW+:VRFAW]\n")
			header_file.write("`define ld_minst_vrf1_base0(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+2*VRFAW+:VRFAW]\n")
			header_file.write("`define ld_minst_vrf1_base1(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+VRFAW+:VRFAW]\n")
			header_file.write("`define ld_minst_vrf1_base2(minst) \\\n")
			header_file.write("    ``minst``[6+NSIZEW+:VRFAW]\n")
			header_file.write("`define ld_minst_size(minst) \\\n")
			header_file.write("    ``minst``[6+:NSIZEW]\n")
			header_file.write("`define ld_minst_src_sel(minst) \\\n")
			header_file.write("    ``minst``[5+:1]\n")
			header_file.write("`define ld_minst_op(minst) \\\n")
			header_file.write("    ``minst``[4+:1]\n")
			header_file.write("`define ld_minst_batch(minst) \\\n")
			header_file.write("    ``minst``[2+:2]\n")
			header_file.write("`define ld_minst_interrupt(minst) \\\n")
			header_file.write("    ``minst``[1+:1]\n")
			header_file.write("`define ld_minst_report_to_host(minst) \\\n")
			header_file.write("	``minst``[0+:1]\n\n")
			header_file.write("// LD micro-instruction definition\n")
			header_file.write("`define ld_uinst_vrf_id(uinst) \\\n")
			header_file.write("    ``uinst``[4+VRFAW+VRFAW+:2*NVRF]\n")
			header_file.write("`define ld_uinst_vrf0_addr(uinst) \\\n")
			header_file.write("    ``uinst``[4+VRFAW+:VRFAW]\n")
			header_file.write("`define ld_uinst_vrf1_addr(uinst) \\\n")
			header_file.write("    ``uinst``[4+:VRFAW]\n")
			header_file.write("`define ld_uinst_src_sel(uinst) \\\n")
			header_file.write("    ``uinst``[3+:1]\n")
			header_file.write("`define ld_uinst_last(uinst) \\\n")
			header_file.write("    ``uinst``[2+:1]\n")
			header_file.write("`define ld_uinst_interrupt(uinst) \\\n")
			header_file.write("    ``uinst``[1+:1]\n")
			header_file.write("`define ld_uinst_report_to_host(uinst) \\\n")
			header_file.write("    ``uinst``[0+:1]\n\n")
			header_file.write("`endif\n")

	'''
	This function is used to launch the RTL simulation in case specified by the user. This requires 
	Synopsys VCS to be set up properly
	'''
	def launch_rtl_sim(self, checkpoint_name, num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth, max_tag, mrf_filled_depth):
		#self.write_verilog_header_file(num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth, max_tag, mrf_filled_depth)
		subprocess.call('cd ../rtl; sed -i -e \'s/\r$//\' run_sim.sh; ./run_sim.sh; cd ../compiler', shell=True)

	'''
	This function uses the FSim checkpoints to generate MRF, instructions, input, and output files for PCIe demo.
	'''
	def dump_pcie_files(self, checkpoint_name, num_tiles, num_dpes, num_lanes, program_loops):
		precision_in = 8
		precision_out = 32
		mask = int(np.power(2, precision_in)) - 1

		# MRF file
		src_path = './dump/' + checkpoint_name + '-mvu_mrf'
		with open (src_path,'rb') as src_file:
			mrfs = np.load(src_file)
			file_path = './pcie_dump/mrfs.dat'
			with open (file_path, 'w') as mrf_file:
				mrf_file.write(str(num_tiles*num_dpes) + ' ' + str(self.mrf_filled_depth) + ' ' + str(num_lanes) + '\n')
				for i in range(num_tiles):
					for j in range(num_dpes):
						for k in range(self.mrf_filled_depth):
							for l in range(num_lanes):
								mrf_file.write(str(mrfs[i][j][k][l]) + ' ')
							mrf_file.write('\n')

		# Inputs file
		src_path = './dump/' + checkpoint_name + '-output'
		outputs_file = open(src_path,'rb')
		outputs = np.load(outputs_file)
		outputs_file.close()
		src_path = './dump/' + checkpoint_name + '-input'
		with open(src_path,'rb') as src_file:
			inputs = np.load(src_file)
			file_path = './pcie_dump/inputs.dat'
			with open (file_path,'w') as inputs_file:
				inputs_file.write(str(2 * program_loops * len(inputs)) + ' ' + str(num_lanes) + ' ' + str(2 * program_loops * len(outputs)) + ' ' + str(num_lanes) + ' ' + str(2 * len(inputs)) + '\n')
				for l in range(program_loops):
					for i in range(len(inputs)):
						for j in range(num_lanes):
							inputs_file.write(str(inputs[i][j]) + ' ')
						inputs_file.write('\n')
						for j in range(num_lanes):
							inputs_file.write(str(inputs[i][j]) + ' ')
						inputs_file.write('\n')

		# Instructions
		self.set_inst_params()
		src_path = './dump/' + checkpoint_name + '-inst'
		with open(src_path,'rb') as src_file:
			insts = np.load(src_file, allow_pickle=True, fix_imports=True, encoding='latin1')
			file_path = './pcie_dump/instructions_bin.dat'
			with open (file_path,'w') as inst_file:
				inst_file.write(str(len(insts)+1) + '\n')
				for i, inst in enumerate(insts):
					self.set_inst(inst)
					inst_str = bin(self.minst_chain & int(pow(2, self.MICW)-1))[2:].zfill(512)
					inst_file.write(inst_str)
					inst_file.write('\n')
				inst_str = '1'*self.MICW
				inst_file.write(inst_str)
				inst_file.write('\n')

			file_path = './pcie_dump/instructions.dat'
			with open (file_path,'w') as inst_file:
				inst_byte_width = int(math.ceil(self.MICW * 1.0 / 8.0))
				inst_file.write(str(len(insts)+1) + ' ' + str(inst_byte_width) + '\n')
				for i, inst in enumerate(insts):
					self.set_inst(inst)
					inst_str = bin(self.minst_chain & int(pow(2, self.MICW)-1))[2:].zfill(inst_byte_width*8)
					for j in range(inst_byte_width):
						partial_inst_str = inst_str[(inst_byte_width*8) - ((j+1)*8): (inst_byte_width*8) - (j*8)];
						value = 0;
						for k in range(8):
							if (partial_inst_str[7-k] == '1'):
								value += int(pow(2,k))
						inst_file.write(str(value) + ' ')
					inst_file.write('\n')
				inst_file.write(str(program_loops % 256) + ' ')
				inst_file.write(str(program_loops >> 8) + ' ')
				for i in range(inst_byte_width-2):
					inst_file.write('255 ')
				inst_file.write('\n')

		# Outputs file
		mask = int(np.power(2, precision_out)) - 1
		file_path = './pcie_dump/outputs.dat'
		with open (file_path,'w') as outputs_file:
			for l in range(program_loops):
				for i in range(len(outputs)):
					for j in range(num_lanes):
						outputs_file.write(str(outputs[i][j] & int(pow(2, 8)-1)) + ' ')
					outputs_file.write('\n')
					for j in range(num_lanes):
						outputs_file.write(str(outputs[i][j] & int(pow(2, 8)-1)) + ' ')
					outputs_file.write('\n')

	'''
	This function uses the FSim checkpoints to generate low-level binary NPU checkpoints. These
	checkpoints will later be used to generate the PAC C header file. Make sure to set the precision_in
	and precision_out to correct number of bits in case the RTL is changed (parameters EW & ACCW in RTL).
	'''
	def dump_binary_files(self, checkpoint_name, num_tiles, num_dpes, num_lanes):
		precision_in = 8
		precision_out = 32
		mask = int(np.power(2, precision_in)) - 1

		# Dump MRF data
		path = './dump/' + checkpoint_name + '-mvu_mrf'
		with open (path,'rb') as mrffile:
			mrfs = np.load(mrffile)
			for i in range(num_tiles):
				for j in range(num_dpes):
					dump_path = './pac_dump/mvu-mrf' + format(i * num_dpes + j, '03d')
					with open (dump_path,'wb') as dump_file:
						for k in range(len(mrfs[i][j])):
							val = 0
							for l in range(num_lanes):
								temp = mrfs[i][j][k][l].item()
								temp &= mask
								val += (temp << (precision_in * l))
							val_str = bin(val)[2:].zfill(num_lanes * precision_in)
							dump_file.write(val_str.encode())
							dump_file.write('\n'.encode())

		# Dump input vectors
		path = './dump/' + checkpoint_name + '-input'
		with open(path,'rb') as inputfile:
			inputs = np.load(inputfile)
			dump_path = './pac_dump/input'
			with open (dump_path,'wb') as dump_file:
				for i in range(len(inputs)):
					val = 0
					for j in range(num_lanes):
						temp = inputs[i][j].item() 
						if((((temp >> (precision_in-1)) & 0x1) == 0x1)):
							temp -= int(np.power(2, precision_in))
						temp &= mask 
						val +=  (temp << (precision_in * j))
					val_str = hex(val)[2:].zfill(int(num_lanes * precision_in / 4))
					dump_file.write(val_str.encode())
					dump_file.write('\n'.encode())

		# Dump instructions
		self.set_inst_params()
		path = './dump/' + checkpoint_name + '-inst'
		with open(path,'rb') as instfile:
			insts = np.load(instfile, allow_pickle=True, fix_imports=True, encoding='latin1')
			dump_path = './pac_dump/top_sched'
			with open (dump_path,'wb') as dump_file:
				for i, inst in enumerate(insts):
					self.set_inst(inst)
					inst_str = bin(self.minst_chain & int(pow(2, self.MICW)-1))[2:].zfill(self.MICW)
					dump_file.write(inst_str.encode())
					dump_file.write('\n'.encode())
				inst_str = '1'*self.MICW
				dump_file.write(inst_str.encode())
				dump_file.write('\n'.encode())

		# Dump output vectors
		mask = int(np.power(2, precision_in)) - 1  #Changed for demo
		path = './dump/' + checkpoint_name + '-output'
		with open(path,'rb') as outputfile:
			outputs = np.load(outputfile)
			dump_path = './pac_dump/output'
			with open (dump_path,'wb') as dump_file:
				for i in range(len(outputs)):
					val = 0	            
					for j in range(num_lanes):
						temp = outputs[i][j].item()
						temp &= mask
						val += (temp << (precision_in * j)) #Changed for demo
					val_str = hex(val)[2:].zfill(int(num_lanes * precision_in / 4)) #Changed for demo
					dump_file.write(val_str.encode())
					dump_file.write('\n'.encode())

	def launch_perf_sim(self, num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth, verbose = False):
		num_tiles = len(self.fsim.mvu_mrfs)
		num_dpes = len(self.fsim.mvu_mrfs[0])
		mrf_depth = len(self.fsim.mvu_mrfs[0][0])
		num_lanes = len(self.fsim.mvu_mrfs[0][0][0])
		vrf_depth = self.arch_params['vrf_depth']

		dump_path = '../simulator/inc/defines.h'
		with open(dump_path, 'w') as defines:
			defines.write('#ifndef DEFINES_H_\n#define DEFINES_H_\n\n')
			defines.write('#include <string>\n#include <iostream>\n\n')

			defines.write('// Debug Messages\n')
			defines.write('#define VERBOSE_OP 1\n')
			defines.write('#define VERBOSE_MVU 1\n')
			defines.write('#define VERBOSE_LD_OUT 0\n\n')

			defines.write('// Architecture Parameters\n')
			defines.write('#define TILES ' + str(num_tiles) + '\n')
			defines.write('#define DPES ' + str(num_dpes) + '\n')
			defines.write('#define LANES ' + str(num_lanes) + '\n')
			defines.write('#define MVU_VRF_DEPTH ' + str(vrf_depth) + '\n')
			defines.write('#define MVU_MRF_DEPTH ' + str(mrf_depth) + '\n')
			defines.write('#define EVRF_DEPTH ' + str(vrf_depth) + '\n')
			defines.write('#define MFU_VRF0_DEPTH ' + str(vrf_depth) + '\n')
			defines.write('#define MFU_VRF1_DEPTH ' + str(vrf_depth) + '\n')
			defines.write('#define FIFO_DEPTH 512\n\n')

			defines.write('// Latency Parameters\n')
			defines.write('#define DPE_MULT_LATENCY 2\n')
			defines.write('#define DPE_ADDER_LATENCY 1\n')
			defines.write('#define RF_WRITE_LATENCY 1\n')
			defines.write('#define RF_READ_LATENCY 1\n')
			defines.write('#define MRF_TO_DPE_LATENCY 8\n')
			defines.write('#define VRF_TO_DPE_LATENCY 8\n')
			defines.write('#define MVU_ACCUM_LATENCY 4\n')
			defines.write('#define MVU_REDUCTION_LATENCY (unsigned int)(ceil(log2(TILES))+5)\n')
			defines.write('#define MFU_ACT_LATENCY 3\n')
			defines.write('#define MFU_ADD_LATENCY 3\n')
			defines.write('#define MFU_MUL_LATENCY 3\n')
			defines.write('#define MFU_LATENCY MFU_ACT_LATENCY+MFU_ADD_LATENCY+MFU_MUL_LATENCY\n')
			defines.write('#define LD_WB_LATENCY 5\n\n')

			defines.write('// Precision\n')
			defines.write('#define TYPE int\n')
			defines.write('#define INPUT_PRECISION 8\n')
			defines.write('#define MASK_TRUNCATE 0x000000FF\n')
			defines.write('#define MASK_SIGN_EXTEND 0xFFFFFF00\n')
			defines.write('#define MASK_SIGN_CHECK 0x00000080\n\n')

			defines.write('#define LOG(module_name, msg) do { \\\n')
			defines.write('std::cout << "[" << module_name << " @ " << cycle_count << "]: " << msg << std::endl; \\\n')
			defines.write('} while (0)\n\n')
			defines.write('#endif\n')

		for t in range(num_tiles):
			for d in range(num_dpes):
				dump_path = '../simulator/register_files/mrf_tile_'+str(t)+'_dpe_'+str(d)+'.txt'
				with open(dump_path, 'w') as dump_file:
					for m in range(mrf_depth):
						for l in range(num_lanes):
							dump_file.write(str(self.fsim.mvu_mrfs[t][d][m][l]) + ' ')
						dump_file.write('\n')

		dump_path = '../simulator/register_files/vrf_file.txt'
		num_inputs = len(self.ibuf_q)
		with open(dump_path, 'w') as dump_file:
			for i in range(num_inputs):
				for l in range(num_lanes):
					dump_file.write(str(self.ibuf_q[i][l]) + ' ')
				dump_file.write('\n')

		dump_path = '../simulator/register_files/py_output.txt'
		num_outputs = len(self.fsim.obuf_q)
		#mask = int(np.power(2, precision_out)) - 1
		with open(dump_path, 'w') as dump_file:
			for i in range(num_outputs):
				for l in range(num_lanes):
					dump_file.write(str(self.fsim.obuf_q[i][l]) + ' ')
				dump_file.write('\n')
	            
		dump_path = '../simulator/register_files/instructions.txt'
		num_inst = len(self.inst_q)
		with open(dump_path, 'w') as dump_file:
			for i in range(num_inst):
				inst = self.inst_q[i]
				
				# MVU macro-op
				if(inst.mvu_op_type == 'matvec'):
					dump_file.write('1 ')
				else:
					dump_file.write('0 ')
				dump_file.write(str(inst.mvu_vrf_rd_base[0]) + ' ')
				dump_file.write(str(inst.mvu_vrf_rd_base[1]) + ' ')
				dump_file.write(str(inst.mvu_vrf_rd_base[2]) + ' ')
				dump_file.write(str(inst.mvu_vrf_rd_sz) + ' ')
				dump_file.write(str(inst.mvu_mrf_rd_base) + ' ')
				dump_file.write(str(inst.mvu_mrf_rd_sz) + ' ')
				dump_file.write(str(inst.mvu_tag) + '\n')
				
				# eVRF macro-op
				if(inst.extvrf_op_type == 'move'):
					dump_file.write('1 0 ')
				elif(inst.extvrf_op_type == 'extvrf'):
					dump_file.write('1 1 ')
				else:
					dump_file.write('0 0 ')

				for i in range(inst.batch):
					dump_file.write(str(inst.extvrf_rd_base[i]) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')

				dump_file.write(str(inst.extvrf_rd_sz) + ' ')
				dump_file.write(str(inst.batch) + ' ')
				dump_file.write(str(inst.extvrf_tag) + '\n')
				
				# MFU0 macro-op
				if((inst.mfu0_act_op_type == 'nop') and (inst.mfu0_act_op_type == 'nop') \
				    and (inst.mfu0_act_op_type == 'nop')):
					dump_file.write('0 ')
				else:
					dump_file.write('1 ')
				dump_file.write(str(inst.mfu0_vrf_rd_size) + ' ')
				if(inst.mfu0_act_op_type == 'tanh'):
					dump_file.write('1 ')
				elif(inst.mfu0_act_op_type == 'sig'):
					dump_file.write('2 ')
				elif(inst.mfu0_act_op_type == 'relu'):
					dump_file.write('3 ')
				else:
					dump_file.write('0 ')
				if(inst.mfu0_add_op_type == 'add'):
					dump_file.write('1 ')
				elif(inst.mfu0_add_op_type == 'sub_a_b'):
					dump_file.write('2 ')
				elif(inst.mfu0_add_op_type == 'sub_b_a'):
					dump_file.write('3 ')
				else:
					dump_file.write('0 ')

				for addr in inst.mfu0_vrf0_rd_base:
					dump_file.write(str(addr) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')
				#dump_file.write(str(inst.mfu0_vrf0_rd_base) + ' ')

				if(inst.mfu0_mul_op_type == 'mul'):
					dump_file.write('1 ')
				else:
					dump_file.write('0 ')

				for addr in inst.mfu0_vrf1_rd_base:
					dump_file.write(str(addr) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')
				#dump_file.write(str(inst.mfu0_vrf1_rd_base) + ' ')

				dump_file.write(str(inst.batch) + ' ')
				dump_file.write(str(inst.mfu0_tag) + '\n')
				
				# MFU1 macro-op
				if((inst.mfu1_act_op_type == 'nop') and (inst.mfu1_act_op_type == 'nop') \
				    and (inst.mfu1_act_op_type == 'nop')):
					dump_file.write('0 ')
				else:
					dump_file.write('1 ')
				dump_file.write(str(inst.mfu1_vrf_rd_size) + ' ')
				if(inst.mfu1_act_op_type == 'tanh'):
					dump_file.write('1 ')
				elif(inst.mfu1_act_op_type == 'sig'):
					dump_file.write('2 ')
				elif(inst.mfu1_act_op_type == 'relu'):
					dump_file.write('3 ')
				else:
					dump_file.write('0 ')
				if(inst.mfu1_add_op_type == 'add'):
					dump_file.write('1 ')
				elif(inst.mfu1_add_op_type == 'sub_a_b'):
					dump_file.write('2 ')
				elif(inst.mfu1_add_op_type == 'sub_b_a'):
					dump_file.write('3 ')
				else:
					dump_file.write('0 ')

				for addr in inst.mfu1_vrf0_rd_base:
					dump_file.write(str(addr) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')
				#dump_file.write(str(inst.mfu1_vrf0_rd_base) + ' ')

				if(inst.mfu1_mul_op_type == 'mul'):
					dump_file.write('1 ')
				else:
					dump_file.write('0 ')

				for addr in inst.mfu1_vrf1_rd_base:
					dump_file.write(str(addr) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')
				#dump_file.write(str(inst.mfu1_vrf1_rd_base) + ' ')

				dump_file.write(str(inst.batch) + ' ')
				dump_file.write(str(inst.mfu1_tag) + '\n')
				
				# LD macro-op
				if(inst.loader_src == 'wb'):
					dump_file.write('1 0 ')
				elif(inst.loader_src == 'in'):
					dump_file.write('1 1 ')
				elif(inst.loader_src == 'flush'):
					dump_file.write('2 0 ')
				else:
					dump_file.write('0 0 ')
				dump_file.write(str(inst.vrf_id0_wr_size) + ' ')
				## DST0
				if((inst.vrf_id0_wr_size == 0) or (inst.loader_src == 'flush')):
					dump_file.write('0 ')
				else:
					dump_file.write('1 ')
				if(inst.vrf_id0_op.startswith('mvu')):
					vrf_id = re.search('mvu(.*)vrf', inst.vrf_id0_op)
					dump_file.write(vrf_id.group(1)[:-1] + ' ')
				elif(inst.vrf_id0_op == 'extvrf'):
					dump_file.write(str(num_tiles) + ' ')
				elif(inst.vrf_id0_op == 'mfu0.vrf0'):
					dump_file.write(str(num_tiles+1) + ' ')
				elif(inst.vrf_id0_op == 'mfu0.vrf1'):
					dump_file.write(str(num_tiles+2) + ' ')
				elif(inst.vrf_id0_op == 'mfu1.vrf0'):
					dump_file.write(str(num_tiles+3) + ' ')
				elif(inst.vrf_id0_op == 'mfu1.vrf1'):
					dump_file.write(str(num_tiles+4) + ' ')
				else:
					dump_file.write('0 ')

				for addr in inst.vrf_id0_wr_base:
					dump_file.write(str(addr) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')
				#dump_file.write(str(inst.vrf_id0_wr_base) + ' ')

				## DST1
				if((inst.vrf_id1_wr_size == 0) or (inst.loader_src == 'flush')):
					dump_file.write('0 ')
				else:
					dump_file.write('1 ')
				if(inst.vrf_id1_op.startswith('mvu')):
					vrf_id = re.search('mvu(.*)vrf', inst.vrf_id1_op)
					dump_file.write(vrf_id.group(1)[:-1] + ' ')
				elif(inst.vrf_id1_op == 'extvrf'):
					dump_file.write(str(num_tiles) + ' ')
				elif(inst.vrf_id1_op == 'mfu0.vrf0'):
					dump_file.write(str(num_tiles+1) + ' ')
				elif(inst.vrf_id1_op == 'mfu0.vrf1'):
					dump_file.write(str(num_tiles+2) + ' ')
				elif(inst.vrf_id1_op == 'mfu1.vrf0'):
					dump_file.write(str(num_tiles+3) + ' ')
				elif(inst.vrf_id1_op == 'mfu1.vrf1'):
					dump_file.write(str(num_tiles+4) + ' ')
				else:
					dump_file.write('0 ')

				for addr in inst.vrf_id1_wr_base:
					dump_file.write(str(addr) + ' ')
				for i in range(3-inst.batch):
					dump_file.write('0 ')
				#dump_file.write(str(inst.vrf_id1_wr_base) + ' ')

				dump_file.write(str(inst.batch) + ' ')
				if(inst.write_to_obuf == True):
					dump_file.write('1 \n')
				else:
					dump_file.write('0 \n')
	           
		dump_path = '../simulator/gen_done'
		with open(dump_path, 'w') as dump_file:
			dump_file.write('1')
		
		subprocess.call('./perf_sim.sh', shell=True)	


	def run_flow(self):
		self.end_npu_program()

		print('\n')
		if self.unsupported_layers:
			print(bcolors.FAIL + 'NPU compilation flow aborted. The following layers are not supported by NPU: ')
			print(self.unsupported_layers)
			print(bcolors.RESET)
			return False

		num_tiles = self.arch_params['tiles']
		num_dpes = self.arch_params['dpes']
		num_lanes = self.arch_params['lanes']
		vrf_depth = self.arch_params['vrf_depth']
		mrf_depth = self.arch_params['mrf_depth']

		checkpoint_name = self.flow_opts['checkpoint_name']
		pac_gen = self.flow_opts['pac']
		rtl_simulation = self.flow_opts['rtl_sim']
		perf_simulation = self.flow_opts['perf_sim']
		verbose = self.flow_opts['verbose']
		freq = self.flow_opts['freq']
		mif_gen = self.flow_opts['mif_gen']
		pcie_gen = self.flow_opts['pcie_gen']
		program_loops = self.flow_opts['program_loops']

		# Parameter checks
		if (num_tiles <= 0 or num_dpes <= 0 or num_lanes <= 0):
			print('One of the architecture parameters is set to zero or a negative number!')
			sys.exit(1)
		if (num_dpes % num_lanes != 0):
			print('Number of DPEs has to be a multiple of the number of lanes')
			sys.exit(1)

		# Make sure that dump files from previous runs are deleted
		if os.path.isfile('./pac_dump/mvu-mrf0'):
			subprocess.call('rm ./pac_dump/mvu-mrf*', shell=True)
		if os.path.isfile('./pac_dump/input'):
			subprocess.call('rm ./pac_dump/input', shell=True)
		if os.path.isfile('./pac_dump/output'):
			subprocess.call('rm ./pac_dump/output', shell=True)
		if os.path.isfile('./pac_dump/top_sched'):
			subprocess.call('rm ./pac_dump/top_sched', shell=True)
		if os.path.isfile('./pac_dump/top_sched.mif'):
			subprocess.call('rm ./pac_dump/top_sched.mif', shell=True)

		# Step 1: Compile NPU program written by the user in npu_program() function
		print(bcolors.HEADER + '=== Compiling NPU Program ===' + bcolors.RESET)
		print(bcolors.OKGREEN + 'NPU program compiled successfully! It contains ' + str(len(self.inst_q)) + ' NPU instruction(s)' + bcolors.RESET)

		# -------------------------------------------------------------------------

		# Step 2: Perform functional simulation using FSim
		print(bcolors.HEADER + '=== Performing Functional Simulation ===' + bcolors.RESET)
		self.fsim_npu_program(verbose)
		sys.stdout.write('Generating FSim checkpoints ... ')
		sys.stdout.flush()
		if os.path.isdir('./dump'):
			subprocess.call('rm -r ./dump', shell=True)
		checkpoints_count = self.generate_fsim_checkpoints(checkpoint_name, verbose)
		print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

		# -------------------------------------------------------------------------
		
		# Generate PCIe files
		if(pcie_gen):
			if os.path.isfile('./pcie_dump/mrfs.dat'):
				subprocess.call('rm ./pcie_dump/mrfs.dat', shell=True)
			if os.path.isfile('./pcie_dump/inputs.dat'):
				subprocess.call('rm ./pcie_dump/inputs.dat', shell=True)
			if os.path.isfile('./pcie_dump/outputs.dat'):
				subprocess.call('rm ./pcie_dump/outputs.dat', shell=True)
			if os.path.isfile('./pcie_dump/instructions.dat'):
				subprocess.call('rm ./pcie_dump/instructions.dat', shell=True)

			print(bcolors.HEADER + '=== Generating PCIE Files ===' + bcolors.RESET)
			thread1 = threading.Thread(target = self.dump_pcie_files, args = (checkpoint_name, num_tiles, num_dpes, num_lanes, program_loops))
			thread1.start()

			sys.stdout.write('Dumping MRF data ... ')
			sys.stdout.flush()
			mrf_file_name = './pcie_dump/mrfs.dat'
			while not os.path.isfile(mrf_file_name):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping inputs file ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pcie_dump/inputs.dat'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping instructions file ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pcie_dump/instructions.dat'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping outputs file ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pcie_dump/outputs.dat'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			thread1.join()
		# -------------------------------------------------------------------------

		# Step 3: Generate PAC C header file

		# Use the checkpoints generated by FSim (python data structures) to generate binary low-level NPU checkpoints
		if(pac_gen):
			print(bcolors.HEADER + '=== Generating PAC Header File ===' + bcolors.RESET)
			thread1 = threading.Thread(target = self.dump_binary_files, args = (checkpoint_name, num_tiles, num_dpes, num_lanes))
			thread1.start()

			sys.stdout.write('Dumping MRF data ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/mvu-mrf' + str(num_tiles * num_dpes - 1)):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping input vectors ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/input'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping instructions ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/input'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping output vectors ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/input'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			thread1.join()

			# Transform the binary low-level NPU checkpoints into the PAC header file format
			sys.stdout.write('Generating C header file ... ')
			sys.stdout.flush()
			transform_list_to_mif(num_lanes)
			generate_header_file(checkpoint_name)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			# After generating C header file, clean all the checkpoints created along the way
			subprocess.call('rm ./pac_dump/mvu-mrf* ./pac_dump/input ./pac_dump/output ./pac_dump/top_sched.mif', shell=True)

		# -------------------------------------------------------------------------
		# Generate MIF files
		if(mif_gen):
			print(bcolors.HEADER + '=== Generating MIF Files ===' + bcolors.RESET)
			thread1 = threading.Thread(target = self.dump_binary_files, args = (checkpoint_name, num_tiles, num_dpes, num_lanes))
			thread1.start()

			sys.stdout.write('Dumping MRF data ... ')
			sys.stdout.flush()
			if(num_tiles * num_dpes - 1 < 10):
				mrf_mif_name = './pac_dump/mvu-mrf00'
			elif(num_tiles * num_dpes - 1 < 100):
				mrf_mif_name = './pac_dump/mvu-mrf0'
			else:
				mrf_mif_name = './pac_dump/mvu-mrf'
			while not os.path.isfile(mrf_mif_name + str(num_tiles * num_dpes - 1)):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping input vectors ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/input'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping instructions ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/top_sched'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Dumping output vectors ... ')
			sys.stdout.flush()
			while not os.path.isfile('./pac_dump/output'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			thread1.join()

			# Transform the binary low-level NPU checkpoints into MIF files
			sys.stdout.write('Converting checkpoints to MIFs ... ')
			sys.stdout.flush()
			transform_list_to_mif(num_lanes)
			subprocess.call('rm ./pac_dump/input ./pac_dump/output', shell=True)
			if(os.path.isdir('../rtl/mif_files') == False):
				subprocess.call('mkdir ../rtl/mif_files', shell=True)
			subprocess.call('mv ./pac_dump/*.mif ../rtl/mif_files/', shell=True)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			self.write_verilog_header_file(num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth, self.arch_params['max_tag'], self.mrf_filled_depth)

		# -------------------------------------------------------------------------
		# Step 4: Perform RTL simulation
		if(rtl_simulation == 1):
			if os.path.isfile('../rtl/init_done'):
				subprocess.call('rm ../rtl/init_done', shell=True)
			if os.path.isfile('../rtl/mrf_done'):
				subprocess.call('rm ../rtl/mrf_done', shell=True)
			if os.path.isfile('../rtl/input_done'):
				subprocess.call('rm ../rtl/input_done', shell=True)
			if os.path.isfile('../rtl/sim_done'):
				subprocess.call('rm ../rtl/sim_done', shell=True)

			print(bcolors.HEADER + '=== Launching RTL Simulation ===' + bcolors.RESET)

			start_time = time.time()

			thread1 = threading.Thread(target = self.launch_rtl_sim, args = (checkpoint_name, num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth, self.arch_params['max_tag'], self.mrf_filled_depth))
			thread1.start()

			sys.stdout.write('Setting up simulation ... ')
			sys.stdout.flush()
			while not os.path.isfile('../rtl/init_done'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			'''sys.stdout.write('Loading MRFs ... ')
			sys.stdout.flush()
			while not os.path.isfile('../rtl/mrf_done'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)'''

			sys.stdout.write('Loading inputs ... ')
			sys.stdout.flush()
			while not os.path.isfile('../rtl/input_done'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Running simulation ... ')
			sys.stdout.flush()
			while not os.path.isfile('../rtl/sim_done'):
				time.sleep(0.2)

			end_time = time.time()
			time.sleep(2)
			
			file = open('../rtl/sim_done', 'r')
			lines = file.readlines()
			if (lines[0] == 'PASS\n'):
				runtime_ms = int(lines[1]) * 1.0 / (freq*1000)
				print(bcolors.OKGREEN + 'PASSED (' + lines[1] + ' cycles - ' + str(round(runtime_ms, 5)) + ' ms - ' + str(round(self.ops/(runtime_ms/1000)/1000000000000, 2)) + ' TOPS)' + bcolors.RESET)
				print(bcolors.OKBLUE + 'RTL simulation took ' + str(round(end_time-start_time, 3)) + ' sec' + bcolors.RESET)
			else:
				print(bcolors.FAIL + 'FAILED' + bcolors.RESET)

			thread1.join()

		# -------------------------------------------------------------------------

		# Step 5: Perform Performance simulation
		if(perf_simulation == 1):
			if os.path.isfile('../simulator/gen_done'):
				subprocess.call('rm ../simulator/gen_done', shell=True)
			if os.path.isfile('../simulator/sim_done'):
				subprocess.call('rm ../simulator/sim_done', shell=True)

			print(bcolors.HEADER + '=== Launching C++ Performance Simulation ===' + bcolors.RESET)

			thread1 = threading.Thread(target = self.launch_perf_sim, args = (num_tiles, num_dpes, num_lanes, vrf_depth, mrf_depth))
			thread1.start()

			sys.stdout.write('Generating simulation files ... ')
			sys.stdout.flush()
			while not os.path.isfile('../simulator/gen_done'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Building simulator ... ')
			sys.stdout.flush()
			while not os.path.isfile('../simulator/npu_sim'):
				time.sleep(0.2)
			print(bcolors.OKGREEN + 'DONE' + bcolors.RESET)

			sys.stdout.write('Running simulation ... ')
			sys.stdout.flush()
			while not os.path.isfile('../simulator/sim_done'):
				time.sleep(0.2)
			time.sleep(2)

			file = open('../simulator/sim_done', 'r')
			lines = file.readlines()
			if (lines[0] == 'PASS\n'):
				runtime_ms = int(lines[1]) * 1.0 / (freq*1000)
				print(bcolors.OKGREEN + 'PASSED (' + str(int(lines[1])) + ' cycles - ' + str(round(runtime_ms, 5)) + \
					' ms - ' + str(round(self.ops/(runtime_ms/1000)/1000000000000, 2)) + ' TOPS)' + bcolors.RESET)
				sim_time = int(lines[2])
				print(bcolors.OKBLUE + 'C++ simulation took ' + str(round(sim_time, 3)) + ' sec' + bcolors.RESET)
			else:
				print(bcolors.FAIL + 'FAILED' + bcolors.RESET)

			thread1.join()

		# -------------------------------------------------------------------------

		subprocess.call('rm -r ./dump', shell=True)
		subprocess.call('rm -rf __pycache__/', shell=True)
		if(perf_simulation == 1):
			subprocess.call('rm ../simulator/make_log', shell=True)
			subprocess.call('rm ../simulator/make_clean_log', shell=True)
			subprocess.call('rm ../simulator/gen_done', shell=True)
			subprocess.call('rm ../simulator/sim_done', shell=True)
			subprocess.call('rm ../simulator/register_files/*.txt', shell=True)
		if(rtl_simulation == 1):
			subprocess.call('rm ../rtl/*_done', shell=True)
			subprocess.call('rm ../rtl/mif_files/*.mif', shell=True)
		return True

##############################################################################################
###################################### END OF CLASS NPU ######################################
##############################################################################################

'''
The vector class defines the main operands of any NPU program. Each vector has the following parameters:
- name: used for figuring out dependencies, detecting hazards and handling tags
- dimension_x: the real vector length specified by user (without padding)
- space_name: the memory space this vector belongs to (e.g. mvu_vrf)
- alloc_addr: the starting address of this vector
- word_count: the number of memory words this vector occupies in the specified space
- useful_data: the vector data without padding
- data: the vector data with padding to match native dimensions
'''
class vector:
	def __init__(self, name, dimension_x, space_name, tiles, dpes, lanes, in_data_type, ac_data_type, data=[]):
		self.name = name
		self.dimension_x = dimension_x
		self.space_name = space_name
		self.alloc_addr = -1
		if space_name == 'mvu_vrf':
			dimension_x_padded = int(math.ceil(1.0 * dimension_x / tiles / lanes) * tiles * lanes)
			self.word_count = int(dimension_x_padded / tiles / lanes)
			self.useful_data = data
			self.data = np.zeros(dimension_x_padded, dtype=in_data_type)
			self.data[:len(self.useful_data)] = self.useful_data 
		else:
			if(dimension_x < (dpes * lanes / 10 * 3)):
				dimension_x_padded = int(math.ceil(1.0 * dimension_x / dpes / (3 * lanes/10)) * dpes * (3 * lanes/10))
			else:
				dimension_x_padded = int(math.ceil(1.0 * dimension_x / dpes) * dpes)
			self.word_count = int(dimension_x_padded / lanes)
			self.useful_data = data
			self.data = np.zeros(dimension_x_padded, dtype=ac_data_type)
			self.data[:len(self.useful_data)] = self.useful_data 
	
	# This function is used to change the data of a vector. Useful when loading new inputs to the same vector location.
	def change_data(self, data):
		assert len(data) == len(self.useful_data), 'Vector length is incompatible!'
		self.useful_data = data
		self.data[:len(self.useful_data)] = self.useful_data 

	# Print some information about the vector
	def info(self):
		print('Vector ' + self.name + ' , Size: ' + str(self.dimension_x) + ' element(s), Mem Space: ' +  self.space_name + ', Base Address: ' + str(self.alloc_addr) + ', Word Count: ' + str(self.word_count))

'''
The matrix class defines the persistent weight matrices. It has same parameters as the vector class in addition to:
- dimension_y: the M dimension of the matrix as specified by the user (vertical dimension -- without padding)
'''
class matrix:
	def __init__(self, name, dimension_x, dimension_y, space_name, tiles, dpes, lanes, in_data_type, data):
		self.name = name
		self.dimension_x = dimension_x
		self.dimension_y = dimension_y
		self.space_name = space_name
		if(dimension_y < (dpes * (3 * lanes/10))):
			self.dimension_y_padded = int(math.ceil(1.0 * dimension_y / dpes / (3 * lanes/10)) * dpes * (3 * lanes/10))
		else:
			self.dimension_y_padded = int(math.ceil(1.0 * dimension_y / dpes) * dpes)
		self.dimension_x_padded = int(math.ceil(1.0 * dimension_x / tiles / lanes) * tiles * lanes)
		self.word_count = int(self.dimension_x_padded / tiles / lanes) * int(self.dimension_y_padded / dpes)
		self.alloc_addr = -1
		self.useful_data = data
		self.data = np.zeros((self.dimension_y_padded, self.dimension_x_padded), dtype=in_data_type)
		self.data[:self.useful_data.shape[0],:self.useful_data.shape[1]] = self.useful_data 

	# Print some information about the matrix	
	def info(self):
		print('Matrix ' + self.name + ' , Size: ' + str(self.dimension_x) + 'x' + str(self.dimension_y) + ' element(s), Mem Space: ' +  self.space_name + ', Base Address: ' + str(self.alloc_addr) + ', Word Count: ' + str(self.word_count))

# Used for colored printing to the terminal.
class bcolors:
	HEADER = '\033[95m'
	OKBLUE = '\033[94m'
	OKGREEN = '\033[92m'
	WARNING = '\033[93m'
	FAIL = '\033[91m'
	ENDC = '\033[0m'
	BOLD = '\033[1m'
	UNDERLINE = '\033[4m'
	RESET = "\033[0;0m"

def transform_list_to_mif(num_lanes):
	dump_dir = './pac_dump/'
	num_dsps = int(num_lanes / 10)

	for filename in os.listdir(dump_dir):
		if((filename == 'top_sched') or (filename == 'input')):
			dump_file = open(dump_dir+filename, 'r')
			mif_file = open(dump_dir+filename+'.mif', 'w')
			
			depth = 0
			for line in dump_file:
				depth = depth + 1
			width = int(len(line.strip()))
			dump_file.close()

			mif_file.write('DEPTH = ' + str(depth) + ';\n')
			if((filename == 'input') or (filename == 'output')):
				mif_file.write('WIDTH = ' + str(width*4) + ';\n')
			else:
				mif_file.write('WIDTH = ' + str(width) + ';\n')
			mif_file.write('ADDRESS_RADIX = DEC;\n')
			if((filename == 'input') or (filename == 'output')):
				mif_file.write('DATA_RADIX = HEX;\n')
			else:
				mif_file.write('DATA_RADIX = BIN;\n')
			mif_file.write('CONTENT\n')
			mif_file.write('BEGIN\n')
			
			line_num = 0
			dump_file = open(dump_dir+filename, 'r')
			for line in dump_file:
				mif_file.write(str(line_num) + ': ' + line.strip() + ';\n')
				line_num = line_num + 1
			mif_file.write('END;\n')
			dump_file.close()
			mif_file.close()

			if((filename != 'input') and (filename != 'output')):
				subprocess.call(['rm', dump_dir+filename], shell=False)

		elif(filename == 'output'):
			dump_file = open(dump_dir+filename, 'r')
			mif_file_lower = open(dump_dir+filename+'_lower.mif', 'w')
			mif_file_upper = open(dump_dir+filename+'_upper.mif', 'w')
			mif_file = open(dump_dir+filename+'.mif', 'w')
			
			depth = 0
			for line in dump_file:
				depth = depth + 1
			width = int(len(line.strip()))
			dump_file.close()

			mif_file_lower.write('DEPTH = ' + str(depth) + ';\n')
			mif_file_lower.write('WIDTH = ' + str(width*2) + ';\n')
			mif_file_lower.write('ADDRESS_RADIX = DEC;\n')
			mif_file_lower.write('DATA_RADIX = HEX;\n')
			mif_file_lower.write('CONTENT\n')
			mif_file_lower.write('BEGIN\n')
			mif_file_upper.write('DEPTH = ' + str(depth) + ';\n')
			mif_file_upper.write('WIDTH = ' + str(width*2) + ';\n')
			mif_file_upper.write('ADDRESS_RADIX = DEC;\n')
			mif_file_upper.write('DATA_RADIX = HEX;\n')
			mif_file_upper.write('CONTENT\n')
			mif_file_upper.write('BEGIN\n')

			mif_file.write('DEPTH = ' + str(depth) + ';\n')
			mif_file.write('WIDTH = ' + str(width*4) + ';\n')
			mif_file.write('ADDRESS_RADIX = DEC;\n')
			mif_file.write('DATA_RADIX = HEX;\n')
			mif_file.write('CONTENT\n')
			mif_file.write('BEGIN\n')
			
			line_num = 0
			dump_file = open(dump_dir+filename, 'r')
			for line in dump_file:
				line_str = line.strip()
				mif_file_lower.write(str(line_num) + ': ' + line_str[int(width/2): width] + ';\n')
				mif_file_upper.write(str(line_num) + ': ' + line_str[0: int(width/2)] + ';\n')
				mif_file.write(str(line_num) + ': ' + line_str + ';\n')
				line_num = line_num + 1
			mif_file_lower.write('END;\n')
			mif_file_upper.write('END;\n')
			mif_file.write('END;\n')
			dump_file.close()
			mif_file_lower.close()
			mif_file_upper.close()
			mif_file.close()

		elif(filename.find('mrf') != -1):
			dump_file = open(dump_dir+filename, 'r')
			mif_files = []
			for i in range(num_dsps):
				mif_files.append(open(dump_dir+filename+'_'+str(i)+'.mif', 'w'))
			
			depth = 0
			for line in dump_file:
				depth = depth + 1
			width = len(line.strip())
			dump_file.close()

			for i in range(num_dsps):
				mif_files[i].write('DEPTH = ' + str(depth) + ';\n')
				mif_files[i].write('WIDTH = ' + str(int(width/4)) + ';\n')
				mif_files[i].write('ADDRESS_RADIX = DEC;\n')
				mif_files[i].write('DATA_RADIX = BIN;\n')
				mif_files[i].write('CONTENT\n')
				mif_files[i].write('BEGIN\n')
			
			line_num = 0
			dump_file = open(dump_dir+filename, 'r')
			flag_first = 1
			for line in dump_file:
				line_str = line.strip()
				line_size = len(line_str)
				line_stepsize = int(len(line_str)/num_dsps)
				for i in range(num_dsps):
					mif_files[i].write(str(line_num) + ': ' + line_str[(line_stepsize*i) : (line_stepsize*(i+1))] + ';\n')
				line_num = line_num + 1
				flag_first = 0

			for i in range(num_dsps):
				mif_files[i].write('END;\n')
				mif_files[i].close()
			dump_file.close()
			
			if((filename != 'input') and (filename != 'output')):
				subprocess.call(['rm', dump_dir+filename], shell=False)

def numericalSort(value):
	numbers = re.compile(r'(\d+)')
	parts = numbers.split(value)
	parts[1::2] = map(int, parts[1::2])
	return parts

def RoundUp(x):
	return ((x + 7) & (-8))

def generate_header_file(filename):
	depth = -1
	width = -1
	radix = ""
	inst_depth = -1
	inst_width = -1
	inst_radix = ""
	mif_path= './pac_dump/'
	in_ = open(mif_path+'mvu-mrf0.mif','r') 
	for line in in_:
		if (depth != -1) and (width != -1):
			break
		mtx = re.match('DEPTH = (\d+);', line)
		if mtx:
			depth = int(mtx.groups()[0])
			continue
		mtx = re.match('WIDTH = (\d+);', line)
		if mtx:
			width = int(mtx.groups()[0]);
			continue

	in_ = open(mif_path+'top_sched.mif','r') 
	for line in in_:
		if (inst_depth != -1) and (inst_width != -1):
			break
		mtx = re.match('DEPTH = (\d+);', line)
		if mtx:
			inst_depth = int(mtx.groups()[0])
			continue
		mtx = re.match('WIDTH = (\d+);', line)
		if mtx:
			inst_width = int(mtx.groups()[0]);
			continue

	dre_src = '([0-9]+):\s+((0|1){' + str(width) + '})'
	dre = re.compile(dre_src)

	dre_src_inst = '([0-9]+):\s+((0|1){' + str(inst_width) + '})'
	dre_inst = re.compile(dre_src_inst)

	dre_input = re.compile(r"\L$")
	total_mrf = 0

	header_file = open(mif_path + filename + '.h', 'w')
	variables_string = ''

	#Files are sorted; careful while changing if-else order
	for file in sorted(os.listdir(mif_path),key=numericalSort):
		try:
			if file.startswith("input"):		
				data = []
				tmp_vec = []
				i=0
				header_file.write('char input_vectors[] = \n')
				with open(mif_path+'/'+file) as f:
					for line in f:
						line = line[:-2]
						data.append(line)
					for d in data:
						bytes = []
						rev_d = d[::-1]
						if(len(rev_d)%8 != 0):
							padded_zeros = RoundUp(len(rev_d))-len(rev_d)
							tmp_str = "0" * padded_zeros 
							rev_d = rev_d + tmp_str
						
						for i in range(0,len(rev_d),2):
							curr_byte = rev_d[i:i+2]
							rev_byte  = curr_byte[::-1]
						bytes.append(int(rev_byte,16))

						out = '"'
						for b in bytes:
							if(b<16):
								out = out + '\\x0' + format(b, 'x')
							else:
								out = out + '\\x' + format(b, 'x')
						for i in range(len(bytes),64):
							out = out + '\\x00'

						out = out + '"'
						header_file.write(out + "\n")
				header_file.write(';' + "\n")
				variables_string = variables_string + 'uint32_t num_in = '+ str(len(data))+   ";\n"
				header_file.write('char mrf_vector[] = \n')
				
			elif(file.startswith("mvu-mrf")):
				data = []
				with open(mif_path+'/'+file) as f:
					total_mrf = total_mrf + 1
					for line in f:
						mtx = re.match(dre, line)
						if mtx:
							data.append(mtx.groups()[1])
					for d in data:
						bytes = []
						rev_d = d[::-1]
						for i in range(0,width,8):
							curr_byte = rev_d[i:i+8]
							rev_byte  = curr_byte[::-1]
						bytes.append(int(rev_byte,2))

						out = '"'
						for b in bytes:
							if(b<16):
								out = out + '\\x0' + format(b, 'x')
							else:
								out = out + '\\x' + format(b, 'x')
						for i in range(len(bytes),64):
							out = out + '\\x00'

						out = out + '"'
						header_file.write(out + "\n")

			elif file.startswith("output"):		
				data = []
				tmp_vec = []
				i=0
				header_file.write(';' + "\n")
				variables_string = variables_string + 'uint32_t num_mrf = '+ str(total_mrf)+  ";\n"
				variables_string = variables_string + 'uint32_t words_per_mrf = '+ str(depth) + ";\n"
				header_file.write('char output_vectors [] = \n')
				with open(mif_path+'/'+file) as f:
					for line in f:
						line = line[:-2]
						data.append(line)
					for d in data:
						bytes = []
						rev_d = d[::-1]
						if(len(rev_d)%8 != 0):
							padded_zeros = RoundUp(len(rev_d))-len(rev_d)
							tmp_str = "0" * padded_zeros 
							rev_d = rev_d + tmp_str
						
						for i in range(0,len(rev_d),2):
							curr_byte = rev_d[i:i+2]
							rev_byte  = curr_byte[::-1]
						bytes.append(int(rev_byte,16))

						out = '"'
						for b in bytes:
							if(b<16):
								out = out + '\\x0' + format(b, 'x')
							else:
								out = out + '\\x' + format(b, 'x')
						for i in range(len(bytes),64):
							out = out + '\\x00'

						out = out + '"\n'
						header_file.write(out)
			elif file.startswith("top"):
				header_file.write(';' + "\n")
				variables_string = variables_string + 'uint32_t num_out = '+ str(len(data))+   ";\n"
				variables_string = variables_string + 'uint32_t num_inst = '+ str(inst_depth) + ";\n"
				header_file.write('char instructions[] = \n')
				data = []
				with open(mif_path+'/'+file) as f:
					for line in f:
						mtx = re.match(dre_inst, line)
						if mtx:
							data.append(mtx.groups()[1])
					for d in data:
						bytes = []
						rev_d = d[::-1]
						for i in range(0,inst_width,8):
							curr_byte = rev_d[i:i+8]
							rev_byte  = curr_byte[::-1]
						bytes.append(int(rev_byte,2))
				   	
						out = '"'
						for b in bytes:
							if(b<16):
								out = out + '\\x0' + format(b, 'x')
							else:
								out = out + '\\x' + format(b, 'x')
						for i in range(len(bytes),64):
							out = out + '\\x00'

						out = out + '"'
						header_file.write(out + "\n")
				header_file.write(';' + "\n")

		except Exception as e:
			raise e
			print('No files found here!')

	variables_string = variables_string + 'uint32_t total_mem_buff_alloc_on_fpga = 11;\n'
	variables_string = variables_string + 'uint32_t pc_start = 0;\n'
	header_file.write(variables_string)
	header_file.close()

 
def initialize_npu(argv):
	# default compiler parameters
	name = 'test'
	num_tiles = 7
	num_dpes = 40
	num_lanes = 40
	vrf_depth = 512
	mrf_depth = 1024
	verbose = 0
	pac_gen = 0
	rtl_simulation = 0
	perf_simulation = 0
	mif_gen = 0
	pcie_gen = 0
	program_loops = 1
	freq = 300

	# Capture parameters from command line
	if('-n' in sys.argv):
		if(sys.argv.index('-n') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -n argument!" + bcolors.RESET)
			sys.exit(1)
		name = sys.argv[sys.argv.index('-n') + 1]
		if(len(name) > 50):
			print(bcolors.FAIL + "\nName too long!" + bcolors.RESET)
			sys.exit(1)
		if(name[0] == '-'):
			print(bcolors.FAIL + "\nInvalid -n argument!" + bcolors.RESET)
			sys.exit(1)	
	
	if('-t' in sys.argv):
		if(sys.argv.index('-t') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -t argument!" + bcolors.RESET)
			sys.exit(1)
		try:
			num_tiles = int(sys.argv[sys.argv.index('-t') + 1])
		except ValueError:
			print(bcolors.FAIL + "\nInvalid -t argument!" + bcolors.RESET)
			sys.exit(1)

	if('-d' in sys.argv):
		if(sys.argv.index('-d') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -d argument!" + bcolors.RESET)
			sys.exit(1)
		try:
			num_dpes = int(sys.argv[sys.argv.index('-d') + 1])
		except ValueError:
			print(bcolors.FAIL + "\nInvalid -d argument!" + bcolors.RESET)
			sys.exit(1)

	if('-l' in sys.argv):
		if(sys.argv.index('-l') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -l argument!" + bcolors.RESET)
			sys.exit(1)
		try:
			num_lanes = int(sys.argv[sys.argv.index('-l') + 1])
		except ValueError:
			print(bcolors.FAIL + "\nInvalid -l argument!" + bcolors.RESET)
			sys.exit(1)

	if('-vd' in sys.argv):
		if(sys.argv.index('-vd') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -vd argument!" + bcolors.RESET)
			sys.exit(1)
		try:
			vrf_depth = int(sys.argv[sys.argv.index('-vd') + 1])
		except ValueError:
			print(bcolors.FAIL + "\nInvalid -vd argument!" + bcolors.RESET)
			sys.exit(1)

	if('-md' in sys.argv):
		if(sys.argv.index('-md') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -md argument!" + bcolors.RESET)
			sys.exit(1)
		try:
			mrf_depth = int(sys.argv[sys.argv.index('-md') + 1])
		except ValueError:
			print(bcolors.FAIL + "\nInvalid -md argument!" + bcolors.RESET)
			sys.exit(1)

	if('-loop' in sys.argv):
		if(sys.argv.index('-loop') + 1 >= len(sys.argv)):
			print(bcolors.FAIL + "\nInvalid -loop argument!" + bcolors.RESET)
			sys.exit(1)
		try:
			program_loops = int(sys.argv[sys.argv.index('-loop') + 1])
		except ValueError:
			print(bcolors.FAIL + "\nInvalid -loop argument!" + bcolors.RESET)
			sys.exit(1)

	# Checks on input parameters
	mult_limit = 11200
	word_count_limit = 290304
	num_tiles_limit = 21
	num_dpes_limit = 120
	num_lanes_limit = 120

	if(num_tiles * num_dpes * num_lanes > mult_limit):
		print(bcolors.FAIL + "\nInvalid Input: Product of number of tiles, DPEs, and lanes must be less than or equal to "+str(mult_limit)+" to fit on the Stratix 10 NX device" + bcolors.RESET)
		sys.exit(1)
	if(num_lanes % 10 != 0):
		print(bcolors.FAIL + "\nInvalid Input: Number of lanes must be a multiple of 10" + bcolors.RESET)
		sys.exit(1)
	if(num_dpes % num_lanes != 0):
		print(bcolors.FAIL + "\nInvalid Input: Number of DPEs must be a multiple of the number of tiles" + bcolors.RESET)
		sys.exit(1)
	if((num_tiles <= 0) or (num_lanes <= 0) or (num_dpes <= 0) or (vrf_depth <= 0) or (mrf_depth <= 0)):
		print(bcolors.FAIL + "\nInvalid Input: All architecture parameters (Tiles, DPEs, Lanes, VRF depth, MRF depth) must have positive non-zero values" + bcolors.RESET)
		sys.exit(1)
	if((mrf_depth*num_tiles*num_dpes + vrf_depth*num_tiles) > word_count_limit):
		print(bcolors.FAIL + "\nInvalid Input: Total number of memory words in all MRFs and VRFs must be less than or equal to "+str(word_count_limit)+" to fit on the Stratix 10 NX device" + bcolors.RESET)
		sys.exit(1)
	if(num_tiles > num_tiles_limit):
		print(bcolors.FAIL + "\nInvalid Input: Number of tiles must be less than " + str(num_tiles_limit) + bcolors.RESET)
		sys.exit(1)
	if(num_dpes > num_dpes_limit):
		print(bcolors.FAIL + "\nInvalid Input: Number of DPEs must be less than " + str(num_dpes_limit) + bcolors.RESET)
		sys.exit(1)
	if(num_lanes > num_lanes_limit):
		print(bcolors.FAIL + "\nInvalid Input: Number of lanes must be less than " + str(num_lanes_limit) + bcolors.RESET)
		sys.exit(1)

	if((num_tiles != 7) or (num_dpes != 40) or (num_lanes != 40) or (vrf_depth != 512) or (mrf_depth != 1024)):
		print("\nWarning: This set of architecture parameters (tiles="+str(num_tiles)+", DPEs="+str(num_dpes)+", lanes="+str(num_lanes)+ \
			", VRF depth="+str(vrf_depth)+", MRF depth="+str(mrf_depth)+") was not extensively tested. Use at your own risk!")
		print("Default parameters from the FPT'20 paper is (tiles=7, DPEs=40, lanes=40, VRF depth=512, MRF depth=1024)")


	if('-v' in sys.argv):
		verbose = 1

	if('-pac' in sys.argv):
		pac_gen = 1

	if('-rtlsim' in sys.argv):
		mif_gen = 1
		rtl_simulation = 1

	if('-perfsim' in sys.argv):
		perf_simulation = 1

	if('-mif' in sys.argv):
		mif_gen = 1

	if('-pcie' in sys.argv):
		pcie_gen = 1

	if('-freq' in sys.argv):
		try:
			freq = int(sys.argv[sys.argv.index('-freq') + 1])
		except ValueError:
			print("Invalid -freq argument!")
			sys.exit(1)

	if(freq <= 0):
		print(bcolors.FAIL + "\nSpecified frequency must be a positive integer" + bcolors.RESET)
		sys.exit(1)


	# Assign program name as well as verbose and RTL simulation options
	checkpoint_name = name + '_' + str(num_tiles) + '_' + str(num_dpes) + '_' + str(num_lanes)

	# Define architecture parameters
	arch_params = {
		'tiles' : num_tiles,
		'dpes'  : num_dpes,
		'lanes' : num_lanes,
		'vrf_depth' : vrf_depth, 
		'mrf_depth' : mrf_depth, 
		'max_tag'	: 512
	}

	# Define compiler options
	flow_opts = {
		'checkpoint_name' : checkpoint_name,
		'pac'  				    : pac_gen,
		'rtl_sim' 			  : rtl_simulation,
		'perf_sim' 			  : perf_simulation, 
		'verbose' 			  : verbose,
		'mif_gen'			    : mif_gen,
		'freq'				    : freq,
		'pcie_gen'			  : pcie_gen,
		'program_loops'   : program_loops
	}

	return npu(arch_params, flow_opts)
