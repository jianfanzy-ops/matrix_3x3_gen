#==============================================================================
# local_paths_example.do : machine dependent paths, template
#
# Copy this file to local_paths.do (same folder) and set the paths of this computer.
# local_paths.do is not handed on (it is in .gitignore); this example is.
# Write paths with forward slashes, without quotes or braces.
#==============================================================================

# folder of vsim.exe, read by run_img_sim.bat; leave it out when vsim is in PATH
set QUESTA_BIN D:/software/Questa/win64

# folder of the precompiled simulation libraries listed in SIM_LIBS of tb_run.do,
# only needed when SIM_LIBS is not empty
set SIM_LIB_DIR D:/software/ModelSim/ModelSim10.4/sim_lib_quartus_prime_standard/verilog_libs
