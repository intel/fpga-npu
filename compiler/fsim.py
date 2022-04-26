import numpy as np
import re
import sys
import warnings
import math

if not sys.warnoptions:
    warnings.simplefilter("ignore")

in_d_type  = np.int8
acc_d_type = np.int32

### Activation functions 
def mySigmoid(x):
    # output = 1/(1+np.exp(-x))
    # for debugging bypass Sigmoid
    # return output *
    return x

def myReLU(x):
    # return x * (x > 0)
    # for debugging bypass ReLU
    return x 

def myTanh(x):
    # output = np.tanh(x)
    # for debugging bypass myTanh
    # return output *
    return x 

### Class to represent the input chains
class chain (object):
   def __init__(self, batch=3, mvu_mrf_rd_base=0, mvu_mrf_rd_sz=0, mvu_vrf_rd_base=0, mvu_vrf_rd_sz=0, mvu_words_per_row=0, mvu_op_type='nop', mvu_tag=0, 
   	           extvrf_rd_base=0, extvrf_rd_sz=0, extvrf_op_type='nop', extvrf_tag=0,
   	           mfu0_vrf0_rd_base=0, mfu0_vrf1_rd_base=0, mfu0_vrf_rd_size=0, mfu0_act_op_type='nop', mfu0_add_op_type='nop', mfu0_mul_op_type='nop', mfu0_tag=0,
   	           mfu1_vrf0_rd_base=0, mfu1_vrf1_rd_base=0, mfu1_vrf_rd_size=0, mfu1_act_op_type='nop', mfu1_add_op_type='nop', mfu1_mul_op_type='nop', mfu1_tag=0,
   	           vrf_id0_op='--', vrf_id0_wr_base=0, vrf_id0_wr_size=0, vrf_id1_op='--', vrf_id1_wr_base=0, vrf_id1_wr_size=0, loader_src='nop',
               last_flag=0, write_to_obuf=1):

      self.batch             = batch

      self.mvu_mrf_rd_base   = mvu_mrf_rd_base		#integer
      self.mvu_mrf_rd_sz     = mvu_mrf_rd_sz		#integer
      self.mvu_vrf_rd_base   = [mvu_vrf_rd_base] * batch		#integer
      self.mvu_vrf_rd_sz     = mvu_vrf_rd_sz		#integer
      self.mvu_words_per_row = mvu_words_per_row
      self.mvu_op_type       = mvu_op_type			#string {matvec, nop}
      self.mvu_tag           = mvu_tag				#integer

      self.extvrf_rd_base    = [extvrf_rd_base] * batch		#integer
      self.extvrf_rd_sz      = extvrf_rd_sz			#integer
      self.extvrf_op_type    = extvrf_op_type		#string {move, extvrf, nop}
      self.extvrf_tag        = extvrf_tag			#integer

      self.mfu0_vrf0_rd_base = [mfu0_vrf0_rd_base] * batch	#integer
      self.mfu0_vrf1_rd_base = [mfu0_vrf1_rd_base] * batch	#integer
      self.mfu0_vrf_rd_size  = mfu0_vrf_rd_size		#integer
      self.mfu0_act_op_type  = mfu0_act_op_type		#string {nop, relu, sig, tanh}
      self.mfu0_add_op_type  = mfu0_add_op_type		#string {nop, add, sub_a_b, sub_b_a, max}
      self.mfu0_mul_op_type  = mfu0_mul_op_type		#string {nop, mul}
      self.mfu0_tag          = mfu0_tag				#integer

      self.mfu1_vrf0_rd_base = [mfu1_vrf0_rd_base] * batch	#integer
      self.mfu1_vrf1_rd_base = [mfu1_vrf1_rd_base] * batch	#integer
      self.mfu1_vrf_rd_size  = mfu1_vrf_rd_size		#integer
      self.mfu1_act_op_type  = mfu1_act_op_type		#string {nop, relu, sig, tanh}
      self.mfu1_add_op_type  = mfu1_add_op_type		#string {nop, add, sub_a_b, sub_b_a, max}
      self.mfu1_mul_op_type  = mfu1_mul_op_type		#string {nop, mul}
      self.mfu1_tag          = mfu1_tag				#integer

      self.vrf_id0_op        = vrf_id0_op			#string {mvu#.vrf, mfu0.vrf0, mfu0.vrf1, mfu1.vrf0, mfu1.vrf1, extvrf}
      self.vrf_id0_wr_base   = [vrf_id0_wr_base] * batch		#integer
      self.vrf_id0_wr_size   = vrf_id0_wr_size		#integer
      self.vrf_id1_op        = vrf_id1_op			#string {mvu#.vrf, mfu0.vrf0, mfu0.vrf1, mfu1.vrf0, mfu1.vrf1, extvrf}
      self.vrf_id1_wr_base   = [vrf_id1_wr_base] * batch		#integer
      self.vrf_id1_wr_size   = vrf_id1_wr_size		#integer
      self.loader_src        = loader_src			#string {wb, in, flush, nop}

      self.last_flag         = last_flag          	#boolean {0,1}
      self.write_to_obuf     = write_to_obuf      	#boolean {0,1}

      self.results = ['', '', '', '', '', '', '', '']
      self.wb_so_far = 0
      self.flags = [False, False, False, False, False, False, False, False]

   def print_chain(self):
      print('MVU mOP {mrf_base:' + str(self.mvu_mrf_rd_base) + ', mrf_sz:' + str(self.mvu_mrf_rd_sz) + ', vrf_base:' + str(self.mvu_vrf_rd_base) + ', vrf_sz:' + str(self.mvu_vrf_rd_sz) + ', op:' + self.mvu_op_type + ', tag:' + str(self.mvu_tag))
      print('eVRF mOP {evrf_base:' + str(self.extvrf_rd_base) + ', evrf_sz:' + str(self.extvrf_rd_sz) + ', op:' + self.extvrf_op_type + ', tag:' + str(self.extvrf_tag))
      print('MFU0 mOP {vrf0_base:' + str(self.mfu0_vrf0_rd_base) + ', vrf1_base:' + str(self.mfu0_vrf1_rd_base) + ', vrf_sz:' + str(self.mfu0_vrf_rd_size) + ', op:' + self.mfu0_act_op_type + ',' + self.mfu0_add_op_type + ',' + self.mfu0_mul_op_type + ', tag:' + str(self.mfu0_tag))
      print('MFU1 mOP {vrf0_base:' + str(self.mfu1_vrf0_rd_base) + ', vrf1_base:' + str(self.mfu1_vrf1_rd_base) + ', vrf_sz:' + str(self.mfu1_vrf_rd_size) + ', op:' + self.mfu1_act_op_type + ',' + self.mfu1_add_op_type + ',' + self.mfu1_mul_op_type + ', tag:' + str(self.mfu1_tag))
      print('LD mOP {vrf_id0:' + self.vrf_id0_op + ', vrf_id0_base:' + str(self.vrf_id0_wr_base) + ', vrf_id0_sz:' + str(self.vrf_id0_wr_size) + ', vrf_id1:' + self.vrf_id1_op + ', vrf_id1_base:' + str(self.vrf_id1_wr_base) + ', vrf_id1_sz:' + str(self.vrf_id1_wr_size) + ', src:' + self.loader_src)
      print('-----------------------------------------')

   def adjust_bypassed(self):
      if(self.mfu0_act_op_type == 'nop'):
        self.mfu0_act_op_type = 'move'
      if(self.mfu0_add_op_type == 'nop'):
        self.mfu0_add_op_type = 'move'
      if(self.mfu0_mul_op_type == 'nop'):
        self.mfu0_mul_op_type = 'move'

      if(self.mfu0_act_op_type == 'move' and self.mfu0_add_op_type == 'move' and self.mfu0_mul_op_type == 'move'):    	
        self.mfu0_vrf_rd_size = self.extvrf_rd_sz
        self.mfu0_vrf0_rd_base = [0] * self.batch
        self.mfu0_vrf1_rd_base = [0] * self.batch
        self.mfu0_tag = self.extvrf_tag
      
      if(self.mfu1_act_op_type == 'nop'):
        self.mfu1_act_op_type = 'move'
      if(self.mfu1_add_op_type == 'nop'):
        self.mfu1_add_op_type = 'move'
      if(self.mfu1_mul_op_type == 'nop'):
        self.mfu1_mul_op_type = 'move'

      if(self.mfu1_act_op_type == 'move' and self.mfu1_add_op_type == 'move' and self.mfu1_mul_op_type == 'move'):
        self.mfu1_vrf_rd_size = self.mfu0_vrf_rd_size
        self.mfu1_vrf0_rd_base = [0] * self.batch
        self.mfu1_vrf1_rd_base = [0] * self.batch
        self.mfu1_tag = self.mfu0_tag

