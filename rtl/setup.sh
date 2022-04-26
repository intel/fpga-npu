# initialize variables
TOP_LEVEL_NAME="npu_tb"

QUARTUS_INSTALL_DIR=$QUARTUS_ROOTDIR
SKIP_SIM=1
#USER_DEFINED_ELAB_OPTIONS="+vcs+lic+wait -debug_access+pp"
USER_DEFINED_ELAB_OPTIONS="+vcs+lic+wait"
USER_DEFINED_ELAB_OPTIONS_APPEND=""
USER_DEFINED_SIM_OPTIONS=""

# ----------------------------------------
# overwrite variables - DO NOT MODIFY!
# This block evaluates each command line argument, typically used for 
# overwriting variables. An example usage:
#   sh <simulator>_setup.sh SKIP_SIM=1
for expression in "$@"; do
  eval $expression
  if [ $? -ne 0 ]; then
    echo "Error: This command line argument, \"$expression\", is/has an invalid expression." >&2
    exit $?
  fi
done

#-------------------------------------------
# check tclsh version no earlier than 8.5 
version=$(echo "puts [package vcompare [info tclversion] 8.5]; exit" | tclsh)
if [ $version -eq -1 ]; then 
  echo "Error: Minimum required tcl package version is 8.5." >&2 
  exit 1 
fi 

ELAB_OPTIONS=""

design_files="*.sv *.v"

vcs -lca -timescale=1ps/1ps -sverilog +verilog2001ext+.v $USER_DEFINED_ELAB_OPTIONS \
  -v $QUARTUS_INSTALL_DIR/eda/sim_lib/altera_primitives.v \
  -v $QUARTUS_INSTALL_DIR/eda/sim_lib/220model.v \
  -v $QUARTUS_INSTALL_DIR/eda/sim_lib/sgate.v \
  -v $QUARTUS_INSTALL_DIR/eda/sim_lib/altera_mf.v \
  $QUARTUS_INSTALL_DIR/eda/sim_lib/fourteennm_atoms.sv \
  $QUARTUS_INSTALL_DIR/eda/sim_lib/synopsys/fourteennm_atoms_ncrypt.sv \
  $design_files \
  $USER_DEFINED_ELAB_OPTIONS_APPEND \
  -top $TOP_LEVEL_NAME -R #-gui &

# ----------------------------------------
# simulate
if [ $SKIP_SIM -eq 0 ]; then
  ./simv $SIM_OPTIONS $USER_DEFINED_SIM_OPTIONS
fi

#$QUARTUS_INSTALL_DIR/eda/sim_lib/altera_lnsim.sv \
#$QUARTUS_INSTALL_DIR/eda/sim_lib/ct1_hssi_atoms.sv \
#$QUARTUS_INSTALL_DIR/eda/sim_lib/synopsys/ct1_hssi_atoms_ncrypt.sv \
#$QUARTUS_INSTALL_DIR/eda/sim_lib/synopsys/cr3v0_serdes_models_ncrypt.sv \
#$QUARTUS_INSTALL_DIR/eda/sim_lib/ct1_hip_atoms.sv \
#$QUARTUS_INSTALL_DIR/eda/sim_lib/synopsys/ct1_hip_atoms_ncrypt.sv \
