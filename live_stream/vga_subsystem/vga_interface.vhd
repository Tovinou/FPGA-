library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_interface is
    port (
        pclk         : in  std_logic;
        rst_n        : in  std_logic;
        test_mode    : in  std_logic_vector(1 downto 0);
        rd_gate      : in  std_logic;

        fifo_rd_en   : out std_logic;
        fifo_rd_data : in  std_logic_vector(15 downto 0);
        fifo_empty   : in  std_logic;

        active       : in  std_logic;
        h_count      : in  std_logic_vector(9 downto 0);
        v_count      : in  std_logic_vector(9 downto 0);
        hsync_in     : in  std_logic;
        vsync_in     : in  std_logic;

        vga_r        : out std_logic_vector(3 downto 0);
        vga_g        : out std_logic_vector(3 downto 0);
        vga_b        : out std_logic_vector(3 downto 0);
        vga_hs       : out std_logic;
        vga_vs       : out std_logic;
        out_pixels01_dbg  : out std_logic_vector(31 downto 0);
        out_pixels23_dbg  : out std_logic_vector(31 downto 0);
        out_pixels45_dbg  : out std_logic_vector(31 downto 0);
        out_pixels67_dbg  : out std_logic_vector(31 downto 0);
        read_pixels01_dbg : out std_logic_vector(31 downto 0);
        read_pixels23_dbg : out std_logic_vector(31 downto 0);
        read_pixels45_dbg : out std_logic_vector(31 downto 0);
        read_pixels67_dbg : out std_logic_vector(31 downto 0);
        read_line0_pair_dbg   : out std_logic_vector(31 downto 0);
        read_line60_pair_dbg  : out std_logic_vector(31 downto 0);
        read_line120_pair_dbg : out std_logic_vector(31 downto 0);
        read_line180_pair_dbg : out std_logic_vector(31 downto 0);
        underflow_count_dbg : out std_logic_vector(31 downto 0);
        out_line0_pair_dbg   : out std_logic_vector(31 downto 0);
        out_line60_pair_dbg  : out std_logic_vector(31 downto 0);
        out_line120_pair_dbg : out std_logic_vector(31 downto 0);
        out_line180_pair_dbg : out std_logic_vector(31 downto 0)
    );
end entity vga_interface;

architecture rtl of vga_interface is

    type line_buf_t is array (0 to 319) of std_logic_vector(15 downto 0);
    signal line_buf : line_buf_t;

    signal pixel    : std_logic_vector(15 downto 0) := (others => '0');
    signal src_x    : unsigned(8 downto 0);

    signal rd_en_int    : std_logic := '0';
    signal rd_en_q      : std_logic := '0';
    signal read_x_q     : unsigned(8 downto 0) := (others => '0');
    signal read_y_q     : unsigned(8 downto 0) := (others => '0');

    signal out_pixels01_int  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_pixels23_int  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_pixels45_int  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_pixels67_int  : std_logic_vector(31 downto 0) := (others => '0');
    signal read_pixels01_int : std_logic_vector(31 downto 0) := (others => '0');
    signal read_pixels23_int : std_logic_vector(31 downto 0) := (others => '0');
    signal read_pixels45_int : std_logic_vector(31 downto 0) := (others => '0');
    signal read_pixels67_int : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line0_work   : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line60_work  : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line120_work : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line180_work : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line0_out    : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line60_out   : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line120_out  : std_logic_vector(31 downto 0) := (others => '0');
    signal read_line180_out  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_ref_arm       : std_logic := '0';
    signal read_ref_arm      : std_logic := '0';
    signal vsync_d           : std_logic := '1';
    signal underflow_count   : unsigned(31 downto 0) := (others => '0');
    signal out_line0_work    : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line60_work   : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line120_work  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line180_work  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line0_out     : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line60_out    : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line120_out   : std_logic_vector(31 downto 0) := (others => '0');
    signal out_line180_out   : std_logic_vector(31 downto 0) := (others => '0');
	signal active_d : std_logic := '0';

