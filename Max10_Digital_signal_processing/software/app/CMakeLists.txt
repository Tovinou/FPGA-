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
        src/main.c
        src/test_common.c
        src/timer_hw_ip_test.c
        src/adc_test.c
        src/pio_led_test.c
        src/irq_test.c
)

target_include_directories(app.elf
    PRIVATE
        src
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
set(stack_report_file app.elf.stack_report)
add_custom_command(
    OUTPUT "${stack_report_file}"
    DEPENDS app.elf
    COMMAND niosv-stack-report -p "${ToolchainPrefix}" app.elf
    COMMENT "Reporting memory available for stack + heap in app.elf."
    VERBATIM
)
add_custom_target(niosv-stack-report ALL DEPENDS "${stack_report_file}")

# Generate HEX file(s) from app.elf using elf2hex tool.
# Note : If ECC Full is enabled, width of 39 is set for NiosV TCM. Otherwise, 32.
add_custom_command(
    OUTPUT "sram.hex"
    DEPENDS app.elf
    COMMAND elf2hex app.elf -o sram.hex -b 0x00010000 -w 32 -e 0x00019FFF -r 4
    COMMENT "Creating sram.hex."
    VERBATIM
)
add_custom_target(create-hex ALL DEPENDS "sram.hex")
