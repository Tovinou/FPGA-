library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TIMER_HW_IP is
   port (
      clk     : in std_logic;
      reset_n : in std_logic;
      cs_n    : in std_logic;                     -- IP component select
      addr    : in std_logic_vector(3 downto 0);  -- offset address (4 bits for 16 addresses)
      write_n : in std_logic;
      read_n  : in std_logic;
      din     : in std_logic_vector(31 downto 0); -- data in
      dout    : out std_logic_vector(31 downto 0); -- data out
      
      -- External interrupt and capture signals
      ext_capture : in std_logic;                 -- External capture trigger
      compare_int : out std_logic;                -- Compare interrupt
      overflow_int : out std_logic;               -- Overflow interrupt
      pwm_out     : out std_logic                 -- PWM output
   );
end entity TIMER_HW_IP;

architecture rtl of TIMER_HW_IP is

   signal data_reg     : std_logic_vector(31 downto 0); -- Timer value
   signal control_reg  : std_logic_vector(7 downto 0);  -- Control Register (extended to 8 bits)
   signal status_reg   : std_logic_vector(7 downto 0);  -- Status Register
   signal load_reg     : std_logic_vector(31 downto 0); -- Load Register
   signal compare_reg  : std_logic_vector(31 downto 0); -- Compare Register
   signal capture_reg  : std_logic_vector(31 downto 0); -- Capture Register
   
   signal compare_int_sig  : std_logic;
   signal overflow_int_sig : std_logic;
   signal pwm_out_sig      : std_logic;

   -- Timer component with all enhancements
   component timer is
      GENERIC (
         TIMER_WIDTH : integer := 32
      );
      port (
         clk            : IN std_logic;
         reset_n        : IN std_logic;
         Control_timer  : IN std_logic_vector(7 downto 0);
         timer_data     : OUT std_logic_vector(31 DOWNTO 0);
         load_value     : IN std_logic_vector(31 DOWNTO 0);
         compare_value  : IN std_logic_vector(31 DOWNTO 0);
         status_reg     : OUT std_logic_vector(7 downto 0);
         capture_data   : OUT std_logic_vector(31 DOWNTO 0);
         ext_capture    : IN std_logic;
         compare_int    : OUT std_logic;
         overflow_int   : OUT std_logic;
         pwm_out        : OUT std_logic
      );
   end component;
	
begin

   ----------------------------------------------------------------
   -- Register Read Process
   -- Address Map:
   -- 0x0 = Timer Value (read-only)
   -- 0x1 = Control Register (read/write)
   -- 0x2 = Status Register (read-only)
   -- 0x3 = Load Register (write-only)
   -- 0x4 = Compare Register (write-only)
   -- 0x5 = Capture Register (read-only)
   ----------------------------------------------------------------
   
   Bus_register_read_process :
   process(cs_n, read_n, addr, data_reg, control_reg, status_reg, capture_reg)
   begin
      if (cs_n = '0' and read_n = '0') then
         case addr is
            when "0000" => 
               dout <= data_reg;          -- Timer value
            when "0001" => 
               dout <= x"000000" & control_reg;  -- Control register
            when "0010" => 
               dout <= x"000000" & status_reg;   -- Status register
            when "0101" => 
               dout <= capture_reg;       -- Capture register
            when others => 
               dout <= (others => '0');
         end case;
      else
         dout <= (others => '0');
      end if;
   end process Bus_register_read_process;

   ---------------------------------------------------------------
   -- Register Write Process
   ---------------------------------------------------------------
   Bus_register_write_process :
   process(clk, reset_n)
   begin
      if reset_n = '0' then
         control_reg <= (others => '0');
         load_reg <= (others => '0');
         compare_reg <= (others => '0');
         
      elsif rising_edge(clk) then
         if (cs_n = '0' and write_n = '0') then
            case addr is
               when "0001" => 
                  -- Write to control register
                  control_reg <= din(7 downto 0);
                  
               when "0011" => 
                  -- Write to load register
                  load_reg <= din;
                  
               when "0100" => 
                  -- Write to compare register
                  compare_reg <= din;
                  
               when others => 
                  null;
            end case;
         end if;
      end if;
   end process Bus_register_write_process;

   ----------------------------------------------------------------
   -- Timer Component Instantiation
   ----------------------------------------------------------------
   b2v_inst_timer : timer
   GENERIC MAP (
      TIMER_WIDTH => 32
   )
   port map (
      clk            => clk,
      reset_n        => reset_n,
      Control_timer  => control_reg,
      timer_data     => data_reg,
      load_value     => load_reg,
      compare_value  => compare_reg,
      status_reg     => status_reg,
      capture_data   => capture_reg,
      ext_capture    => ext_capture,
      compare_int    => compare_int_sig,
      overflow_int   => overflow_int_sig,
      pwm_out        => pwm_out_sig
   );

   -- Output interrupt and PWM signals
   compare_int  <= compare_int_sig;
   overflow_int <= overflow_int_sig;
   pwm_out      <= pwm_out_sig;

end rtl;
