-- =============================================================================
-- camera_interface.vhd
-- OV7670 RGB565 capture (PCLK domain)
--
-- OV7670 default: VSYNC low during active frame, HREF high during valid pixels.
-- If LED7 blinks fast and the camera FIFO stays empty, toggle invert_sync
-- (stream_top SW(1)) — VSYNC/HREF may be inverted or swapped on the module.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity camera_interface is
    port (
        clk            : in  std_logic;
        pclk           : in  std_logic;
        rst_n          : in  std_logic;
        i2c_done       : in  std_logic;
        invert_sync    : in  std_logic;  -- '1' = invert VSYNC and HREF before use
        sample_falling : in  std_logic;  -- '1' = capture on falling edge of original PCLK
        reverse_bits   : in  std_logic;  -- '1' = reverse D[7:0] bit order for debug
        data_map_sel   : in  std_logic_vector(1 downto 0); -- extra D[7:0] remap modes
        swap_bytes     : in  std_logic;  -- '1' = swap RGB565 byte order for debug
        vsync          : in  std_logic;
        href           : in  std_logic;
        cam_data       : in  std_logic_vector(7 downto 0);
        fifo_wr_en     : out std_logic;
        fifo_wr_data   : out std_logic_vector(15 downto 0);
        fifo_full      : in  std_logic;
        frame_done     : out std_logic;
        pclk_heartbeat : out std_logic;
        last_line_count      : out std_logic_vector(9 downto 0);
        last_pixel_count_div : out std_logic_vector(8 downto 0);
        frame_valid_dbg      : out std_logic;
        raw_byte_dbg         : out std_logic_vector(7 downto 0);
        mapped_byte_dbg      : out std_logic_vector(7 downto 0);
        pixel_word_dbg       : out std_logic_vector(15 downto 0);
        ref_pixels01_dbg     : out std_logic_vector(31 downto 0);
        ref_pixels23_dbg     : out std_logic_vector(31 downto 0);
        ref_pixels45_dbg     : out std_logic_vector(31 downto 0);
        ref_pixels67_dbg     : out std_logic_vector(31 downto 0);
        line0_pair_dbg       : out std_logic_vector(31 downto 0);
        line60_pair_dbg      : out std_logic_vector(31 downto 0);
        line120_pair_dbg     : out std_logic_vector(31 downto 0);
        line180_pair_dbg     : out std_logic_vector(31 downto 0)
    );
end entity camera_interface;

