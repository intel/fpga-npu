import math
import numpy as np
import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = "2"
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

from compiler import *

def npu_dense(npu, layer_name, layer_idx, num_inputs, time_steps, input_size, output_size, w_data, dest_memspace, inputs=None, activation=None, style='normal', last_layer=0):
    SIM_BATCH = 3
    BATCH = 6
    # Allocate weight matrix
    wdata = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
    W = npu.malloc(layer_name+'W', input_size, output_size, 'mvu_mrf', wdata)

    # Allocate output vectors
    h = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * time_steps
    for t in range(time_steps):
        for k in range(int(num_inputs / BATCH)):
            for i in range(SIM_BATCH):
                h[t][k][i] = npu.malloc(layer_name+'_h'+str(t)+'_'+str(k)+'_'+str(i), output_size, None, dest_memspace)

    # Allocate or retrieve input vectors
    x = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * time_steps
    if(layer_idx == 0):
        for t in range(time_steps):
            for k in range(int(num_inputs / BATCH)):
                for i in range(SIM_BATCH):
                    if(style == 'embedding'):
                        input_data = np.zeros(input_size)
                        input_data[int(inputs[(k * SIM_BATCH) + i][t])] = 1
                        x[t][k][i] = npu.malloc(layer_name, input_size, None, 'mvu_vrf', input_data)
                    else:
                        x[t][k][i] = npu.malloc(layer_name+'_x'+str(t)+'_'+str(k)+'_'+str(i), input_size, None, 'mvu_vrf', inputs[(k * SIM_BATCH) + i])
    else:
        x = npu.operands[layer_idx-1]            

    # NPU instructions
    for t in range(time_steps):
        for k in range(int(num_inputs / BATCH)):
            if(layer_idx == 0):
                npu.load(x[t][k], write_to_obuf=0, batch=SIM_BATCH)
            tmp1 = npu.matvec_mult(x[t][k], W, batch=SIM_BATCH)
            if(activation == 'relu'):
                tmp1 = npu.relu(tmp1, batch=SIM_BATCH)
            elif(activation == 'tanh'):
                tmp1 = npu.tanh(tmp1, batch=SIM_BATCH)
            elif(activation == 'sigmoid'):
                tmp1 = npu.sigmoid(tmp1, batch=SIM_BATCH)
            if(last_layer == 1):
                npu.produce_output(tmp1, h[t][k], batch=SIM_BATCH)
            else:
                npu.write_back(tmp1, h[t][k], write_to_obuf=0, batch=SIM_BATCH)
            for i in range(SIM_BATCH):
                h[t][k][i].space_name = dest_memspace

    npu.operands.append(h)

