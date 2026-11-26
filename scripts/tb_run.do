#==============================================================================
# tb_run.do : collect the sources automatically, compile, simulate
#
#   - every *.sv below the source roots is compiled, new RTL files only have to be
#     put below ../rtl, this script is not changed for them
#   - files that declare a package are found by their content and compiled FIRST,
#     wherever they are and whatever they are called (import needs the package
#     to be in the library already, this is the only real order dependency)
#   - header files are NOT compiled, they are only reached by `include:
#       * every file in a directory named "include"
#       * every file matching EXCLUDE_FILES (define_isp.sv, *_define.sv ...)
#   - every directory below the source roots is an include directory, so
#     `include "x.sv", `include "./include/x.sv" and `include "./../x.sv" all resolve
#   - the generated list is written to compile_auto.f (look there when a file is missing)
#
# This script is not changed:
#   - image, frame count, handshake mode and the DUT are set in ../tb/tb_top.sv
#   - machine dependent paths are in local_paths.do (copy of local_paths_example.do)
#   - simulation libraries are in sim_libs.do      (copy of sim_libs_example.do)
#==============================================================================

#------------------------------------------------------------------------------
# settings
#------------------------------------------------------------------------------
set SRC_ROOTS     {../rtl ../tb/tb_rtl}
set TB_TOP        tb_top
# the testbench top is always in ../tb/ relative to this .do file.
# The directory of this .do file is the current directory: Questa must be started
# there (run_img_sim.bat does it). "info script" is not used on purpose, inside
# "vsim -do" it returns a directory of the Questa installation.
set DO_DIR        .
if {![file exists [file join $DO_DIR tb_run.do]]} {
    error "run this script from its own directory (cd there first, or use run_img_sim.bat). Current directory: [pwd]"
}
set TB_DIR        [file join $DO_DIR .. tb]
set TB_FILES      [list [file join $TB_DIR $TB_TOP.sv]]
set OUT_DIR       [file join $DO_DIR .. pic out]
set DEFINES       {SIMULATION}

# directories whose files are headers (never compiled as a source)
set HEADER_DIRS   {include}
# file name patterns that are headers or must not be compiled
set EXCLUDE_FILES {define_*.sv *_define.sv}

#------------------------------------------------------------------------------
# NOT set here, so this script is the same for everybody:
#
#   local_paths.do (copy of local_paths_example.do, not handed on)
#       QUESTA_BIN  : folder of vsim.exe, only read by run_img_sim.bat
#   sim_libs.do    (copy of sim_libs_example.do, not handed on)
#       SIM_LIBS    : precompiled simulation libraries the DUT needs (vendor IP, primitives),
#                     a library name (searched in SIM_LIB_DIR) or the full path of a library
#       SIM_LIB_DIR : folder that holds the libraries given by name;
#                     when not set there, the environment variable SIM_LIB_DIR is used
# Both files are optional: without sim_libs.do no library is added.
#------------------------------------------------------------------------------
set SIM_LIBS    {}
set SIM_LIB_DIR {}

foreach f {local_paths.do sim_libs.do} {
    set p [file join $DO_DIR $f]
    if {[file exists $p]} {
        puts "settings from: $p"
        source $p
    }
}
if {$SIM_LIB_DIR eq "" && [info exists env(SIM_LIB_DIR)]} { set SIM_LIB_DIR $env(SIM_LIB_DIR) }

# every library: a folder given directly, or a name below SIM_LIB_DIR
set lib_dirs {}
foreach l $SIM_LIBS {
    if {[file isdirectory $l]} {
        lappend lib_dirs $l
    } elseif {$SIM_LIB_DIR eq "" || ![file isdirectory $SIM_LIB_DIR]} {
        error "simulation library '$l' is given by name, but SIM_LIB_DIR is not set or not found: '$SIM_LIB_DIR'.\n\
Set SIM_LIB_DIR in sim_libs.do (copy of sim_libs_example.do), or the environment variable SIM_LIB_DIR."
    } else {
        lappend lib_dirs [file join $SIM_LIB_DIR $l]
    }
}