architecture rtl of camera_interface is

    type state_t is (S_IDLE, S_WAIT_FRAME, S_CAPTURE, S_DONE_PULSE);
    signal state : state_t := S_IDLE;

    signal vsync_i  : std_logic;
    signal href_i   : std_logic;
    signal pclk_cap : std_logic;

    signal byte_sel       : std_logic := '0';
    signal d_latch        : std_logic_vector(7 downto 0) := (others => '0');

    signal vsync_clean    : std_logic;
    signal href_clean     : std_logic;
    signal vsync_d        : std_logic := '0';
    signal href_d         : std_logic := '0';

    signal i2c_done_ff1   : std_logic := '0';
    signal i2c_done_ff2   : std_logic := '0';

    signal pulse_cnt      : unsigned(15 downto 0) := (others => '0');
    signal hb_cnt         : unsigned(19 downto 0) := (others => '0');
    signal line_cnt       : unsigned(9 downto 0)  := (others => '0');
    signal pixel_cnt      : unsigned(17 downto 0) := (others => '0');
    signal last_line_cnt  : unsigned(9 downto 0)  := (others => '0');
    signal last_pixel_div : unsigned(8 downto 0)  := (others => '0');
    signal frame_valid_i  : std_logic := '0';
    signal cam_byte_pre   : std_logic_vector(7 downto 0);
    signal cam_byte       : std_logic_vector(7 downto 0);
    signal last_pixel_word: std_logic_vector(15 downto 0) := (others => '0');
    signal last_raw_first : std_logic_vector(7 downto 0) := (others => '0');
    signal last_raw_second: std_logic_vector(7 downto 0) := (others => '0');
    signal sample_armed   : std_logic := '0';
    signal line_pixel_idx : unsigned(8 downto 0) := (others => '0');
    signal ref_pixel0     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel1     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel2     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel3     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel4     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel5     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel6     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_pixel7     : std_logic_vector(15 downto 0) := (others => '0');
    signal line0_pair_work     : std_logic_vector(31 downto 0) := (others => '0');
    signal line60_pair_work    : std_logic_vector(31 downto 0) := (others => '0');
    signal line120_pair_work   : std_logic_vector(31 downto 0) := (others => '0');
    signal line180_pair_work   : std_logic_vector(31 downto 0) := (others => '0');
    signal line0_pair_out      : std_logic_vector(31 downto 0) := (others => '0');
    signal line60_pair_out     : std_logic_vector(31 downto 0) := (others => '0');
    signal line120_pair_out    : std_logic_vector(31 downto 0) := (others => '0');
    signal line180_pair_out    : std_logic_vector(31 downto 0) := (others => '0');

    -- Treat each substantial VSYNC-to-VSYNC window as a frame. This keeps the
    -- stream alive even if the camera module's VSYNC polarity/phase differs from
    -- the nominal OV7670 convention, while still ignoring tiny runt windows.
    constant END_MIN_LINES  : unsigned(9 downto 0)  := to_unsigned (1, 10); --(8, 10);
    constant END_MIN_PIXELS : unsigned(17 downto 0) := to_unsigned (1, 18); --(4096, 18);
    constant GOOD_MIN_LINES  : unsigned(9 downto 0)  := to_unsigned(200, 10);
    constant GOOD_MAX_LINES  : unsigned(9 downto 0)  := to_unsigned(260, 10);
    constant GOOD_MIN_PIXELS : unsigned(17 downto 0) := to_unsigned(70000, 18);
    constant GOOD_MAX_PIXELS : unsigned(17 downto 0) := to_unsigned(82000, 18);

