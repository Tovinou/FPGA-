-- =============================================================================
-- vga_core.vhd
-- Standard 640x480 @ 60Hz VGA timing generator
-- Pixel clock: 25.175MHz (use 25MHz from PLL - close enough for monitors)
-- Generates H/V sync and active-area flag
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_core is
    port (
        pclk     : in  std_logic;   -- 25.175 MHz pixel clock
        rst_n    : in  std_logic;

        hsync    : out std_logic;   -- Horizontal sync (active low)
        vsync    : out std_logic;   -- Vertical sync   (active low)
        active   : out std_logic;   -- High during visible pixel area

        h_count  : out std_logic_vector(9 downto 0);   -- 0..799
        v_count  : out std_logic_vector(9 downto 0)    -- 0..524
    );
end entity vga_core;

architecture rtl of vga_core is

    -- -------------------------------------------------------------------------
    -- 640x480 @ 60Hz timing (VESA standard, 25.175MHz pixel clock)
    -- -------------------------------------------------------------------------
    -- Horizontal
    constant H_ACTIVE   : integer := 640;
    constant H_FP       : integer := 16;    -- Front porch
    constant H_SYNC_W   : integer := 96;    -- Sync pulse width
    constant H_BP       : integer := 48;    -- Back porch
    constant H_TOTAL    : integer := 800;   -- 640+16+96+48

    -- Vertical
    constant V_ACTIVE   : integer := 480;
    constant V_FP       : integer := 10;
    constant V_SYNC_W   : integer := 2;
    constant V_BP       : integer := 33;
    constant V_TOTAL    : integer := 525;   -- 480+10+2+33

    -- Sync pulse start/end positions
    constant H_SYNC_START : integer := H_ACTIVE + H_FP;          -- 656
    constant H_SYNC_END   : integer := H_ACTIVE + H_FP + H_SYNC_W; -- 752
    constant V_SYNC_START : integer := V_ACTIVE + V_FP;          -- 490
    constant V_SYNC_END   : integer := V_ACTIVE + V_FP + V_SYNC_W; -- 492

    signal hc : unsigned(9 downto 0) := (others => '0');
    signal vc : unsigned(9 downto 0) := (others => '0');

begin

    h_count <= std_logic_vector(hc);
    v_count <= std_logic_vector(vc);

    p_timing : process(pclk, rst_n)
    begin
        if rst_n = '0' then
            hc <= (others => '0');
            vc <= (others => '0');

        elsif rising_edge(pclk) then
            -- Horizontal counter
            if hc = H_TOTAL - 1 then
                hc <= (others => '0');
                -- Vertical counter
                if vc = V_TOTAL - 1 then
                    vc <= (others => '0');
                else
                    vc <= vc + 1;
                end if;
            else
                hc <= hc + 1;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Sync signal generation (active low per VESA spec)
    -- -------------------------------------------------------------------------
    hsync  <= '1' when rst_n = '0' else
              '0' when (hc >= H_SYNC_START and hc < H_SYNC_END) else '1';
    vsync  <= '1' when rst_n = '0' else
              '0' when (vc >= V_SYNC_START and vc < V_SYNC_END) else '1';
    active <= '0' when rst_n = '0' else
              '1' when (hc < H_ACTIVE and vc < V_ACTIVE) else '0';

end architecture rtl;