#------------------------------------------------------------------------------
# helpers
#------------------------------------------------------------------------------
proc is_excluded_file {f} {
    global EXCLUDE_FILES
    foreach p $EXCLUDE_FILES {
        if {[string match $p [file tail $f]]} { return 1 }
    }
    return 0
}

# 1: the file declares a package (a line starting with "package <name>")
proc has_package {f} {
    set fd [open $f r]
    set txt [read $fd]
    close $fd
    return [regexp -line {^\s*package\s+\w+} $txt]
}

# walk one directory tree: packages go to pkg_list, other sources to src_list,
# every directory goes to inc_list
proc collect {dir pkg_name src_name inc_name} {
    global HEADER_DIRS
    upvar $pkg_name pkg_list
    upvar $src_name src_list
    upvar $inc_name inc_list

    lappend inc_list $dir
    set is_header_dir [expr {[lsearch -exact $HEADER_DIRS [file tail $dir]] >= 0}]
    foreach f [lsort [glob -nocomplain -types f -directory $dir *.sv *.v]] {
        if {[has_package $f]} {
            lappend pkg_list $f
        } elseif {!$is_header_dir && ![is_excluded_file $f]} {
            lappend src_list $f
        }
    }
    foreach d [lsort [glob -nocomplain -types d -directory $dir *]] {
        collect $d pkg_list src_list inc_list
    }
}

#------------------------------------------------------------------------------
# collect
#------------------------------------------------------------------------------
set pkg_list {}
set src_list {}
set inc_list {}
foreach root $SRC_ROOTS {
    if {![file isdirectory $root]} {
        error "source root not found: $root"
    }
    collect $root pkg_list src_list inc_list
}
foreach f $TB_FILES {
    if {![file exists $f]} {
        error "testbench file not found: $f (TB_DIR = $TB_DIR, current directory = [pwd])"
    }
    lappend src_list $f
    lappend inc_list [file dirname $f]
}
# packages first
set src_list [concat $pkg_list $src_list]
foreach f $pkg_list { puts "package file, compiled first: $f" }

# two files with the same name usually mean the same module twice: the later one
# silently replaces the earlier one in the library, so only warn here
array unset seen
foreach f $src_list {
    set t [file tail $f]
    if {[info exists seen($t)]} {
        puts "WARNING: same file name twice: $seen($t)  and  $f"
    } else {
        set seen($t) $f
    }
}

# write the file list
set fd [open compile_auto.f w]
foreach d [lsort -unique $inc_list] { puts $fd "+incdir+$d" }
foreach m $DEFINES                  { puts $fd "+define+$m" }
foreach f $src_list                 { puts $fd $f }
close $fd
puts "compile_auto.f: [llength $pkg_list] package files, [llength $src_list] files in total, [llength [lsort -unique $inc_list]] include directories"

#------------------------------------------------------------------------------
# compile
#------------------------------------------------------------------------------
quit -sim
catch {.main clear}

if {[file exists work]} {
    file delete -force work
}
vlib work
vmap work work

# -sfcu: every file is its own compilation unit, nothing leaks from one file to
#        the next, so the result does not depend on the compile order
# -suppress 13314: "Defaulting port kind to var rather than wire", hides the real messages
vlog -sv -sfcu -suppress 13314 -work work -f compile_auto.f

#------------------------------------------------------------------------------
# simulate
#------------------------------------------------------------------------------
# output folder of the saved frames (the testbench writes ../pic/out/dut_out_f<n>.bmp)
file mkdir $OUT_DIR

set vsim_cmd [list vsim -L work]

# simulation libraries: map the logical name (= folder name), then search it
foreach d $lib_dirs {
    set l [file tail $d]
    if {[file isdirectory $d]} {
        vmap $l $d
        lappend vsim_cmd -L $l
    } else {
        puts "WARNING: simulation library not found, skipped: $d"
    }
}

lappend vsim_cmd -voptargs=+acc work.$TB_TOP
eval $vsim_cmd

run -all
