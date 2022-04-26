import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = "2"
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
#import sys
#sys.path.append('../compiler/')

from compiler import *
from npu_layers import *

###### START OF MODEL DEFINITION ######

# Define constants
INPUT_SIZE = 1024
HIDDEN_UNITS = 1024
TIME_STEPS = 8

# Define model architecture using Keras Sequential Model
model = NPUSequential([
	layers.SimpleRNN(HIDDEN_UNITS, name="layer1"),
])

# Random test inputs for different types of layers
test_input = tf.random.uniform(shape=[TIME_STEPS, 6, INPUT_SIZE], minval=-128, maxval=127)

# Call model on example input
y = model(test_input)

# Print model summary
model.summary()

####### END OF MODEL DEFINITION #######

# Initialize NPU
npu = initialize_npu(sys.argv)
# Compile model for NPU
model.compile_for_npu(npu, test_input)
# Run NPU flow
npu.run_flow()
