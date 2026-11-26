#==============================================================================
# sim_libs_example.do : precompiled simulation libraries, template
#
# Copy this file to sim_libs.do (same folder) when the DUT needs vendor libraries
# (IP such as altera_mf, primitives such as unisims). sim_libs.do is not handed on
# (it is in .gitignore); this example is. Without sim_libs.do no library is added.
# Write paths with forward slashes.
#==============================================================================

# folder that holds the libraries below that are given by name
set SIM_LIB_DIR D:/software/ModelSim/ModelSim10.4/sim_lib_quartus_prime_standard/verilog_libs

# libraries added with -L: a name (searched in SIM_LIB_DIR) or the full path of a library folder;
# the library name in Questa is the folder name. Missing ones are skipped with a warning.
set SIM_LIBS {
    altera_mf_ver
    lpm_ver
}

# examples
# set SIM_LIBS {altera_mf_ver cyclonev_ver lpm_ver altera_ver}
# set SIM_LIBS {D:/modeltech64_10.4/anlogic/PH1}
