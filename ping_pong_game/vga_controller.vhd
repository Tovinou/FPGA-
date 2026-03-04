-- FIX: Added x_counter and y_counter as output ports so the vga_score_renderer
--      can know which pixel is being drawn.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_controller is
    port(
        clk_25    : in  std_logic;
        resetn    : in  std_logic;
        rgb_in    : in  std_logic_vector(2 downto 0);
        vga_r     : out std_logic_vector(3 downto 0);
        vga_g     : out std_logic_vector(3 downto 0);
        vga_b     : out std_logic_vector(3 downto 0);
        hsync     : out std_logic;
        vsync     : out std_logic;
        x_counter : out unsigned(9 downto 0);  -- FIX: expose pixel X
        y_counter : out unsigned(9 downto 0)   -- FIX: expose pixel Y
    );
end entity;

architecture rtl of vga_controller is
    constant H_PIXELS : integer := 640;
    constant H_FP     : integer := 16;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_TOTAL  : integer := H_PIXELS + H_FP + H_SYNC + H_BP;

    constant V_LINES  : integer := 480;
    constant V_FP     : integer := 10;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
    constant V_TOTAL  : integer := V_LINES + V_FP + V_SYNC + V_BP;

    signal h_cnt : integer range 0 to H_TOTAL-1 := 0;
    signal v_cnt : integer range 0 to V_TOTAL-1 := 0;
    signal active_video : std_logic;

    signal resetn_t1, resetn_t2 : std_logic;

begin

    -- Reset synchroniser
    process(clk_25, resetn)
    begin
        if resetn = '0' then
            resetn_t1 <= '0';
            resetn_t2 <= '0';
        elsif rising_edge(clk_25) then
            resetn_t1 <= '1';
            resetn_t2 <= resetn_t1;
        end if;
    end process;

    -- Horizontal and vertical counters
    process(clk_25, resetn)
    begin
        if resetn = '0' then
            h_cnt <= 0;
            v_cnt <= 0;
        elsif rising_edge(clk_25) then
            if h_cnt < H_TOTAL-1 then
                h_cnt <= h_cnt + 1;
            else
                h_cnt <= 0;
                if v_cnt < V_TOTAL-1 then
                    v_cnt <= v_cnt + 1;
                else
                    v_cnt <= 0;
                end if;
            end if;
        end if;
    end process;

    -- Sync signals
    hsync <= '0' when (h_cnt >= H_PIXELS + H_FP and h_cnt < H_PIXELS + H_FP + H_SYNC) else '1';
    vsync <= '0' when (v_cnt >= V_LINES + V_FP and v_cnt < V_LINES + V_FP + V_SYNC)   else '1';

    active_video <= '1' when (h_cnt < H_PIXELS and v_cnt < V_LINES) else '0';

    -- Expose pixel coordinates to renderer
    x_counter <= to_unsigned(h_cnt, 10);  -- FIX
    y_counter <= to_unsigned(v_cnt, 10);  -- FIX

    -- RGB output
    process(clk_25)
    begin
        if rising_edge(clk_25) then
            if active_video = '1' then
                vga_r <= (others => rgb_in(2));
                vga_g <= (others => rgb_in(1));
                vga_b <= (others => rgb_in(0));
            else
                vga_r <= (others => '0');
                vga_g <= (others => '0');
                vga_b <= (others => '0');
            end if;
        end if;
    end process;

end rtl;
