#==============================================================================
# local_paths_example.do : machine dependent paths, template
#
# Copy this file to local_paths.do (same folder) and set the paths of this computer.
# local_paths.do is not handed on (it is in .gitignore); this example is.
# Write paths with forward slashes, without quotes or braces.
# Simulation libraries are set in sim_libs.do (copy of sim_libs_example.do).
#==============================================================================

# folder of vsim.exe, read by run_img_sim.bat; leave it out when vsim is in PATH
set QUESTA_BIN D:/software/Questa/win64
