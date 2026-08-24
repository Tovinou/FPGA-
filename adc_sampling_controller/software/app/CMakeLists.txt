cmake_minimum_required(VERSION 3.14)

add_subdirectory(../hal_bsp hal_bsp)

include(../hal_bsp/toolchain.cmake)

project(app)

enable_language(ASM)
enable_language(C)
enable_language(CXX)

add_executable(app.elf)

target_sources(app.elf
    PRIVATE
        test.c
)

target_include_directories(app.elf
    PRIVATE
    PUBLIC
)

target_link_libraries(app.elf
    PRIVATE
        -T "${BspLinkerScript}" -nostdlib
        "${ExtraArchiveLibraries}"
        -Wl,--start-group "${BspLibraryName}" -lc -lstdc++ -lgcc -lm -Wl,--end-group
)

# Create objdump from ELF.
set(objdump app.elf.objdump)
add_custom_command(
    OUTPUT "${objdump}"
    DEPENDS app.elf
    COMMAND "${ToolchainObjdump}" "${ToolchainObjdumpFlags}" app.elf >
            "${objdump}"
    COMMENT "Creating ${objdump}."
    VERBATIM
)
add_custom_target(create-objdump ALL DEPENDS "${objdump}")

# Report space free for stack + heap. Note that the file below is never created
# so the report is always output on build.
find_program(NIOSV_STACK_REPORT_EXE niosv-stack-report)
if (NIOSV_STACK_REPORT_EXE)
    set(stack_report_file app.elf.stack_report)
    add_custom_command(
        OUTPUT "${stack_report_file}"
        DEPENDS app.elf
        COMMAND "${NIOSV_STACK_REPORT_EXE}" -p "${ToolchainPrefix}" app.elf
        COMMENT "Reporting memory available for stack + heap in app.elf."
        VERBATIM
    )
    add_custom_target(niosv-stack-report ALL DEPENDS "${stack_report_file}")
endif()

# Generate HEX file(s) from app.elf using elf2hex tool.
# Note : If ECC Full is enabled, width of 39 is set for NiosV TCM. Otherwise, 32.
find_program(ELF2HEX_EXE elf2hex)
if (ELF2HEX_EXE)
    add_custom_command(
        OUTPUT "onchip_memory2_0.hex"
        DEPENDS app.elf
        COMMAND "${ELF2HEX_EXE}" app.elf -o onchip_memory2_0.hex -b 0x00000000 -w 32 -e 0x0001DFFF -r 4
        COMMENT "Creating onchip_memory2_0.hex."
        VERBATIM
    )
    add_custom_target(create-hex ALL DEPENDS "onchip_memory2_0.hex")
endif()