begin

    vsync_i <= vsync xor invert_sync;
    href_i  <= href xor invert_sync;
    pclk_cap <= pclk when sample_falling = '0' else not pclk;
    -- Use VSYNC/HREF directly in the selected capture-edge domain so line/frame
    -- boundaries stay aligned with the byte sampled on that same PCLK edge.
    vsync_clean <= vsync_i;
    href_clean  <= href_i;
    cam_byte_pre <= cam_data;
    
    cam_byte <= cam_byte_pre;
    last_line_count      <= std_logic_vector(last_line_cnt);
    last_pixel_count_div <= std_logic_vector(last_pixel_div);
    frame_valid_dbg      <= frame_valid_i;
    raw_byte_dbg         <= last_raw_first;
    mapped_byte_dbg      <= last_raw_second;
    pixel_word_dbg       <= last_pixel_word;
    ref_pixels01_dbg     <= ref_pixel0 & ref_pixel1;
    ref_pixels23_dbg     <= ref_pixel2 & ref_pixel3;
    ref_pixels45_dbg     <= ref_pixel4 & ref_pixel5;
    ref_pixels67_dbg     <= ref_pixel6 & ref_pixel7;
    line0_pair_dbg       <= line0_pair_out;
    line60_pair_dbg      <= line60_pair_out;
    line120_pair_dbg     <= line120_pair_out;
    line180_pair_dbg     <= line180_pair_out;

    -- Capture directly in the camera PCLK domain. The frame geometry probe proved
    -- that sync parsing is correct; the remaining fault is likely pixel-value
    -- corruption from oversampling PCLK/data in another clock domain.
    p_capture : process(pclk_cap, rst_n)
        variable assembled_pixel : std_logic_vector(15 downto 0);
    begin
        if rst_n = '0' then
            state      <= S_IDLE;
            byte_sel   <= '0';
            fifo_wr_en <= '0';
            frame_done <= '0';
            vsync_d    <= '0';
            href_d     <= '0';
            pulse_cnt  <= (others => '0');
            hb_cnt     <= (others => '0');
            line_cnt   <= (others => '0');
            pixel_cnt  <= (others => '0');
            last_line_cnt <= (others => '0');
            last_pixel_div <= (others => '0');
            frame_valid_i <= '0';
            pclk_heartbeat <= '0';
            last_pixel_word <= (others => '0');
            last_raw_first <= (others => '0');
            last_raw_second <= (others => '0');
            sample_armed <= '0';
            line_pixel_idx <= (others => '0');
            ref_pixel0 <= (others => '0');
            ref_pixel1 <= (others => '0');
            ref_pixel2 <= (others => '0');
            ref_pixel3 <= (others => '0');
            ref_pixel4 <= (others => '0');
            ref_pixel5 <= (others => '0');
            ref_pixel6 <= (others => '0');
            ref_pixel7 <= (others => '0');
            line0_pair_work   <= (others => '0');
            line60_pair_work  <= (others => '0');
            line120_pair_work <= (others => '0');
            line180_pair_work <= (others => '0');
            line0_pair_out    <= (others => '0');
            line60_pair_out   <= (others => '0');
            line120_pair_out  <= (others => '0');
            line180_pair_out  <= (others => '0');
            i2c_done_ff1 <= '0';
            i2c_done_ff2 <= '0';
        elsif rising_edge(pclk_cap) then
            fifo_wr_en <= '0';
            frame_done <= '0';

            hb_cnt <= hb_cnt + 1;
            pclk_heartbeat <= std_logic(hb_cnt(19));

            i2c_done_ff1 <= i2c_done;
            i2c_done_ff2 <= i2c_done_ff1;

            vsync_d   <= vsync_clean;
            href_d    <= href_clean;

            case state is
                when S_IDLE =>
                    if i2c_done_ff2 = '1' then
                        state <= S_WAIT_FRAME;
                    end if;

                -- Some OV7670 boards/modules do not present VSYNC with the
                -- expected polarity. Start capture on either frame edge and
                -- accept the next substantial edge as the frame end.
                when S_WAIT_FRAME =>
                    if vsync_clean /= vsync_d then
                        state     <= S_CAPTURE;
                        byte_sel  <= '0';
                        line_cnt  <= (others => '0');
                        pixel_cnt <= (others => '0');
                        line_pixel_idx <= (others => '0');
                        sample_armed <= '1';
                        ref_pixel0 <= (others => '0');
                        ref_pixel1 <= (others => '0');
                        ref_pixel2 <= (others => '0');
                        ref_pixel3 <= (others => '0');
                        ref_pixel4 <= (others => '0');
                        ref_pixel5 <= (others => '0');
                        ref_pixel6 <= (others => '0');
                        ref_pixel7 <= (others => '0');
                        line0_pair_work   <= (others => '0');
                        line60_pair_work  <= (others => '0');
                        line120_pair_work <= (others => '0');
                        line180_pair_work <= (others => '0');
                    end if;

                when S_CAPTURE =>
                    -- Count active lines (HREF rising edges while in frame)
                    if href_clean = '1' and href_d = '0' then
                        line_cnt <= line_cnt + 1;
                        line_pixel_idx <= (others => '0');
                        byte_sel <= '0';
                    end if;

                    if href_clean = '1' then
                        if byte_sel = '0' then
                            d_latch  <= cam_byte;
                            if sample_armed = '1' then
                                last_raw_first <= cam_data;
                            end if;
                            byte_sel <= '1';
                        else
                            if fifo_full = '0' then
                                if sample_armed = '1' then
                                    last_raw_second <= cam_data;
                                end if;
                                if swap_bytes = '0' then
                                    assembled_pixel := d_latch & cam_byte;
                                    if sample_armed = '1' then
                                        last_pixel_word <= assembled_pixel;
                                    end if;
                                else
                                    assembled_pixel := cam_byte & d_latch;
                                    if sample_armed = '1' then
                                        last_pixel_word <= assembled_pixel;
                                    end if;
                                end if;
                                fifo_wr_data <= assembled_pixel;
                                if line_cnt = to_unsigned(1, 10) then
                                    case to_integer(line_pixel_idx) is
                                        when 20  => ref_pixel0 <= assembled_pixel;
                                        when 60  => ref_pixel1 <= assembled_pixel;
                                        when 100 => ref_pixel2 <= assembled_pixel;
                                        when 140 => ref_pixel3 <= assembled_pixel;
                                        when 180 => ref_pixel4 <= assembled_pixel;
                                        when 220 => ref_pixel5 <= assembled_pixel;
                                        when 260 => ref_pixel6 <= assembled_pixel;
                                        when 300 => ref_pixel7 <= assembled_pixel;
                                        when others => null;
                                    end case;
                                end if;
                                if line_pixel_idx = to_unsigned(20, line_pixel_idx'length) then
                                    if line_cnt = to_unsigned(1, 10) then
                                        line0_pair_work(31 downto 16) <= assembled_pixel;
                                    elsif line_cnt = to_unsigned(61, 10) then
                                        line60_pair_work(31 downto 16) <= assembled_pixel;
                                    elsif line_cnt = to_unsigned(121, 10) then
                                        line120_pair_work(31 downto 16) <= assembled_pixel;
                                    elsif line_cnt = to_unsigned(181, 10) then
                                        line180_pair_work(31 downto 16) <= assembled_pixel;
                                    end if;
                                elsif line_pixel_idx = to_unsigned(180, line_pixel_idx'length) then
                                    if line_cnt = to_unsigned(1, 10) then
                                        line0_pair_work(15 downto 0) <= assembled_pixel;
                                    elsif line_cnt = to_unsigned(61, 10) then
                                        line60_pair_work(15 downto 0) <= assembled_pixel;
                                    elsif line_cnt = to_unsigned(121, 10) then
                                        line120_pair_work(15 downto 0) <= assembled_pixel;
                                    elsif line_cnt = to_unsigned(181, 10) then
                                        line180_pair_work(15 downto 0) <= assembled_pixel;
                                    end if;
                                end if;
                                fifo_wr_en   <= '1';
                                pixel_cnt    <= pixel_cnt + 1;
                                line_pixel_idx <= line_pixel_idx + 1;
                                sample_armed <= '0';
                            end if;
                            byte_sel <= '0';
                        end if;
                    else
                        byte_sel <= '0';
                    end if;

                    if vsync_clean /= vsync_d then
                        if line_cnt >= END_MIN_LINES and pixel_cnt >= END_MIN_PIXELS then
                            last_line_cnt  <= line_cnt;
                            last_pixel_div <= pixel_cnt(16 downto 8);
                            line0_pair_out   <= line0_pair_work;
                            line60_pair_out  <= line60_pair_work;
                            line120_pair_out <= line120_pair_work;
                            line180_pair_out <= line180_pair_work;
                            if line_cnt >= GOOD_MIN_LINES and line_cnt <= GOOD_MAX_LINES and
                               pixel_cnt >= GOOD_MIN_PIXELS and pixel_cnt <= GOOD_MAX_PIXELS then
                                frame_valid_i <= '1';
                            else
                                frame_valid_i <= '0';
                            end if;
                            state     <= S_DONE_PULSE;
                            pulse_cnt <= to_unsigned(64, 16);
                        else
                            -- Ignore a tiny runt window and re-arm immediately
                            -- from this edge so the next full frame can start.
                            frame_valid_i <= '0';
                            byte_sel  <= '0';
                            line_cnt  <= (others => '0');
                            pixel_cnt <= (others => '0');
                            line_pixel_idx <= (others => '0');
                            sample_armed <= '1';
                            ref_pixel0 <= (others => '0');
                            ref_pixel1 <= (others => '0');
                            ref_pixel2 <= (others => '0');
                            ref_pixel3 <= (others => '0');
                            ref_pixel4 <= (others => '0');
                            ref_pixel5 <= (others => '0');
                            ref_pixel6 <= (others => '0');
                            ref_pixel7 <= (others => '0');
                            line0_pair_work   <= (others => '0');
                            line60_pair_work  <= (others => '0');
                            line120_pair_work <= (others => '0');
                            line180_pair_work <= (others => '0');
                        end if;
                    end if;

                when S_DONE_PULSE =>
                    frame_done <= '1';
                    if pulse_cnt = 0 then
                        state <= S_WAIT_FRAME;
                    else
                        pulse_cnt <= pulse_cnt - 1;
                    end if;

                when others =>
                    state <= S_IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