begin
	
    src_x <= unsigned(h_count(9 downto 1));

    out_pixels01_dbg  <= out_pixels01_int;
    out_pixels23_dbg  <= out_pixels23_int;
    out_pixels45_dbg  <= out_pixels45_int;
    out_pixels67_dbg  <= out_pixels67_int;
    read_pixels01_dbg <= read_pixels01_int;
    read_pixels23_dbg <= read_pixels23_int;
    read_pixels45_dbg <= read_pixels45_int;
    read_pixels67_dbg <= read_pixels67_int;
    read_line0_pair_dbg   <= read_line0_out;
    read_line60_pair_dbg  <= read_line60_out;
    read_line120_pair_dbg <= read_line120_out;
    read_line180_pair_dbg <= read_line180_out;
    underflow_count_dbg <= std_logic_vector(underflow_count);
    out_line0_pair_dbg   <= out_line0_out;
    out_line60_pair_dbg  <= out_line60_out;
    out_line120_pair_dbg <= out_line120_out;
    out_line180_pair_dbg <= out_line180_out;

     -- Load 320 pixels on even VGA rows only (one camera row per pair of scan lines).
    --rd_en_int <= '1' when (test_mode(1) = '1' and active_d = '1' and v_count(0) = '0' and h_count(0) = '0') else
                -- '1' when (test_mode(0) = '0' and rd_gate = '1' and active_d = '1' and v_count(0) = '0' and h_count(0) = '0' and fifo_empty = '0') else
                 --'0';
    -- One source pixel supplies each 2x2 output block.  Requests outside this
    -- cadence discard FIFO data and desynchronise the entire displayed frame.
    rd_en_int <= '1' when (test_mode(0) = '0' and rd_gate = '1' and
                           active = '1' and
                           v_count(0) = '0' and
                           h_count(0) = '0' and fifo_empty = '0') else '0';

    fifo_rd_en <= rd_en_int;

    p_vga_sync : process(pclk, rst_n)
        variable pixel_next : std_logic_vector(15 downto 0);
        -- src_x reaches 399 in horizontal blanking.  It is used to index the
        -- 320-entry line buffer only while active video is asserted.
        variable disp_idx   : integer;
    begin
        if rst_n = '0' then
            pixel     <= (others => '0');
            rd_en_q   <= '0';
            read_x_q  <= (others => '0');
            read_y_q  <= (others => '0');
            vga_hs    <= '1';
            vga_vs    <= '1';
            out_pixels01_int <= (others => '0');
            out_pixels23_int <= (others => '0');
            out_pixels45_int <= (others => '0');
            out_pixels67_int <= (others => '0');
            read_pixels01_int <= (others => '0');
            read_pixels23_int <= (others => '0');
            read_pixels45_int <= (others => '0');
            read_pixels67_int <= (others => '0');
            read_line0_work   <= (others => '0');
            read_line60_work  <= (others => '0');
            read_line120_work <= (others => '0');
            read_line180_work <= (others => '0');
            read_line0_out    <= (others => '0');
            read_line60_out   <= (others => '0');
            read_line120_out  <= (others => '0');
            read_line180_out  <= (others => '0');
            out_ref_arm      <= '0';
            read_ref_arm     <= '0';
            vsync_d          <= '1';
            underflow_count  <= (others => '0');
            out_line0_work   <= (others => '0');
            out_line60_work  <= (others => '0');
            out_line120_work <= (others => '0');
            out_line180_work <= (others => '0');
            out_line0_out    <= (others => '0');
            out_line60_out   <= (others => '0');
            out_line120_out  <= (others => '0');
            out_line180_out  <= (others => '0');
        elsif rising_edge(pclk) then
            vga_hs <= hsync_in;
            vga_vs <= vsync_in;
            vsync_d <= vsync_in;
			active_d <= active;
            pixel_next := pixel;
            disp_idx := to_integer(src_x);

            rd_en_q <= rd_en_int;
            if rd_en_int = '1' then
                read_x_q <= src_x;
                read_y_q <= unsigned(v_count(9 downto 1));
            end if;

            if vsync_d = '1' and vsync_in = '0' then
                out_line0_out    <= out_line0_work;
                out_line60_out   <= out_line60_work;
                out_line120_out  <= out_line120_work;
                out_line180_out  <= out_line180_work;
                out_line0_work   <= (others => '0');
                out_line60_work  <= (others => '0');
                out_line120_work <= (others => '0');
                out_line180_work <= (others => '0');
                out_pixels01_int <= (others => '0');
                out_pixels23_int <= (others => '0');
                out_pixels45_int <= (others => '0');
                out_pixels67_int <= (others => '0');
                read_pixels01_int <= (others => '0');
                read_pixels23_int <= (others => '0');
                read_pixels45_int <= (others => '0');
                read_pixels67_int <= (others => '0');
                read_line0_out    <= read_line0_work;
                read_line60_out   <= read_line60_work;
                read_line120_out  <= read_line120_work;
                read_line180_out  <= read_line180_work;
                read_line0_work   <= (others => '0');
                read_line60_work  <= (others => '0');
                read_line120_work <= (others => '0');
                read_line180_work <= (others => '0');
                out_ref_arm      <= '1';
                read_ref_arm     <= '1';
                underflow_count  <= (others => '0');
            elsif test_mode(0) = '0' and rd_gate = '1' and active = '1' and
                  v_count(0) = '0' and h_count(0) = '0' and fifo_empty = '1' then
                underflow_count <= underflow_count + 1;
            end if;

            if active = '1' then
                if test_mode(0) = '1' then
                    pixel_next := (others => '0');
                elsif v_count(0) = '1' then
                    if h_count(0) = '1' then
                        pixel_next := line_buf(disp_idx);
                    end if;
                elsif rd_en_q = '1' then
                    pixel_next := fifo_rd_data;
                end if;
            else
                pixel_next := (others => '0');
            end if;

            if rd_en_q = '1' then
                line_buf(to_integer(read_x_q)) <= fifo_rd_data;

                if read_ref_arm = '1' and read_y_q = to_unsigned(0, 9) then
                    case to_integer(read_x_q) is
                        when 20  => read_pixels01_int(31 downto 16) <= fifo_rd_data;
                        when 60  => read_pixels01_int(15 downto 0)  <= fifo_rd_data;
                        when 100 => read_pixels23_int(31 downto 16) <= fifo_rd_data;
                        when 140 => read_pixels23_int(15 downto 0)  <= fifo_rd_data;
                        when 180 => read_pixels45_int(31 downto 16) <= fifo_rd_data;
                        when 220 => read_pixels45_int(15 downto 0)  <= fifo_rd_data;
                        when 260 => read_pixels67_int(31 downto 16) <= fifo_rd_data;
                        when 300 => read_pixels67_int(15 downto 0)  <= fifo_rd_data;
                        when others => null;
                    end case;

                    if read_x_q = to_unsigned(300, read_x_q'length) then
                        read_ref_arm <= '0';
                    end if;
                end if;

                if read_x_q = to_unsigned(20, read_x_q'length) then
                    if read_y_q = to_unsigned(0, 9) then
                        read_line0_work(31 downto 16) <= fifo_rd_data;
                    elsif read_y_q = to_unsigned(60, 9) then
                        read_line60_work(31 downto 16) <= fifo_rd_data;
                    elsif read_y_q = to_unsigned(120, 9) then
                        read_line120_work(31 downto 16) <= fifo_rd_data;
                    elsif read_y_q = to_unsigned(180, 9) then
                        read_line180_work(31 downto 16) <= fifo_rd_data;
                    end if;
                elsif read_x_q = to_unsigned(180, read_x_q'length) then
                    if read_y_q = to_unsigned(0, 9) then
                        read_line0_work(15 downto 0) <= fifo_rd_data;
                    elsif read_y_q = to_unsigned(60, 9) then
                        read_line60_work(15 downto 0) <= fifo_rd_data;
                    elsif read_y_q = to_unsigned(120, 9) then
                        read_line120_work(15 downto 0) <= fifo_rd_data;
                    elsif read_y_q = to_unsigned(180, 9) then
                        read_line180_work(15 downto 0) <= fifo_rd_data;
                    end if;
                end if;
            end if;

            if out_ref_arm = '1' and active = '1' and h_count(0) = '1' and
               v_count(0) = '0' and unsigned(v_count(9 downto 1)) = to_unsigned(0, 9) then
                case to_integer(unsigned(h_count(9 downto 1))) is
                    when 20  => out_pixels01_int(31 downto 16) <= pixel_next;
                    when 60  => out_pixels01_int(15 downto 0)  <= pixel_next;
                    when 100 => out_pixels23_int(31 downto 16) <= pixel_next;
                    when 140 => out_pixels23_int(15 downto 0)  <= pixel_next;
                    when 180 => out_pixels45_int(31 downto 16) <= pixel_next;
                    when 220 => out_pixels45_int(15 downto 0)  <= pixel_next;
                    when 260 => out_pixels67_int(31 downto 16) <= pixel_next;
                    when 300 => out_pixels67_int(15 downto 0)  <= pixel_next;
                    when others => null;
                end case;

                if unsigned(h_count(9 downto 1)) = to_unsigned(300, 9) then
                    out_ref_arm <= '0';
                end if;
            end if;

            if active = '1' and h_count(0) = '1' and v_count(0) = '0' then
                if unsigned(h_count(9 downto 1)) = to_unsigned(20, 9) then
                    if unsigned(v_count(9 downto 1)) = to_unsigned(0, 9) then
                        out_line0_work(31 downto 16) <= pixel_next;
                    elsif unsigned(v_count(9 downto 1)) = to_unsigned(60, 9) then
                        out_line60_work(31 downto 16) <= pixel_next;
                    elsif unsigned(v_count(9 downto 1)) = to_unsigned(120, 9) then
                        out_line120_work(31 downto 16) <= pixel_next;
                    elsif unsigned(v_count(9 downto 1)) = to_unsigned(180, 9) then
                        out_line180_work(31 downto 16) <= pixel_next;
                    end if;
                elsif unsigned(h_count(9 downto 1)) = to_unsigned(180, 9) then
                    if unsigned(v_count(9 downto 1)) = to_unsigned(0, 9) then
                        out_line0_work(15 downto 0) <= pixel_next;
                    elsif unsigned(v_count(9 downto 1)) = to_unsigned(60, 9) then
                        out_line60_work(15 downto 0) <= pixel_next;
                    elsif unsigned(v_count(9 downto 1)) = to_unsigned(120, 9) then
                        out_line120_work(15 downto 0) <= pixel_next;
                    elsif unsigned(v_count(9 downto 1)) = to_unsigned(180, 9) then
                        out_line180_work(15 downto 0) <= pixel_next;
                    end if;
                end if;
            end if;

            pixel <= pixel_next;
        end if;
    end process;

    -- RGB565: pixel[15:11]=R(5b), pixel[10:5]=G(6b), pixel[4:0]=B(5b)
    -- Displaying top 4 bits of each channel (12-bit VGA DAC)
    vga_r <= (h_count(5 downto 2)) when (test_mode(0) = '1' and active = '1') else
             pixel(15 downto 12)   when active = '1' else "0000";

    vga_g <= (v_count(5 downto 2)) when (test_mode(0) = '1' and active = '1') else
             pixel(10 downto 7)    when active = '1' else "0000";

    vga_b <= (h_count(7 downto 4)) when (test_mode(0) = '1' and active = '1') else
             pixel(4  downto 1)    when active = '1' else "0000";

end architecture rtl;
