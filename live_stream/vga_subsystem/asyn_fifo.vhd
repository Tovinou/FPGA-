-- =============================================================================
-- asyn_fifo.vhd  (VHDL-93 compatible, with rd_usedw port)
-- Dual-clock async FIFO
--   USE_DCFIFO=true  => Altera dcfifo megafunction (lpm_showahead=OFF)
--   USE_DCFIFO=false => Portable RTL grey-code CDC FIFO
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity asyn_fifo is
    generic (
        DATA_WIDTH  : integer := 16;
        DEPTH_LOG2  : integer := 9;
        USE_DCFIFO  : boolean := false
    );
    port (
        wr_clk   : in  std_logic;
        wr_rst_n : in  std_logic;
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wr_full  : out std_logic;

        rd_clk   : in  std_logic;
        rd_rst_n : in  std_logic;
        rd_en    : in  std_logic;
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_empty : out std_logic;
        rd_usedw : out std_logic_vector(DEPTH_LOG2-1 downto 0);

        -- Write-domain fill level, for producer-side almost-full throttling.
        -- Unlike rd_usedw, this does NOT suffer the "wraps to 0 when full"
        -- artifact, because on the write side "full" and "usedw = DEPTH"
        -- are the same event (full_int covers it) rather than a modulo wrap.
        wr_usedw : out std_logic_vector(DEPTH_LOG2-1 downto 0)
    );
end entity asyn_fifo;

