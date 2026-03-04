// =============================================================================
// DE10-Lite Golden Top for Ping Pong Game
// FIXED: Instantiates ping_pong_game_top and maps all board signals
//        GPIO[0] is used as speaker output (connect to buzzer/speaker circuit)
// =============================================================================

module DE10_LITE_Golden_Top(

    ////////// CLOCK //////////
    input           MAX10_CLK1_50,

    ////////// HEX Displays //////////
    output  [7:0]   HEX0,
    output  [7:0]   HEX1,
    output  [7:0]   HEX2,
    output  [7:0]   HEX3,
    output  [7:0]   HEX4,
    output  [7:0]   HEX5,

    ////////// LEDs //////////
    output  [9:0]   LEDR,

    ////////// Switches //////////
    input   [9:0]   SW,

    ////////// VGA //////////
    output  [3:0]   VGA_B,
    output  [3:0]   VGA_G,
    output          VGA_HS,
    output  [3:0]   VGA_R,
    output          VGA_VS,

    ////////// GPIO //////////
    inout   [35:0]  GPIO
);

// Drive unused GPIO pins to high-Z except GPIO[0] which is used as speaker
// The ping_pong_game_top entity drives GPIO[0]; the rest are left open.
// (GPIO[1..35] are not driven by the game; set them tristate via the entity.)

ping_pong_game_top game_inst (
    .SW             (SW),
    .MAX10_CLK1_50  (MAX10_CLK1_50),
    .LEDR           (LEDR),
    .HEX0           (HEX0),
    .HEX1           (HEX1),
    .HEX2           (HEX2),
    .HEX3           (HEX3),
    .HEX4           (HEX4),
    .HEX5           (HEX5),
    .GPIO           (GPIO),
    .VGA_HS         (VGA_HS),
    .VGA_VS         (VGA_VS),
    .VGA_R          (VGA_R),
    .VGA_G          (VGA_G),
    .VGA_B          (VGA_B)
);

endmodule
