-- =============================================================================
-- ssi_avalon_wrapper.vhd
-- Avalon Memory-Mapped Wrapper for the SSI Master
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ssi_avalon_wrapper is
    generic (
        CLK_FREQ_HZ : positive := 50_000_000;
        SSI_CLK_HZ  : positive := 500_000;
        DATA_BITS   : positive := 25
    );
    port (
        -- Avalon-MM Slave Interface
        csi_clk          : in  std_logic;
        csi_reset_n      : in  std_logic;
        avs_address      : in  std_logic_vector(0 downto 0);
        avs_read         : in  std_logic;
        avs_readdata     : out std_logic_vector(31 downto 0);
        avs_write        : in  std_logic;
        avs_writedata    : in  std_logic_vector(31 downto 0);

        -- Conduit Interface (Exported to top-level physical pins)
        coe_ssi_clk      : out std_logic;
        coe_ssi_data     : in  std_logic
    );
end entity ssi_avalon_wrapper;

architecture rtl of ssi_avalon_wrapper is

    -- Signals connecting to the inner ssi_master
    signal w_start    : std_logic;
    signal w_busy     : std_logic;
    signal w_valid    : std_logic;
    signal w_position : std_logic_vector(DATA_BITS - 1 downto 0);
    
    -- Registers for Avalon-MM interface
    signal r_start_pulse : std_logic;
    signal r_valid_latch : std_logic;
    signal r_position    : std_logic_vector(31 downto 0);

begin

    -- Instantiate the original SSI master core
    u_ssi_master : entity work.ssi_master
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            SSI_CLK_HZ  => SSI_CLK_HZ,
            DATA_BITS   => DATA_BITS
        )
        port map (
            clk      => csi_clk,
            rst_n    => csi_reset_n,
            start    => w_start,
            busy     => w_busy,
            valid    => w_valid,
            position => w_position,
            ssi_clk  => coe_ssi_clk,
            ssi_data => coe_ssi_data
        );

    -- Map start pulse to the core
    w_start <= r_start_pulse;
    
    -- Write process
    process(csi_clk, csi_reset_n)
    begin
        if csi_reset_n = '0' then
            r_start_pulse <= '0';
            r_valid_latch <= '0';
            r_position    <= (others => '0');
        elsif rising_edge(csi_clk) then
            -- Start pulse is strictly 1 cycle
            r_start_pulse <= '0';
            
            -- Capture valid data when the core asserts w_valid
            if w_valid = '1' then
                r_valid_latch <= '1';
                r_position(DATA_BITS - 1 downto 0) <= w_position;
                r_position(31 downto DATA_BITS)    <= (others => '0');
            end if;

            -- Handle Avalon-MM writes
            if avs_write = '1' then
                if avs_address = "0" then
                    -- If writing 1 to bit 0 of Address 0, trigger a start
                    if avs_writedata(0) = '1' then
                        r_start_pulse <= '1';
                        r_valid_latch <= '0'; -- Clear old data flag
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Read process (combinational)
    process(avs_address, w_busy, r_valid_latch, r_position)
    begin
        avs_readdata <= (others => '0');
        if avs_address = "0" then
            -- Register 0: Status
            -- Bit 1 = Valid Data Ready
            -- Bit 0 = SSI is Busy
            avs_readdata(1) <= r_valid_latch;
            avs_readdata(0) <= w_busy;
        else
            -- Register 1: RX Data (Position)
            avs_readdata <= r_position;
        end if;
    end process;

end architecture rtl;