architecture rtl of asyn_fifo is

    constant DEPTH : integer := 2**DEPTH_LOG2;

    component dcfifo
        generic (
            intended_device_family : string;
            lpm_width              : natural;
            lpm_numwords           : natural;
            lpm_widthu             : natural;
            lpm_showahead          : string;
            overflow_checking      : string;
            underflow_checking     : string;
            use_eab                : string;
            wrsync_delaypipe       : natural;
            rdsync_delaypipe       : natural
        );
        port (
            aclr    : in  std_logic;
            data    : in  std_logic_vector(lpm_width-1 downto 0);
            rdclk   : in  std_logic;
            rdreq   : in  std_logic;
            wrclk   : in  std_logic;
            wrreq   : in  std_logic;
            q       : out std_logic_vector(lpm_width-1 downto 0);
            rdempty : out std_logic;
            wrfull  : out std_logic;
            rdusedw : out std_logic_vector(lpm_widthu-1 downto 0);
            wrusedw : out std_logic_vector(lpm_widthu-1 downto 0)
        );
    end component;

    type ram_type is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ram : ram_type;
    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M9K, no_rw_check";

    signal wr_ptr_bin  : unsigned(DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_ptr_bin  : unsigned(DEPTH_LOG2 downto 0) := (others => '0');

    signal wr_ptr_gray : std_logic_vector(DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_ptr_gray : std_logic_vector(DEPTH_LOG2 downto 0) := (others => '0');

    signal rd_gray_sync1 : std_logic_vector(DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_gray_sync2 : std_logic_vector(DEPTH_LOG2 downto 0) := (others => '0');

    signal wr_gray_sync1 : std_logic_vector(DEPTH_LOG2 downto 0) := (others => '0');
    signal wr_gray_sync2 : std_logic_vector(DEPTH_LOG2 downto 0) := (others => '0');

    signal full_int  : std_logic := '0';
    signal empty_int : std_logic := '1';

    signal wr_ptr_synced_bin : unsigned(DEPTH_LOG2 downto 0) := (others => '0');
    signal diff              : unsigned(DEPTH_LOG2 downto 0) := (others => '0');
    signal wr_diff           : unsigned(DEPTH_LOG2 downto 0) := (others => '0');

    signal aclr_int : std_logic;

    -- Binary-to-Gray conversion
    function bin2gray(b : unsigned) return std_logic_vector is
        variable g : std_logic_vector(b'length-1 downto 0);
    begin
        g(b'length-1) := b(b'length-1);
        for i in b'length-2 downto 0 loop
            g(i) := b(i+1) xor b(i);
        end loop;
        return g;
    end function;

    function gray2bin(g : std_logic_vector) return unsigned is
        variable b : unsigned(g'length-1 downto 0);
    begin
        b(g'length-1) := g(g'length-1);
        for i in g'length-2 downto 0 loop
            b(i) := b(i+1) xor g(i);
        end loop;
        return b;
    end function;

begin

    gen_vendor : if USE_DCFIFO generate
    begin
        aclr_int <= not (wr_rst_n and rd_rst_n);

        u_fifo : dcfifo
            generic map (
                intended_device_family => "MAX 10",
                lpm_width              => DATA_WIDTH,
                lpm_numwords           => DEPTH,
                lpm_widthu             => DEPTH_LOG2,
                lpm_showahead          => "OFF",
                overflow_checking      => "ON",
                underflow_checking     => "ON",
                use_eab                => "ON",
                wrsync_delaypipe       => 4,
                rdsync_delaypipe       => 4
            )
            port map (
                aclr    => aclr_int,
                data    => wr_data,
                rdclk   => rd_clk,
                rdreq   => rd_en,
                wrclk   => wr_clk,
                wrreq   => wr_en,
                q       => rd_data,
                rdempty => rd_empty,
                wrfull  => wr_full,
                rdusedw => rd_usedw,
                wrusedw => wr_usedw
            );
    end generate gen_vendor;

    gen_rtl : if not USE_DCFIFO generate
    begin
        wr_ptr_gray <= bin2gray(wr_ptr_bin);
        rd_ptr_gray <= bin2gray(rd_ptr_bin);

        p_write : process(wr_clk, wr_rst_n)
        begin
            if wr_rst_n = '0' then
                wr_ptr_bin    <= (others => '0');
                rd_gray_sync1 <= (others => '0');
                rd_gray_sync2 <= (others => '0');
            elsif rising_edge(wr_clk) then
                rd_gray_sync1 <= rd_ptr_gray;
                rd_gray_sync2 <= rd_gray_sync1;
                if wr_en = '1' and full_int = '0' then
                    ram(to_integer(wr_ptr_bin(DEPTH_LOG2-1 downto 0))) <= wr_data;
                    wr_ptr_bin <= wr_ptr_bin + 1;
                end if;
            end if;
        end process;

        full_int <= '1' when
            (wr_ptr_gray(DEPTH_LOG2)   /= rd_gray_sync2(DEPTH_LOG2)   and
             wr_ptr_gray(DEPTH_LOG2-1) /= rd_gray_sync2(DEPTH_LOG2-1) and
             wr_ptr_gray(DEPTH_LOG2-2 downto 0) = rd_gray_sync2(DEPTH_LOG2-2 downto 0))
            else '0';

        wr_full <= full_int;

        -- Write-domain fill level: wr_ptr - (synchronized) rd_ptr.
        -- No modulo-wrap artifact here since this is a plain subtraction,
        -- not a width-truncated counter that rolls over at DEPTH.
        wr_diff  <= wr_ptr_bin - gray2bin(rd_gray_sync2);
        wr_usedw <= std_logic_vector(wr_diff(DEPTH_LOG2-1 downto 0));

        p_read : process(rd_clk, rd_rst_n)
        begin
            if rd_rst_n = '0' then
                rd_ptr_bin    <= (others => '0');
                wr_gray_sync1 <= (others => '0');
                wr_gray_sync2 <= (others => '0');
                rd_data       <= (others => '0');
            elsif rising_edge(rd_clk) then
                wr_gray_sync1 <= wr_ptr_gray;
                wr_gray_sync2 <= wr_gray_sync1;
                if rd_en = '1' and empty_int = '0' then
                    rd_data <= ram(to_integer(rd_ptr_bin(DEPTH_LOG2-1 downto 0)));
                    rd_ptr_bin <= rd_ptr_bin + 1;
                end if;
            end if;
        end process;

        empty_int <= '1' when rd_ptr_gray = wr_gray_sync2 else '0';
        rd_empty  <= empty_int;

        wr_ptr_synced_bin <= gray2bin(wr_gray_sync2);
        diff              <= wr_ptr_synced_bin - rd_ptr_bin;
        rd_usedw          <= std_logic_vector(diff(DEPTH_LOG2-1 downto 0));
    end generate gen_rtl;

end architecture rtl;