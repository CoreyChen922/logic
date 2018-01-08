# Copyright 2017 Tymoteusz Blazejczyk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if (COMMAND add_hdl_source)
    return()
endif()

find_package(ModelSim)
find_package(SystemC REQUIRED COMPONENTS SCV UVM)
find_package(Verilator)

include(AddVivadoProject)
include(AddQuartusProject)
include(CMakeParseArguments)

foreach (hdl_entry ${_HDL_LIST})
    unset(_HDL_${hdl_entry} CACHE)
endforeach()

set(_HDL_LIST "" CACHE INTERNAL "" FORCE)

set(_HDL_ONE_VALUE_ARGUMENTS
    NAME
    TYPE
    SOURCE
    TARGET
    LIBRARY
    SYNTHESIZABLE
    MODELSIM_LINT
    MODELSIM_PEDANTICERRORS
)

set(_HDL_MULTI_VALUE_ARGUMENTS
    COMPILE
    COMPILE_EXCLUDE
    DEFINES
    INCLUDES
    ANALYSIS
    SOURCES
    LIBRARIES
    PARAMETERS
    VERILATOR_CONFIGURATIONS
    DEPENDS
)

set(VERILATOR_CONFIGURATION_FILE
    ${CMAKE_CURRENT_LIST_DIR}/VerilatorConfig.cmake.in
    CACHE INTERNAL "Verilator configuration file" FORCE)

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/output)

if (MODELSIM_FOUND)
    set(MODELSIM_RUN_TCL
        ${CMAKE_CURRENT_LIST_DIR}/../scripts/modelsim_run.tcl
        CACHE INTERNAL "ModelSim run script" FORCE)

    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim/.modules)

    if (NOT EXISTS ${CMAKE_BINARY_DIR}/modelsim/work/_info)
        execute_process(COMMAND ${MODELSIM_VLIB} work
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim OUTPUT_QUIET)
    endif()

    if (NOT EXISTS ${CMAKE_BINARY_DIR}/modelsim/modelsim.ini)
        execute_process(COMMAND ${MODELSIM_VMAP} work work
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim OUTPUT_QUIET)
    endif()

    if (NOT TARGET modelsim-compile-all)
        add_custom_target(modelsim-compile-all ALL)
    endif()
endif()