### Class for ISA simulator
class npu_isa_sim (object):
  def __init__(self,inst_q, ibuf_q, mvu_vrfs, ext_vrf, mfu0_vrf0, mfu0_vrf1, mfu1_vrf0, mfu1_vrf1, ntile, ndpe, nlane, vrf_init_sz):
    self.inst_q = inst_q
    self.ibuf_q = ibuf_q
    self.obuf_q = []

    # HW 
    self.ndpe   = ndpe
    self.nlane  = nlane
    self.ntile  = ntile
    self.vrf_init_sz = vrf_init_sz

    # MVU states
    self.mvu_ofifo = []
    self.mvu_mrfs  = []   
    self.mvu_accs  = [0] * self.ndpe

    # Read the input fifo data and put in the vrf
    self.mvu_vrfs   = mvu_vrfs
    self.mvu_all    = [0]*self.ntile

    # extvrf states
    self.ext_vrf = ext_vrf
    self.ext_vrf_ififo = []
    self.ext_vrf_ofifo = []

    # MFU0 states
    self.mfu0_vrf0  = mfu0_vrf0
    self.mfu0_vrf1  = mfu0_vrf1
    self.mfu0_ififo = []
    self.mfu0_ofifo = []

    # MFU1 states
    self.mfu1_vrf0  = mfu1_vrf0
    self.mfu1_vrf1  = mfu1_vrf1
    self.mfu1_ofifo = []
    self.mfu1_ififo = []
   
  #### MVU macro functionality ####
  # MVU matvec
  def exe_mvu_m_inst_matvec(self, cur_chain, verbose):
    num_steps = int(math.ceil(cur_chain.mvu_mrf_rd_sz / cur_chain.mvu_vrf_rd_sz))
    batch = cur_chain.batch

    mvu_result = [[([0] * batch) for d in range(self.ndpe)] for t in range(num_steps)]
    mrf_addr = cur_chain.mvu_mrf_rd_base
    for t in range(num_steps):
      vrf_addr = cur_chain.mvu_vrf_rd_base[:]
      while(vrf_addr[0] < cur_chain.mvu_vrf_rd_base[0] + cur_chain.mvu_vrf_rd_sz):
        for tile in range(self.ntile):
          for dpe in range(self.ndpe):
            mrf_data = self.mvu_mrfs[tile][dpe][mrf_addr]
            for b in range(batch):
              vrf_data = self.mvu_vrfs[tile][vrf_addr[b]]
              mvu_result[t][dpe][b] += np.dot(mrf_data.astype(acc_d_type), vrf_data.astype(acc_d_type))
        mrf_addr += 1
        for b in range(batch):
          vrf_addr[b] += 1

    for t in range(num_steps):
      for chunk in range(int(self.ndpe/self.nlane)):
        for b in range(batch):
          for lane in range(self.nlane):
            self.mvu_ofifo.append(mvu_result[t][(chunk*self.nlane)+lane][b])

    if(verbose):
      print("MVU Output FIFO: ", self.mvu_ofifo)
  
  # Complete MVU
  def exe_mvu_m_inst (self, cur_chain, verbose):
    if cur_chain.mvu_op_type=='matvec':
      if(verbose):
        print('MVU performing matvec')    	
      self.exe_mvu_m_inst_matvec(cur_chain, verbose)
    elif cur_chain.mvu_op_type=='nop':
      if(verbose):	
        print('MVU performing nop')
    else:
      raise AssertionError()

  #### Extvrf macro functionality ####
  # Extvrf move 
  def exe_extvrf_inst_move(self, cur_chain, verbose):
    batch = cur_chain.batch
    for i in range(cur_chain.extvrf_rd_sz):
      for b in range(batch):
        for j in range(self.nlane):
          self.mfu0_ififo.append((self.mvu_ofifo.pop(0)).astype(acc_d_type))

    if(verbose):
      print("eVRF Output FIFO: ", self.mfu0_ififo)

  # Extvrf active: reading from external vrf 
  def exe_extvrf_inst_extvrf(self, cur_chain, verbose):
    batch = cur_chain.batch
    extvrf_rd_addr_tmp = cur_chain.extvrf_rd_base[:]
    for i in range(cur_chain.extvrf_rd_sz):
      for b in range(batch):
        for j in range(self.nlane):
          self.mfu0_ififo.append(self.ext_vrf[extvrf_rd_addr_tmp[b]][j])
        extvrf_rd_addr_tmp[b] += 1  

    if(verbose):
      print("eVRF Output FIFO: ", self.mfu0_ififo)
  
  # Complete Extvrf  
  def exe_extverf_m_inst (self, cur_chain, verbose):
    if cur_chain.extvrf_op_type == 'move':
      if(verbose):
        print('eVRF performing move')
      self.exe_extvrf_inst_move(cur_chain, verbose)
    elif cur_chain.extvrf_op_type == 'extvrf':
      if(verbose):
        print('eVRF performing read')
      self.exe_extvrf_inst_extvrf(cur_chain, verbose)
    elif cur_chain.extvrf_op_type == 'nop':
      if(verbose):
        print('eVRF performing nop')
    else:
      raise AssertionError()

  #### MFU0 macro functionality ####
  def exe_mfu0_m_inst(self, cur_chain, verbose): 
    batch = cur_chain.batch
    mfu0_vrf0_idx = cur_chain.mfu0_vrf0_rd_base[:]
    mfu0_vrf1_idx = cur_chain.mfu0_vrf1_rd_base[:]

    if(cur_chain.mfu0_act_op_type=='nop' and cur_chain.mfu0_add_op_type=='nop' and cur_chain.mfu0_mul_op_type=='nop'):
      if(verbose):
        print('MFU0 performing nop')
    else:
      if(verbose):
        print('MFU0 performing ' + cur_chain.mfu0_act_op_type + ', ' + cur_chain.mfu0_add_op_type + ', ' + cur_chain.mfu0_mul_op_type)
      for i in range (cur_chain.mfu0_vrf_rd_size):
        for b in range(batch):
          for j in range (self.nlane):
            if(cur_chain.mfu0_act_op_type=='nop' or cur_chain.mfu0_act_op_type=='move'):
              temp = (self.mfu0_ififo.pop(0)).astype(acc_d_type)
            elif(cur_chain.mfu0_act_op_type=='relu'):
              temp = myReLU((self.mfu0_ififo.pop(0)).astype(acc_d_type))
            elif(cur_chain.mfu0_act_op_type=='tanh'):
              temp = myTanh((self.mfu0_ififo.pop(0)).astype(acc_d_type))
            elif(cur_chain.mfu0_act_op_type=='sig'):
              temp = mySigmoid((self.mfu0_ififo.pop(0)).astype(acc_d_type))
            else:
              raise AssertionError()

            if(cur_chain.mfu0_add_op_type=='nop' or cur_chain.mfu0_add_op_type=='move'):
              temp = temp
            elif(cur_chain.mfu0_add_op_type=='add'):
              temp = (self.mfu0_vrf0[mfu0_vrf0_idx[b]][j] + temp).astype(acc_d_type)
            elif(cur_chain.mfu0_add_op_type=='sub_a_b'):
              temp = (temp - self.mfu0_vrf0[mfu0_vrf0_idx[b]][j]).astype(acc_d_type)
            elif(cur_chain.mfu0_add_op_type=='sub_b_a'):
              temp = (self.mfu0_vrf0[mfu0_vrf0_idx[b]][j] - temp).astype(acc_d_type)
            elif(cur_chain.mfu0_add_op_type=='max'):
              temp = max(self.mfu0_vrf0[mfu0_vrf0_idx[b]][j],temp).astype(acc_d_type)
            else:
              raise AssertionError()

            if(cur_chain.mfu0_mul_op_type=='nop' or cur_chain.mfu0_mul_op_type=='move'):
              temp = temp
            elif(cur_chain.mfu0_mul_op_type=='mul'):
              temp = (self.mfu0_vrf1[mfu0_vrf1_idx[b]][j] * temp).astype(acc_d_type)
              
            else:
              raise AssertionError()

            self.mfu1_ififo.append(temp)

          mfu0_vrf0_idx[b] = mfu0_vrf0_idx[b] + 1
          mfu0_vrf1_idx[b] = mfu0_vrf1_idx[b] + 1

      if(verbose):
        print("MFU0 Output FIFO: ", self.mfu1_ififo)


  #### MFU1 macro functionality ####
  def exe_mfu1_m_inst(self, cur_chain, verbose): 
    batch = cur_chain.batch
    mfu1_vrf0_idx = cur_chain.mfu1_vrf0_rd_base[:]
    mfu1_vrf1_idx = cur_chain.mfu1_vrf1_rd_base[:]

    if(cur_chain.mfu1_act_op_type=='nop' and cur_chain.mfu1_add_op_type=='nop' and cur_chain.mfu1_mul_op_type=='nop'):
      if(verbose):
        print('MFU1 performing nop')
    else:
      if(verbose):
        print('MFU1 performing ' + cur_chain.mfu1_act_op_type + ', ' + cur_chain.mfu1_add_op_type + ', ' + cur_chain.mfu1_mul_op_type)
      for i in range (cur_chain.mfu1_vrf_rd_size):
        for b in range(batch):
          for j in range (self.nlane):
            if(cur_chain.mfu1_act_op_type=='nop' or cur_chain.mfu1_act_op_type=='move'):
              temp = (self.mfu1_ififo.pop(0)).astype(acc_d_type)
            elif(cur_chain.mfu1_act_op_type=='relu'):
              temp = myReLU((self.mfu1_ififo.pop(0)).astype(acc_d_type))
            elif(cur_chain.mfu1_act_op_type=='tanh'):
              temp = myTanh((self.mfu1_ififo.pop(0)).astype(acc_d_type))
            elif(cur_chain.mfu1_act_op_type=='sig'):
              temp = mySigmoid((self.mfu1_ififo.pop(0)).astype(acc_d_type))
            else:
              raise AssertionError()

            if(cur_chain.mfu1_add_op_type=='nop' or cur_chain.mfu1_add_op_type=='move'):
              temp = temp
            elif(cur_chain.mfu1_add_op_type=='add'):
              temp = (self.mfu1_vrf0[mfu1_vrf0_idx[b]][j] + temp).astype(acc_d_type)
            elif(cur_chain.mfu1_add_op_type=='sub_a_b'):
              temp = (temp - self.mfu1_vrf0[mfu1_vrf0_idx[b]][j]).astype(acc_d_type)
            elif(cur_chain.mfu1_add_op_type=='sub_b_a'):
              temp = (self.mfu1_vrf0[mfu1_vrf0_idx[b]][j] - temp).astype(acc_d_type)
            elif(cur_chain.mfu1_add_op_type=='max'):
              temp = max(self.mfu1_vrf0[mfu1_vrf0_idx[b]][j],temp).astype(acc_d_type)
            else:
              raise AssertionError()

            if(cur_chain.mfu1_mul_op_type=='nop' or cur_chain.mfu1_mul_op_type=='move'):
              temp = temp
            elif(cur_chain.mfu1_mul_op_type=='mul'):
              temp = (self.mfu1_vrf1[mfu1_vrf1_idx[b]][j] * temp).astype(acc_d_type)
          
            else:
              raise AssertionError()

            self.mfu1_ofifo.append(temp)

          mfu1_vrf0_idx[b] = mfu1_vrf0_idx[b] + 1
          mfu1_vrf1_idx[b] = mfu1_vrf1_idx[b] + 1 

      if(verbose):
        print("MFU1 Output FIFO: ", self.mfu1_ififo) 

  #### Loader macro functionality ####
  # Loader for the input   
  def exe_ld_inst_in(self, cur_chain):
    curr_obuf_q = []
    for i in range (cur_chain.vrf_id0_wr_size):
      for b in range(cur_chain.batch):
        vrf_addr = cur_chain.vrf_id0_wr_base[b] + i
        wb_data = self.ibuf_q.pop(0)

        # Loading to MVU VRFs
        seprator = ''
        id_str_0 = cur_chain.vrf_id0_op
        src_0 = seprator.join(id_str_0[0:3])
        id_str_1 = cur_chain.vrf_id1_op
        src_1 = seprator.join(id_str_1[0:3])
        if(src_0 == 'mvu'):
          m = re.search('mvu(\d+)',id_str_0,re.IGNORECASE)
          vrf_id = int(m.group(1))
          self.mvu_vrfs[vrf_id][vrf_addr][:]= wb_data
        if(src_1 == 'mvu'):
          m = re.search('mvu(\d+)',id_str_0,re.IGNORECASE)
          vrf_id = int(m.group(1))
          self.mvu_vrfs[vrf_id][vrf_addr][:]= wb_data

        # Loading to eVRF
        if((cur_chain.vrf_id0_op=='extvrf') or (cur_chain.vrf_id1_op=='extvrf')):
          self.ext_vrf[vrf_addr][:]= wb_data
        # Loading to MFU0 VRF0
        elif((cur_chain.vrf_id0_op=='mfu0.vrf0') or (cur_chain.vrf_id1_op=='mfu0.vrf0')):
          self.mfu0_vrf0[vrf_addr][:]= wb_data
        # Loading to MFU0 VRF1
        elif((cur_chain.vrf_id0_op=='mfu0.vrf1') or (cur_chain.vrf_id1_op=='mfu0.vrf1')):
          self.mfu0_vrf1[vrf_addr][:]= wb_data
        # Loading to MFU1 VRF0
        elif((cur_chain.vrf_id0_op=='mfu1.vrf0') or (cur_chain.vrf_id1_op=='mfu1.vrf0')):
          self.mfu1_vrf0[vrf_addr][:]= wb_data
        # Loading to MFU1 VRF1
        elif((cur_chain.vrf_id0_op=='mfu1.vrf1') or (cur_chain.vrf_id1_op=='mfu1.vrf1')):
          self.mfu1_vrf1[vrf_addr][:]= wb_data

        if(cur_chain.write_to_obuf == 1):
          self.obuf_q.append(wb_data)

  # flush is used to make the fifo empty if loader wb instruction don't read all the data in fifo
  def exe_ld_inst_flush(self, cur_chain, verbose):
    for i in range(cur_chain.vrf_id0_wr_size):
      for b in range(cur_chain.batch):
        for j in range (self.nlane):
          temp_nul = self.mfu1_ofifo.pop(0)
    if(verbose):
      print("Loader Output FIFO: ", self.mfu1_ofifo)
     
  # Loader for write back 
  def exe_ld_inst_wb(self, cur_chain, verbose):
    if(verbose):
      print("Loader Output FIFO: ", self.mfu1_ofifo)
    seprator = ''
    id_str_0 = cur_chain.vrf_id0_op
    id_str_1 = cur_chain.vrf_id1_op
    curr_obuf_q = []
    for i in range(cur_chain.vrf_id0_wr_size):
      for b in range(cur_chain.batch):
        curr_obuf_val = []
        tmp_addr0 = cur_chain.vrf_id0_wr_base[b] + i
        tmp_addr1 = cur_chain.vrf_id1_wr_base[b] + i
        for j in range (self.nlane):
          wb_data = self.mfu1_ofifo.pop(0)
          curr_obuf_val.append(wb_data)
          # wb0:write back to the first destination
          if (seprator.join(id_str_0[0:3]) == 'mvu'):
            m = re.search('mvu(\d+)',id_str_0,re.IGNORECASE)
            id_int_0 = int(m.group(1))
            self.mvu_vrfs[id_int_0][tmp_addr0][j]= wb_data
            #if (self.mvu_vrfs[id_int_0][tmp_addr0][j] == -128):
            #  self.mvu_vrfs[id_int_0][tmp_addr0][j] = 0
          if(cur_chain.vrf_id0_op=='mfu0.vrf0'):
            self.mfu0_vrf0[tmp_addr0][j]= wb_data
          if(cur_chain.vrf_id0_op=='mfu0.vrf1'):
            self.mfu0_vrf1[tmp_addr0][j] = wb_data 
          if(cur_chain.vrf_id0_op=='mfu1.vrf0'):
            self.mfu1_vrf0[tmp_addr0][j] = wb_data
          if(cur_chain.vrf_id0_op=='mfu1.vrf1'):
            self.mfu1_vrf1[tmp_addr0][j] = wb_data 
          if(cur_chain.vrf_id0_op=='extvrf'):
            self.ext_vrf[tmp_addr0][j] = wb_data 
          # wb1:write back to the second destination 
          if (seprator.join(id_str_1[0:3]) == 'mvu'):
            m = re.search('mvu(\d+)',id_str_1,re.IGNORECASE)
            id_int_1 = int(m.group(1))
            self.mvu_vrfs[id_int_1][tmp_addr1][j]= wb_data
            #if (self.mvu_vrfs[id_int_1][tmp_addr1][j] == -128):
            #  self.mvu_vrfs[id_int_1][tmp_addr1][j] = 0
          if(cur_chain.vrf_id1_op=='mfu0.vrf0'):
            self.mfu0_vrf0[tmp_addr1][j] = wb_data
          if(cur_chain.vrf_id1_op=='mfu0.vrf1'):
            self.mfu0_vrf1[tmp_addr1][j] = wb_data 
          if(cur_chain.vrf_id1_op=='mfu1.vrf0'):
            self.mfu1_vrf0[tmp_addr1][j] = wb_data
          if(cur_chain.vrf_id1_op=='mfu1.vrf1'):
            self.mfu1_vrf1[tmp_addr1][j] = wb_data 
          if(cur_chain.vrf_id1_op=='extvrf'):
            self.ext_vrf[tmp_addr1][j] = wb_data 
        if(cur_chain.write_to_obuf == 1):
          self.obuf_q.append(curr_obuf_val)

  # Complete loader 
  def exe_ld_m_inst (self, cur_chain, verbose):
    if cur_chain.loader_src == 'in':
      if(verbose):
        print('Loader performing input load')
      self.exe_ld_inst_in(cur_chain)
    elif(cur_chain.loader_src =='wb'):
      if(verbose):
        print('Loader performing write back')
      self.exe_ld_inst_wb(cur_chain, verbose)
    elif(cur_chain.loader_src =='flush'):
      if(verbose):
        print('Loader performing flush')
      self.exe_ld_inst_flush(cur_chain, verbose)
    elif(cur_chain.loader_src =='nop'):
      if(verbose):
        print('Loader performing nop')
    else:
      raise AssertionError()
  
  # execute all macro insts in the chain
  def step(self, verbose=0):
    cur_chain = self.inst_q.pop(0)
    if(verbose):
      cur_chain.print_chain()
    self.exe_mvu_m_inst(cur_chain, verbose)
    self.exe_extverf_m_inst(cur_chain, verbose)
    self.exe_mfu0_m_inst(cur_chain, verbose)
    self.exe_mfu1_m_inst(cur_chain, verbose)  
    self.exe_ld_m_inst(cur_chain, verbose)
