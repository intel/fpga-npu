CC 			:= g++
HEADER  	:= inc/
CFLAGS 		:= -c -g -std=c++11  -Wall -Wextra
INCLUDES 	:= -I ./inc/
OBJ_DIR 	:= ./src/obj/
SIM_DIR		:= ./main/obj/
EXE			:= npu_sim 

OBJ := \
		$(OBJ_DIR)port.o \
		$(OBJ_DIR)input.o \
		$(OBJ_DIR)output.o \
		$(OBJ_DIR)channel.o \
		$(OBJ_DIR)dpe.o \
		$(OBJ_DIR)mvu_vrf.o \
		$(OBJ_DIR)accumulator.o \
		$(OBJ_DIR)register_file.o \
		$(OBJ_DIR)tile.o \
		$(OBJ_DIR)mvu.o \
		$(OBJ_DIR)evrf.o \
		$(OBJ_DIR)mfu.o \
		$(OBJ_DIR)loader.o \
		$(OBJ_DIR)datapath.o \
		$(OBJ_DIR)decoder.o \
		$(OBJ_DIR)npu.o \
		$(OBJ_DIR)utils.o

all: $(EXE) 

%: $(SIM_DIR)%.o $(OBJ)   
	$(CC) -g $(OBJ) $< -o $@

$(SIM_DIR)%.o: main/%.cpp  
	$(CC) $(INCLUDES) $(CFLAGS) $< -o $@

$(OBJ_DIR)%.o: src/%.cpp 
	$(CC) $(INCLUDES) $(CFLAGS) $< -o $@

clean: 
	rm   $(OBJ) $(EXE)

.PRECIOUS: $(OBJ)