if (VERILATOR_FOUND)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/verilator/.coverage)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/verilator/.configs)

    add_custom_target(verilator-coverage
        ${VERILATOR_COVERAGE_EXECUTABLE}
            --annotate-all
            --annotate ${CMAKE_BINARY_DIR}/verilator/.coverage
            ${CMAKE_BINARY_DIR}/output/*.dat
    )

    if (NOT TARGET verilator-compile-all)
        add_custom_target(verilator-compile-all ALL)
    endif()

    if (NOT TARGET verilator-analysis-all)
        add_custom_target(verilator-analysis-all)
    endif()
endif()

function(add_hdl_quartus hdl_target)
    set(QUARTUS_DEFINES ${QUARTUS_DEFINES}
        LOGIC_SYNTHESIS
    )

    if (QUARTUS_EDITION MATCHES Pro)
        set(QUARTUS_DEFINES ${QUARTUS_DEFINES}
            LOGIC_MODPORT_DISABLED
        )
    endif()

    get_target_property(quartus_analysis ${hdl_target} HDL_QUARTUS_ANALYSIS)

    if (quartus_analysis)
        add_quartus_project(${hdl_target})
    endif()
endfunction()

function(add_hdl_vivado hdl_target)
    set(VIVADO_DEFINES ${VIVADO_DEFINES}
        LOGIC_SYNTHESIS
    )

    get_target_property(vivado_analysis ${hdl_target} HDL_VIVADO_ANALYSIS)

    if (vivado_analysis)
        add_vivado_project(${hdl_target})
    endif()
endfunction()

function(get_hdl_depends hdl_target hdl_depends_var)
    set(hdl_depends "")

    cmake_parse_arguments(ARG "" "${_HDL_ONE_VALUE_ARGUMENTS}"
        "${_HDL_MULTI_VALUE_ARGUMENTS}" ${_HDL_${hdl_target}})

    foreach (name ${ARG_DEPENDS})
        get_hdl_depends(${name} depends)

        list(APPEND hdl_depends ${name})
        list(APPEND hdl_depends ${depends})
    endforeach()

    list(REMOVE_DUPLICATES hdl_depends)

    set(${hdl_depends_var} ${hdl_depends} PARENT_SCOPE)
endfunction()

function(add_hdl_modelsim hdl_name)
    if (NOT MODELSIM_FOUND)
        return()
    endif()

    cmake_parse_arguments(ARG "" "${_HDL_ONE_VALUE_ARGUMENTS}"
        "${_HDL_MULTI_VALUE_ARGUMENTS}" ${_HDL_${hdl_name}} ${ARGN})

    if (DEFINED ARG_COMPILE)
        if (NOT ARG_COMPILE MATCHES ALL AND NOT ARG_COMPILE MATCHES ModelSim)
            return()
        endif()
    endif()

    if (DEFINED ARG_COMPILE_EXCLUDE)
        if (ARG_COMPILE_EXCLUDE MATCHES ModelSim)
            return()
        endif()
    endif()

    set(modelsim_compiler)
    set(modelsim_flags "")

    if (ARG_TYPE MATCHES SystemVerilog)
        set(modelsim_compiler ${MODELSIM_VLOG})
    elseif (ARG_TYPE MATCHES Verilog)
        set(modelsim_compiler ${MODELSIM_VLOG})
    elseif (ARG_TYPE MATCHES VHDL)
        set(modelsim_compiler ${MODELSIM_VCOM})
    else()
        return()
    endif()

    if (ARG_MODELSIM_LINT)
        list(APPEND modelsim_flags -lint)
    endif()

    if (ARG_MODELSIM_PEDANTICERRORS)
        list(APPEND modelsim_flags -pedanticerrors)
    endif()

    list(APPEND modelsim_flags -work ${ARG_LIBRARY})

    if (ARG_TYPE MATCHES Verilog)
        if (ARG_TYPE MATCHES SystemVerilog)
            list(APPEND modelsim_flags -sv)
        endif()

        foreach (hdl_define ${ARG_DEFINES})
            list(APPEND modelsim_flags +define+${hdl_define})
        endforeach()

        foreach (hdl_include ${ARG_INCLUDES})
            if (CYGWIN)
                execute_process(COMMAND cygpath -m ${hdl_include}
                    OUTPUT_VARIABLE hdl_include
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
            endif()

            list(APPEND modelsim_flags +incdir+${hdl_include})
        endforeach()
    elseif (ARG_TYPE MATCHES VHDL)
        list(APPEND modelsim_flags -2008)
    endif()

    set(modelsim_modules_dir ${CMAKE_BINARY_DIR}/modelsim/.modules)

    if (NOT EXISTS ${CMAKE_BINARY_DIR}/modelsim/${ARG_LIBRARY})
        execute_process(COMMAND ${MODELSIM_VLIB} ${ARG_LIBRARY}
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim OUTPUT_QUIET)
    endif()

    if (NOT EXISTS ${modelsim_modules_dir}/${ARG_LIBRARY})
        file(MAKE_DIRECTORY ${modelsim_modules_dir}/${ARG_LIBRARY})
    endif()

    set(modelsim_sources "")

    foreach (modelsim_source ${ARG_SOURCES} ${ARG_SOURCE})
        if (CYGWIN)
            execute_process(COMMAND cygpath -m ${modelsim_source}
                OUTPUT_VARIABLE modelsim_source
                OUTPUT_STRIP_TRAILING_WHITESPACE)
        endif()

        list(APPEND modelsim_sources ${modelsim_source})
    endforeach()

    list(REMOVE_DUPLICATES modelsim_sources)

    set(modelsim_depends "")
    set(modelsim_libraries "")

    foreach (name ${ARG_DEPENDS})
        cmake_parse_arguments(DEP "" "${_HDL_ONE_VALUE_ARGUMENTS}"
            "${_HDL_MULTI_VALUE_ARGUMENTS}" ${_HDL_${name}})

        if (DEFINED DEP_COMPILE_EXCLUDE)
            if (DEP_COMPILE_EXCLUDE MATCHES ModelSim)
                continue()
            endif()
        endif()

        if (DEFINED DEP_COMPILE)
            if (NOT DEP_COMPILE MATCHES ALL AND
                    NOT DEP_COMPILE MATCHES ModelSim)
                continue()
            endif()
        endif()

        list(APPEND modelsim_libraries ${DEP_LIBRARY})
        list(APPEND modelsim_depends
            modelsim-compile-${DEP_LIBRARY}-${DEP_NAME})
    endforeach()

    list(REMOVE_DUPLICATES modelsim_depends)
    list(REMOVE_DUPLICATES modelsim_libraries)

    foreach (modelsim_library ${modelsim_libraries})
        set(modelsim_flags ${modelsim_flags} -L ${modelsim_library})
    endforeach()

    set(hdl_module_file ${modelsim_modules_dir}/${ARG_LIBRARY}/${ARG_NAME})

    add_custom_command(
        OUTPUT
            ${hdl_module_file}
        COMMAND
            ${modelsim_compiler} ${modelsim_flags} ${modelsim_sources}
        COMMAND
            ${CMAKE_COMMAND} -E touch ${hdl_module_file}
        DEPENDS
            ${ARG_SOURCE}
            ${ARG_SOURCES}
            ${ARG_INCLUDES}
            ${modelsim_depends}
        WORKING_DIRECTORY
            ${CMAKE_BINARY_DIR}/modelsim
        COMMENT
            "ModelSim compiling HDL ${ARG_NAME} to ${ARG_LIBRARY} library"
    )

    add_custom_target(modelsim-compile-${ARG_LIBRARY}-${ARG_NAME}
        DEPENDS ${hdl_module_file}
    )

    if (NOT TARGET modelsim-compile-${ARG_LIBRARY})
        add_custom_target(modelsim-compile-${ARG_LIBRARY})

        add_dependencies(modelsim-compile-all modelsim-compile-${ARG_LIBRARY})
    else()
        get_target_property(prev_target modelsim-compile-${ARG_LIBRARY}
            HDL_PREV_TARGET)

        add_dependencies(modelsim-compile-${ARG_LIBRARY}-${ARG_NAME}
            ${prev_target})
    endif()

    add_dependencies(modelsim-compile-${ARG_LIBRARY}
        modelsim-compile-${ARG_LIBRARY}-${ARG_NAME})

    set_target_properties(modelsim-compile-${ARG_LIBRARY} PROPERTIES
        HDL_PREV_TARGET modelsim-compile-${ARG_LIBRARY}-${ARG_NAME})
endfunction()

function(add_hdl_verilator hdl_name)
    if (NOT VERILATOR_FOUND)
        return()
    endif()

    cmake_parse_arguments(ARG "" "${_HDL_ONE_VALUE_ARGUMENTS}"
        "${_HDL_MULTI_VALUE_ARGUMENTS}" ${_HDL_${hdl_name}} ${ARGN})

    if (NOT DEFINED ARG_SYNTHESIZABLE OR NOT ARG_SYNTHESIZABLE)
        return()
    endif()

    if (DEFINED ARG_ANALYSIS)
        if (ARG_ANALYSIS MATCHES ALL OR ARG_ANALYSIS MATCHES Verilator)
            set(verilator_analysis TRUE)
        else()
            set(verilator_analysis FALSE)
        endif()
    endif()

    if (DEFINED ARG_ANALYSIS_EXCLUDE MATCHES Verilator)
        if (ARG_ANALYSIS_EXCLUDE MATCHES Verilator)
            set(verilator_analysis FALSE)
        endif()
    endif()

    if (DEFINED ARG_COMPILE)
        if (ARG_COMPILE MATCHES ALL OR ARG_COMPILE MATCHES Verilator)
            set(verilator_compile TRUE)
        else()
            set(verilator_compile FALSE)
        endif()
    endif()

    if (DEFINED ARG_COMPILE_EXCLUDE MATCHES Verilator)
        if (ARG_COMPILE_EXCLUDE MATCHES Verilator)
            set(verilator_compile FALSE)
        endif()
    endif()

    if (NOT verilator_analysis AND NOT verilator_compile)
        return()
    endif()

    if (NOT DEFINED ARG_TARGET)
        set(ARG_TARGET ${ARG_NAME})
    endif()

    set(verilator_sources "")
    set(verilator_defines "")
    set(verilator_includes "")
    set(verilator_parameters "")
    set(verilator_configurations "")

    list(APPEND verilator_defines ${ARG_DEFINES})
    list(APPEND verilator_parameters ${ARG_PARAMETERS})

    get_hdl_depends(${ARG_NAME} hdl_depends)

    foreach (name ${hdl_depends} ${ARG_NAME})
        cmake_parse_arguments(TMP "" "${_HDL_ONE_VALUE_ARGUMENTS}"
            "${_HDL_MULTI_VALUE_ARGUMENTS}" ${_HDL_${name}})

        list(APPEND verilator_sources ${TMP_SOURCES})
        list(APPEND verilator_sources ${TMP_SOURCE})
        list(APPEND verilator_defines ${TMP_DEFINES})
        list(APPEND verilator_includes ${TMP_INCLUDES})
        list(APPEND verilator_configurations ${TMP_VERILATOR_CONFIGURATIONS})
    endforeach()

    list(REMOVE_DUPLICATES verilator_defines)
    list(REMOVE_DUPLICATES verilator_includes)
    list(REMOVE_DUPLICATES verilator_parameters)
    list(REMOVE_DUPLICATES verilator_configurations)

    set(verilator_configuration_file
        ${CMAKE_BINARY_DIR}/verilator/.configs/${ARG_TARGET}.vlt)

    set(verilator_config "")
    foreach (config ${verilator_configurations})
        set(verilator_config "${verilator_config}${config}\n")
    endforeach()

    configure_file(${VERILATOR_CONFIGURATION_FILE}
        ${verilator_configuration_file})

    set(verilator_flags "")

    list(APPEND verilator_flags --top-module ${ARG_NAME})

    foreach (verilator_parameter ${verilator_parameters})
        list(APPEND verilator_parameters -G${verilator_parameter})
    endforeach()

    foreach (verilator_define ${verilator_defines})
        list(APPEND verilator_flags -D${verilator_define})
    endforeach()

    foreach (verilator_include ${verilator_includes})
        list(APPEND verilator_flags -I${verilator_include})
    endforeach()

    list(APPEND verilator_flags ${verilator_configuration_file})
    list(APPEND verilator_flags ${verilator_sources})

    set(verilator_target ${ARG_TARGET})

    if (ARG_PREFIX)
        set(verilator_target ${ARG_PREFIX})
    endif()

    if (verilator_analysis AND
            NOT TARGET verilator-analysis-${verilator_target})
        set(analysis_flags "")
        list(APPEND analysis_flags -Wall)
        list(APPEND analysis_flags --lint-only)

        add_custom_target(verilator-analysis-${verilator_target}
                ${VERILATOR_EXECUTABLE}
                ${analysis_flags}
                ${verilator_flags}
            DEPENDS
                ${verilator_sources}
                ${verilator_includes}
                ${verilator_configuration_file}
        )

        add_dependencies(verilator-analysis-all
            verilator-analysis-${verilator_target})

        if (TARGET ${ARG_TARGET})
            add_dependencies(${ARG_TARGET}
                verilator-analysis-${verilator_target})
        endif()
    endif()

    if (verilator_compile AND NOT TARGET verilator-compile-${verilator_target})
        set(compile_flags "")

        list(APPEND compile_flags --sc)
        list(APPEND compile_flags -O2)
        list(APPEND compile_flags -Wall)
        list(APPEND compile_flags --trace)
        list(APPEND compile_flags --coverage)
        list(APPEND compile_flags --prefix ${verilator_target})
        list(APPEND compile_flags -Mdir .)

        if (CMAKE_CXX_COMPILER_ID MATCHES GNU OR
                CMAKE_CXX_COMPILER_ID MATCHES Clang)
            set(flags
                -std=c++11
                -O2
                -fdata-sections
                -ffunction-sections
            )

            list(APPEND compile_flags -CFLAGS '${flags}')
        endif()

        set(verilator_output_directory
            ${CMAKE_BINARY_DIR}/verilator/${verilator_target})

        file(MAKE_DIRECTORY ${verilator_output_directory})

        set(verilator_library ${verilator_target}__ALL.a)

        add_custom_command(
            OUTPUT
                ${verilator_output_directory}/${verilator_library}
            COMMAND
                ${VERILATOR_EXECUTABLE}
            ARGS
                ${compile_flags}
                ${verilator_flags}
            COMMAND
                $(MAKE)
            ARGS
                -f ${verilator_target}.mk
            DEPENDS
                ${verilator_depends}
                ${verilator_sources}
                ${verilator_includes}
                ${verilaotr_configuration_file}
            WORKING_DIRECTORY
                ${verilator_output_directory}
            COMMENT
                "Creating SystemC ${verilator_target} module"
        )

        add_custom_target(verilator-compile-${verilator_target}
            DEPENDS ${verilator_output_directory}/${verilator_library})

        add_dependencies(verilator-compile-all
            verilator-compile-${verilator_target})

        if (TARGET ${ARG_TARGET})
            add_dependencies(${ARG_TARGET}
                verilator-compile-${verilator_target})
        endif()

        add_library(verilated_${verilator_target} STATIC IMPORTED)

        add_dependencies(verilated_${verilator_target}
            verilator-compile-${verilator_target})

        set_target_properties(verilated_${verilator_target} PROPERTIES
            IMPORTED_LOCATION
                ${verilator_output_directory}/${verilator_library}
        )

        set(module_libraries
            verilated_${verilator_target}
            verilated
            ${SYSTEMC_LIBRARIES}
        )

        set(module_include_directories
            ${VERILATOR_INCLUDE_DIR}
            ${SYSTEMC_INCLUDE_DIRS}
            ${verilator_output_directory}
        )

        if (NOT TARGET ${verilator_target})
            add_custom_target(${verilator_target})
        endif()

        set_target_properties(${verilator_target} PROPERTIES
            LIBRARIES "${module_libraries}"
            INCLUDE_DIRECTORIES "${module_include_directories}"
        )
    endif()
endfunction()

function(add_hdl_source)
    cmake_parse_arguments(ARG "" "${_HDL_ONE_VALUE_ARGUMENTS}"
        "${_HDL_MULTI_VALUE_ARGUMENTS}" ${ARGN})

    macro(set_default_value name value)
        if (NOT DEFINED ARG_${name})
            set(ARG_${name} ${value})
        endif()
    endmacro()

    if (NOT DEFINED ARG_SOURCES)
        set(ARG_SOURCES "")
    endif()

    foreach (hdl_file ${ARG_UNPARSED_ARGUMENTS})
        if (NOT ARG_SOURCE)
            set(ARG_SOURCE ${hdl_file})
        else()
            list(APPEND ARG_SOURCES ${hdl_file})
        endif()
    endforeach()

    if (NOT ARG_SOURCE)
        message(FATAL_ERROR "HDL file not provided as first argument")
    endif()

    get_filename_component(ARG_SOURCE "${ARG_SOURCE}" REALPATH)

    if (NOT EXISTS "${ARG_SOURCE}")
        message(FATAL_ERROR "HDL file doesn't exist: ${ARG_SOURCE}")
    endif()

    get_filename_component(hdl_name "${ARG_SOURCE}" NAME_WE)

    set_default_value(NAME ${hdl_name})
    set_default_value(DEPENDS "")
    set_default_value(DEFINES "")
    set_default_value(INCLUDES "")
    set_default_value(LIBRARY work)
    set_default_value(COMPILE ModelSim Quartus)
    set_default_value(ANALYSIS FALSE)
    set_default_value(SYNTHESIZABLE FALSE)
    set_default_value(MODELSIM_LINT TRUE)
    set_default_value(MODELSIM_PEDANTICERRORS TRUE)
    set_default_value(VERILATOR_CONFIGURATIONS "")

    if (HDL_LIBRARY)
        set(ARG_LIBRARY ${HDL_LIBRARY})
    endif()

    if (DEFINED HDL_SYNTHESIZABLE)
        set(ARG_SYNTHESIZABLE ${HDL_SYNTHESIZABLE})
    endif()

    set(ARG_DEPENDS ${HDL_DEPENDS} ${ARG_DEPENDS})
    set(ARG_DEFINES ${HDL_DEFINES} ${ARG_DEFINES})
    set(ARG_INCLUDES ${HDL_INCLUDES} ${ARG_INCLUDES})

    if (ARG_DEPENDS)
        list(REMOVE_DUPLICATES ARG_DEPENDS)
    endif()

    if (ARG_DEFINES)
        list(REMOVE_DUPLICATES ARG_DEFINES)
    endif()

    if (ARG_INCLUDES)
        list(REMOVE_DUPLICATES ARG_INCLUDES)
    endif()

    set(arg_includes "")

    foreach (arg_include ${ARG_INCLUDES})
        get_filename_component(arg_include "${arg_include}" REALPATH)
        list(APPEND arg_includes ${arg_include})
    endforeach()

    set(ARG_INCLUDES ${arg_includes})

    set(arg_sources "")

    foreach (arg_source ${ARG_SOURCES})
        get_filename_component(arg_source "${arg_source}" REALPATH)
        list(APPEND arg_sources ${arg_source})
    endforeach()

    set(ARG_SOURCES ${arg_sources})

    if (NOT ARG_TYPE)
        if (ARG_SOURCE MATCHES .sv)
            set(ARG_TYPE SystemVerilog)
        elseif (ARG_SOURCE MATCHES .vhd)
            set(ARG_TYPE VHDL)
        elseif (ARG_SOURCE MATCHES .v)
            set(ARG_TYPE Verilog)
        elseif (ARG_SOURCE MATCHES .qsys)
            set(ARG_TYPE Qsys)
        elseif (ARG_SOURCE MATCHES .ip)
            set(ARG_TYPE IP)
        elseif (ARG_SOURCE MATCHES .tcl)
            set(ARG_TYPE Tcl)
        else()
            message(FATAL_ERROR "HDL type is unknown for file ${ARG_SOURCE}")
        endif()
    endif()

    if (NOT DEFINED _HDL_${ARG_NAME})
        set(hdl_list ${_HDL_LIST})
        list(APPEND hdl_list ${ARG_NAME})
        set(_HDL_LIST "${hdl_list}" CACHE INTERNAL "" FORCE)
    endif()

    set(hdl_entry "")

    foreach (argument ${_HDL_ONE_VALUE_ARGUMENTS})
        list(APPEND hdl_entry ${argument} ${ARG_${argument}})
    endforeach()

    foreach (argument ${_HDL_MULTI_VALUE_ARGUMENTS})
        list(APPEND hdl_entry ${argument} ${ARG_${argument}})
    endforeach()

    set(_HDL_${ARG_NAME} "${hdl_entry}" CACHE INTERNAL "" FORCE)

    add_hdl_modelsim(${ARG_NAME})
    add_hdl_verilator(${ARG_NAME})
    #add_hdl_quartus(${hdl_target})
    #add_hdl_vivado(${hdl_target})
endfunction()

function(add_hdl_systemc target_name)
    add_hdl_verilator(${target_name}
        COMPILE Verilator
        ANALYSIS Verilator
        SYNTHESIZABLE TRUE
        ${ARGN}
    )
endfunction()

function(add_hdl_test test_name)
    if (MODELSIM_FOUND)
        set(modelsim_waveform ${CMAKE_BINARY_DIR}/output/${test_name}.wlf)

        if (CYGWIN)
            execute_process(COMMAND cygpath -m ${MODELSIM_RUN_TCL}
                OUTPUT_VARIABLE MODELSIM_RUN_TCL
                OUTPUT_STRIP_TRAILING_WHITESPACE)

            execute_process(COMMAND cygpath -m ${modelsim_waveform}
                OUTPUT_VARIABLE modelsim_waveform
                OUTPUT_STRIP_TRAILING_WHITESPACE)
        endif()

        set(hdl_depends "")
        set(hdl_libraries "")
        set(modelsim_flags "")

        list(APPEND modelsim_flags -c)
        list(APPEND modelsim_flags -wlf ${modelsim_waveform})
        list(APPEND modelsim_flags -do ${MODELSIM_RUN_TCL})

        get_hdl_depends(${test_name} hdl_depends)

        foreach (hdl_name ${hdl_depends} ${test_name})
            cmake_parse_arguments(TMP "" "${_HDL_ONE_VALUE_ARGUMENTS}"
                "${_HDL_MULTI_VALUE_ARGUMENTS}" ${_HDL_${hdl_name}})
            list(APPEND hdl_libraries ${TMP_LIBRARY})
        endforeach()

        list(REMOVE_DUPLICATES hdl_libraries)

        foreach (hdl_library ${hdl_libraries})
            list(APPEND modelsim_flags -L ${hdl_library})
        endforeach()

        add_test(NAME ${test_name}
            COMMAND ${MODELSIM_VSIM} ${modelsim_flags} ${test_name}
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim
        )
    endif()
endfunction()