def npu_rnn(npu, layer_name, layer_idx, time_steps, num_inputs, input_size, units, output_size, wx_data, wh_data, dest_memspace, inputs=None, activation='tanh'):
    SIM_BATCH = 3
    BATCH = 6

    # Allocate Matrices
    Wx = npu.malloc(layer_name+'Wx', input_size, output_size, 'mvu_mrf', wx_data)
    Wh = npu.malloc(layer_name+'Wh', units, output_size, 'mvu_mrf', wh_data)

    # Allocate output and intermediate vectors
    hz = [None] * SIM_BATCH
    h1 = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * 1
    h2 = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * 1
    for k in range(int(num_inputs / BATCH)):
        for i in range(SIM_BATCH):
                h1[0][k][i] = npu.malloc(layer_name+'_h1', output_size, None, dest_memspace)
                h2[0][k][i] = npu.malloc(layer_name+'_h2', output_size, None, dest_memspace)
    for i in range(SIM_BATCH):
        hz[i] = npu.malloc(layer_name+'_hz', output_size, None, dest_memspace)
    tmp = [None] * SIM_BATCH
    for i in range(SIM_BATCH):
        tmp[i] = npu.malloc('tmp',  output_size, None, 'mfu0_add')

    # Allocate or retrieve input vectors
    x = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * time_steps
    if(layer_idx == 0):
        for t in range(time_steps):
            for k in range(int(num_inputs / BATCH)):
                for i in range(SIM_BATCH):
                    x[t][k][i] = npu.malloc(layer_name, input_size, None, 'mvu_vrf', inputs[t][(k * SIM_BATCH) + i])
    else:
        x = npu.operands[layer_idx-1]    

    for k in range(int(num_inputs / BATCH)):
        # Chain 0 : Load x
        npu.load(x[0][k], write_to_obuf=0, batch=SIM_BATCH)
        for t in range(time_steps):
            # Chain 1: tmp = x{t} * Wx
            intermediate = npu.matvec_mult(x[t][k], Wx, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp, write_to_obuf=0, batch=SIM_BATCH)
            
            # Chain 2: Load x
            if(t < time_steps-1):
                npu.load(x[t+1][k], write_to_obuf=0, batch=SIM_BATCH)
            
            # Chain 3: h{t+1} = tanh(h{t} * Wh + tmp)
            if(t == 0):
            	intermediate = npu.matvec_mult(hz, Wh, batch=SIM_BATCH)
            elif(t % 2 == 0):
                intermediate = npu.matvec_mult(h1[0][k], Wh, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h2[0][k], Wh, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp, batch=SIM_BATCH)
            if(activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(activation == 'sigmoid'):
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            if(t % 2 == 0):
                npu.write_back(intermediate, h2[0][k], write_to_obuf=(t == time_steps-1), batch=SIM_BATCH)
            else:
                npu.write_back(intermediate, h1[0][k], write_to_obuf=(t == time_steps-1), batch=SIM_BATCH)
    
    if(time_steps % 2 == 0):
        npu.operands.append(h1)
    else:
        npu.operands.append(h2)

def npu_gru(npu, layer_name, layer_idx, time_steps, num_inputs, input_size, units, output_size, uz_data, uc_data, ur_data, \
    wz_data, wc_data, wr_data, dest_memspace, inputs=None, activation='tanh', recurrent_activation='sigmoid'):
    SIM_BATCH = 3
    BATCH = 6

    # Allocate Matrices
    Uz = npu.malloc(layer_name+'_Uz', input_size, output_size, 'mvu_mrf', uz_data)
    Uc = npu.malloc(layer_name+'_Uc', input_size, output_size, 'mvu_mrf', uc_data)
    Ur = npu.malloc(layer_name+'_Ur', input_size, output_size, 'mvu_mrf', ur_data)
    Wz = npu.malloc(layer_name+'_Wz', units, output_size, 'mvu_mrf', wz_data)
    Wc = npu.malloc(layer_name+'_Wc', units, output_size, 'mvu_mrf', wc_data)
    Wr = npu.malloc(layer_name+'_Wr', units, output_size, 'mvu_mrf', wr_data)

    # Allocate output and intermediate vectors
    ones = [None] * SIM_BATCH
    tmp1 = [None] * SIM_BATCH
    tmp2 = [None] * SIM_BATCH
    tmp3 = [None] * SIM_BATCH
    tmp4 = [None] * SIM_BATCH
    tmp5 = [None] * SIM_BATCH
    tmp6 = [None] * SIM_BATCH
    tmp7 = [None] * SIM_BATCH
    ct = [None] * SIM_BATCH
    htmp = [None] * SIM_BATCH
    htmpz = [None] * SIM_BATCH
    for i in range(SIM_BATCH):
        ones[i] = npu.malloc('ones', output_size, None, 'evrf',  np.ones((output_size), dtype=npu.ac_data_type))
        tmp1[i] = npu.malloc('tmp1', output_size, None, 'mfu0_add')
        tmp2[i] = npu.malloc('tmp2', output_size, None, 'mfu0_add')
        tmp3[i] = npu.malloc('tmp3', output_size, None, 'mfu0_add')
        tmp4[i] = npu.malloc('tmp4', output_size, None, 'mfu0_mul')
        tmp5[i] = npu.malloc('tmp4', output_size, None, 'mfu0_add')
        tmp6[i] = npu.malloc('tmp6', output_size, None, 'mfu1_add')
        tmp7[i] = npu.malloc('tmp7', output_size, None, 'mvu_vrf')
        ct[i] = npu.malloc('ct',  output_size, None, 'evrf')
        htmp[i] = npu.malloc('h', output_size, None, 'mfu1_mul')
        htmpz[i] = npu.malloc('hz', output_size, None, 'mfu1_mul')

    hz = [None] * SIM_BATCH
    h = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * 1
    for k in range(int(num_inputs / BATCH)):
        for i in range(SIM_BATCH):
                h[0][k][i] = npu.malloc(layer_name+'_h', output_size, None, dest_memspace)
    for i in range(SIM_BATCH):
        hz[i] = npu.malloc(layer_name+'_hz', output_size, None, dest_memspace)
    
    # Allocate or retrieve input vectors
    x = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * time_steps
    if(layer_idx == 0):
        for t in range(time_steps):
            for k in range(int(num_inputs / BATCH)):
                for i in range(SIM_BATCH):
                    x[t][k][i] = npu.malloc(layer_name, input_size, None, 'mvu_vrf', inputs[t][(k * SIM_BATCH) + i])
    else:
        x = npu.operands[layer_idx-1]   

    npu.load(ones, write_to_obuf=0, batch=SIM_BATCH)
    for k in range(int(num_inputs / BATCH)):
        # Chain 0 
        if(layer_idx == 0):
            npu.load(x[0][k], write_to_obuf=0, batch=SIM_BATCH)
        for t in range(time_steps):
            # Chain 1
            intermediate = npu.matvec_mult(x[t][k], Uz, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp1, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 2
            intermediate = npu.matvec_mult(x[t][k], Ur, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp2, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 3
            intermediate = npu.matvec_mult(x[t][k], Uc, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp3, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 4
            if(t < time_steps-1):
                npu.load(x[t+1][k], write_to_obuf=0, batch=SIM_BATCH)
            # Chain 5
            if(t == 0):
                intermediate = npu.matvec_mult(hz, Wz, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h[0][k], Wz, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp1, batch=SIM_BATCH)
            if(recurrent_activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(recurrent_activation == 'tanh'):
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp4, tmp5, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 6
            intermediate = npu.read_evrf(ones, batch=SIM_BATCH)
            intermediate = npu.sub_a_b(intermediate, tmp5, batch=SIM_BATCH)
            if (t == 0):
                intermediate = npu.multiply(intermediate, htmpz, batch=SIM_BATCH)
            else:
                intermediate = npu.multiply(intermediate, htmp, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp6, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 7
            if(t == 0):
                intermediate = npu.matvec_mult(hz, Wr, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h[0][k], Wr, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp2, batch=SIM_BATCH)
            if(recurrent_activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(recurrent_activation == 'tanh'):
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            if(t == 0):
                intermediate = npu.multiply(intermediate, htmpz, batch=SIM_BATCH)
            else:
                intermediate = npu.multiply(intermediate, htmp, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp7, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 8
            intermediate = npu.matvec_mult(tmp7, Wc, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp3, batch=SIM_BATCH)
            if(activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(activation == 'sigmoid'):
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            npu.write_back(intermediate, ct, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 9
            intermediate = npu.read_evrf(ct, batch=SIM_BATCH)
            intermediate = npu.multiply(intermediate, tmp4, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp6, batch=SIM_BATCH)
            npu.write_back(intermediate, h[0][k], htmp, write_to_obuf=(t == time_steps-1), batch=SIM_BATCH)

    npu.operands.append(h)

def npu_lstm(npu, layer_name, layer_idx, time_steps, num_inputs, input_size, units, output_size, uf_data, uc_data, ui_data, uo_data, \
        wf_data, wc_data, wi_data, wo_data, dest_memspace, inputs, activation, recurrent_activation):
    SIM_BATCH = 3
    BATCH = 6

    # Allocate Matrices
    Uf = npu.malloc(layer_name+'_Uf', input_size, output_size, 'mvu_mrf', uf_data)
    Uc = npu.malloc(layer_name+'_Uc', input_size, output_size, 'mvu_mrf', uc_data)
    Ui = npu.malloc(layer_name+'_Ui', input_size, output_size, 'mvu_mrf', ui_data)
    Uo = npu.malloc(layer_name+'_Uo', input_size, output_size, 'mvu_mrf', uo_data)
    Wf = npu.malloc(layer_name+'_Wf', units, output_size, 'mvu_mrf', wf_data)
    Wc = npu.malloc(layer_name+'_Wc', units, output_size, 'mvu_mrf', wc_data)
    Wi = npu.malloc(layer_name+'_Wi', units, output_size, 'mvu_mrf', wi_data)
    Wo = npu.malloc(layer_name+'_Wo', units, output_size, 'mvu_mrf', wo_data)

    # Allocate output and intermediate vectors
    tmp1 = [None] * SIM_BATCH
    tmp2 = [None] * SIM_BATCH
    tmp3 = [None] * SIM_BATCH
    tmp4 = [None] * SIM_BATCH
    tmp5 = [None] * SIM_BATCH
    tmp6 = [None] * SIM_BATCH
    tmp7 = [None] * SIM_BATCH
    tmp8 = [None] * SIM_BATCH
    ct = [None] * SIM_BATCH
    ctz = [None] * SIM_BATCH
    for i in range(SIM_BATCH):
        tmp1[i] = npu.malloc('tmp1', output_size, None, 'mfu0_add')
        tmp2[i] = npu.malloc('tmp2', output_size, None, 'mfu0_add')
        tmp3[i] = npu.malloc('tmp3', output_size, None, 'mfu0_add')
        tmp4[i] = npu.malloc('tmp4', output_size, None, 'mfu0_add')
        tmp5[i] = npu.malloc('tmp5', output_size, None, 'mfu0_mul')
        tmp6[i] = npu.malloc('tmp6', output_size, None, 'mfu1_mul')
        tmp7[i] = npu.malloc('tmp7', output_size, None, 'mfu0_mul')
        tmp8[i] = npu.malloc('tmp8', output_size, None, 'mfu1_add')
        ct[i] = npu.malloc('ct', output_size, None, 'evrf')
        ctz[i] = npu.malloc('ctz', output_size, None, 'evrf')

    hz = [None] * SIM_BATCH
    h = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * 1
    for k in range(int(num_inputs / BATCH)):
        for i in range(SIM_BATCH):
                h[0][k][i] = npu.malloc(layer_name+'_h', output_size, None, dest_memspace)
    for i in range(SIM_BATCH):
        hz[i] = npu.malloc(layer_name+'_hz', output_size, None, dest_memspace)
    
    # Allocate or retrieve input vectors
    x = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * time_steps
    if(layer_idx == 0):
        for t in range(time_steps):
            for k in range(int(num_inputs / BATCH)):
                for i in range(SIM_BATCH):
                    x[t][k][i] = npu.malloc(layer_name, input_size, None, 'mvu_vrf', inputs[t][(k * SIM_BATCH) + i])
    else:
        x = npu.operands[layer_idx-1]   


    for k in range(int(num_inputs / BATCH)):
        # Chain 0
        if(layer_idx == 0):
            npu.load(x[0][k], write_to_obuf=0, batch=SIM_BATCH)
        for t in range(time_steps):
            # Chain 1
            intermediate = npu.matvec_mult(x[t][k], Uf, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp1, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 2
            intermediate = npu.matvec_mult(x[t][k], Uc, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp2, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 3
            intermediate = npu.matvec_mult(x[t][k], Ui, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp3, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 4
            intermediate = npu.matvec_mult(x[t][k], Uo, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp4, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 5
            if(t < time_steps-1):
                npu.load(x[t+1][k], write_to_obuf=0, batch=SIM_BATCH)
            # Chain 6
            if(t == 0):
                intermediate = npu.matvec_mult(hz, Wf, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h[0][k], Wf, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp1, batch=SIM_BATCH)
            if(recurrent_activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(recurrent_activation == 'tanh'):
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp5, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 7
            if(t == 0):
                intermediate = npu.matvec_mult(hz, Wi, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h[0][k], Wi, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp3, batch=SIM_BATCH)
            if(recurrent_activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(recurrent_activation == 'tanh'):
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp6, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 8
            if(t == 0):
                intermediate = npu.matvec_mult(hz, Wo, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h[0][k], Wo, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp4, batch=SIM_BATCH)
            if(recurrent_activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(recurrent_activation == 'tanh'):
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp7, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 9
            if(t == 0):
                intermediate = npu.matvec_mult(hz, Wc, batch=SIM_BATCH)
            else:
                intermediate = npu.matvec_mult(h[0][k], Wc, batch=SIM_BATCH)
            intermediate = npu.add(intermediate, tmp2, batch=SIM_BATCH)
            if(activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(activation == 'sigmoid'):
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            intermediate = npu.multiply(intermediate, tmp6, batch=SIM_BATCH)
            npu.write_back(intermediate, tmp8, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 10
            if (t == 0):
                intermediate = npu.read_evrf(ctz, batch=SIM_BATCH)
            else:
                intermediate = npu.read_evrf(ct, batch=SIM_BATCH)
            intermediate = npu.multiply(intermediate, tmp5, batch=SIM_BATCH)
            intermediate = npu.add (intermediate, tmp8, batch=SIM_BATCH)
            npu.write_back(intermediate, ct, write_to_obuf=0, batch=SIM_BATCH)
            # Chain 11
            intermediate = npu.read_evrf(ct, batch=SIM_BATCH)
            if(activation == 'relu'):
                intermediate = npu.relu(intermediate, batch=SIM_BATCH)
            elif(activation == 'sigmoid'):
                intermediate = npu.sigmoid(intermediate, batch=SIM_BATCH)
            else:
                intermediate = npu.tanh(intermediate, batch=SIM_BATCH)
            intermediate = npu.multiply(intermediate, tmp7, batch=SIM_BATCH)
            npu.write_back(intermediate, h[0][k], write_to_obuf=(t == time_steps-1), batch=SIM_BATCH)
    
    npu.operands.append(h)

def npu_preprocessing(npu, max_tokens, seq_length, num_inputs):
    SIM_BATCH = 3
    BATCH = 6

    x = [[[None] * SIM_BATCH] * int(num_inputs/BATCH)] * time_steps
    for t in range(time_steps):
        for k in range(int(num_inputs / BATCH)):
            for i in range(SIM_BATCH):
                input_data = np.zeros(seq_length)
                random_idx = np.random.choice(seq_length, 1, replace=False) 
                input_data[random_idx] = 1
                x[t][k][i] = npu.malloc(layer_name, input_size, None, 'mvu_vrf', input_data)

    npu.operands.append(x)

class NPUSequential(keras.Sequential):
    def __init__(self, layers=None, name=None):
        super(NPUSequential, self).__init__(layers, name)

    def compile_for_npu(self, npu, inputs):
        unsupported_layers = []
        ops = 0
        for i in range(len(self.layers)):
            config = self.layers[i].get_config()
            layer_name = self.layers[i].name
            layer_idx = i
            weights = self.layers[i].get_weights()

            if isinstance(self.layers[i], keras.layers.Dense):
                w_data = np.transpose(weights[0])
                input_size = int(w_data.shape[1])
                output_size = int(w_data.shape[0])
                w_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                if (i == 0):
                    num_inputs = int(math.ceil(int(inputs.shape[0]) / 6.0)) * 6
                else:
                    num_inputs = len(npu.operands[i-1][0]) * 6
                input_data = np.random.randint(-128, 127, size=(num_inputs, input_size), dtype=np.int8)
                dest_memspace = 'mvu_vrf'
                activation = config['activation']
                style = 'normal'
                npu_dense(npu, layer_name, layer_idx, num_inputs, 1, input_size, output_size, w_data, dest_memspace, input_data, activation, style, i==len(self.layers)-1)
                ops = ops + (num_inputs * input_size * output_size * 2)
            
            elif isinstance(self.layers[i], keras.layers.Embedding):
                w_data = np.transpose(weights[0])
                input_size = config['input_dim']
                output_size = config['output_dim']
                dest_memspace = 'mvu_vrf'
                if(i == 0):
                    num_inputs = int(math.ceil(int(inputs.shape[0]) / 6.0)) * 6
                    time_steps = inputs.shape[1]
                else:
                    num_inputs = len(npu.operands[i-1][0]) * 6
                    time_steps = len(npu.operands[i-1])
                activation = None
                style = 'embedding'
                npu_dense(npu, layer_name, layer_idx, num_inputs, time_steps, input_size, output_size, w_data, dest_memspace, inputs, activation, style)
                ops = ops + (num_inputs * time_steps * input_size * output_size * 2)

            elif isinstance(self.layers[i], keras.layers.SimpleRNN):
                wx_data = weights[0]
                wh_data = weights[1]
                input_size = int(wx_data.shape[0])
                units = config['units']
                output_size = int(wx_data.shape[1])
                wx_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                wh_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                if(i == 0):
                    time_steps = inputs.shape[0]
                    num_inputs = int(math.ceil(int(inputs.shape[1]) / 6.0)) * 6
                    assert input_size == int(inputs.shape[2]), 'Incompatible input dimensions for ('+layer_name+')'
                else:
                    time_steps = len(npu.operands[i-1])
                    num_inputs = len(npu.operands[i-1][0]) * 6
                input_data = np.random.randint(-128, 127, size=(time_steps, num_inputs, input_size), dtype=np.int8)
                dest_memspace = 'mvu_vrf'
                activation = config['activation']
                assert activation in ['relu', 'sigmoid', 'tanh'], 'Specified activation function for ('+layer_name+') is not supported by NPU'
                npu_rnn(npu, layer_name, layer_idx, time_steps, num_inputs, input_size, units, output_size, wx_data, wh_data, dest_memspace, input_data, activation)
                ops = ops + (time_steps * num_inputs * input_size * output_size * 2 * 2)

            elif isinstance(self.layers[i], keras.layers.GRU):
                # Dimensions 
                input_size = int(weights[0].shape[0])
                output_size = int(int(weights[0].shape[1]) / 3)
                units = config['units']
                if(i == 0):
                    time_steps = int(inputs.shape[0])
                    num_inputs = int(math.ceil(int(inputs.shape[1]) / 6.0)) * 6
                    assert input_size == int(inputs.shape[2]), 'Incompatible input dimensions for ('+layer_name+')'
                else:
                    time_steps = len(npu.operands[i-1])
                    num_inputs = len(npu.operands[i-1][0]) * 6
                # Weight Matrices
                uz_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                uc_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                ur_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                wz_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                wc_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                wr_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                input_data = np.random.randint(-128, 127, size=(time_steps, num_inputs, input_size), dtype=np.int8)
                # Other params
                dest_memspace = 'mvu_vrf'
                activation = config['activation']
                assert activation in ['relu', 'sigmoid', 'tanh'], 'Specified activation function for ('+layer_name+') is not supported by NPU'
                recurrent_activation = config['recurrent_activation']
                assert recurrent_activation in ['relu', 'sigmoid', 'tanh'], 'Specified recurrent activation function for ('+layer_name+') is not supported by NPU'
                npu_gru(npu, layer_name, layer_idx, time_steps, num_inputs, input_size, units, output_size, uz_data, uc_data, ur_data, \
                    wz_data, wc_data, wr_data, dest_memspace, input_data, activation, recurrent_activation)
                ops = ops + (time_steps * num_inputs * input_size * output_size * 6 * 2)

            elif isinstance(self.layers[i], keras.layers.LSTM):
                # Dimensions 
                input_size = int(weights[0].shape[0])
                output_size = int(int(weights[0].shape[1]) / 4)
                units = config['units']
                if(i == 0):
                    time_steps = int(inputs.shape[0])
                    num_inputs = int(math.ceil(int(inputs.shape[1]) / 6.0)) * 6
                    assert input_size == int(inputs.shape[2]), 'Incompatible input dimensions for ('+layer_name+')'
                else:
                    time_steps = len(npu.operands[i-1])
                    num_inputs = len(npu.operands[i-1][0]) * 6
                # Weight Matrices
                uf_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                uc_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                ui_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                uo_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                wf_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                wc_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                wi_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8) 
                wo_data = np.random.randint(0, 127, size=(output_size, input_size), dtype=np.int8)
                input_data = np.random.randint(-128, 127, size=(time_steps, num_inputs, input_size), dtype=np.int8) 
                # Other params
                dest_memspace = 'mvu_vrf'
                activation = config['activation']
                assert activation in ['relu', 'sigmoid', 'tanh'], 'Specified activation function for ('+layer_name+') is not supported by NPU'
                recurrent_activation = config['recurrent_activation']
                assert recurrent_activation in ['relu', 'sigmoid', 'tanh'], 'Specified recurrent activation function for ('+layer_name+') is not supported by NPU'
                npu_lstm(npu, layer_name, layer_idx, time_steps, num_inputs, input_size, units, output_size, uf_data, uc_data, ui_data, uo_data, \
                    wf_data, wc_data, wi_data, wo_data, dest_memspace, input_data, activation, recurrent_activation)
                ops = ops + (time_steps * num_inputs * input_size * output_size * 8 * 2)

            elif isinstance(self.layers[i], keras.layers.experimental.preprocessing.TextVectorization):
                max_tokens = config['max_tokens']
                seq_length = config['output_sequence_length']
                num_inputs = int(math.ceil(len(inputs) / 6.0)) * 6
                npu_preprocessing(npu, max_tokens, seq_length, num_inputs)

            else:
                print(layer_name+' type is not supported by NPU')
                exit(0)

        npu.unsupported_layers = unsupported_layers
        npu.ops = ops
