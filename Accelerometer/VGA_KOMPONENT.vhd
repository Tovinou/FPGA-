library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;  

entity VGA_KOMPONENT is 
   port
      (
      CLOCK_50          : in std_logic;
      reset_n           : in std_logic;
      KEY               : in std_logic_vector(2 downto 0);
      VGA_VS            : out std_logic;
      VGA_HS            : out std_logic;
      VGA_R             : out std_logic_vector(3 downto 0);
      VGA_G             : out std_logic_vector(3 downto 0);
      VGA_B             : out std_logic_vector(3 downto 0);		                   
      adress_vga_w      : in  std_logic_vector(16 downto 0):= (others => '0'); -- För att adressera 76800 pixlar
      data_vga_w        : in  std_logic_vector(7 downto 0) := (others => '0');
      write_VGA         : in  std_logic:= '0'      
      );
end entity;

architecture Behavioral of VGA_KOMPONENT is
   constant DATA_WIDTH           : natural := 8;
   constant ADDR_WIDTH           : natural := 6;
   signal   addr_ab              : std_logic_vector(16 downto 0):= (others => '0');
   signal   q_ab                 : std_logic_vector(7 downto 0):= (others => '0');
   SIGNAL   outclock_pll         : std_logic:='0';        --connect to clk_25
   signal   clk_25               : std_logic:='0';        -- 25 MHz clock 
   signal   status_sync_write    : std_logic:= '0';
   
  ------ Component Declarations ------
   component pll is
      port
      (
         inclk0 : IN STD_LOGIC := '0';
         c0     : OUT STD_LOGIC
      );
   end component;

   component DPRAM is
      generic 
      (
         DATA_WIDTH : natural := 8;
         ADDR_WIDTH : natural := 6			
      );
      port 
      (
         clk_a    : in std_logic;
         clk_b    : in std_logic;
         addr_a   : in std_logic_vector(ADDR_WIDTH - 1 downto 0); -- std_logic_vector for address A
         addr_b   : in std_logic_vector(ADDR_WIDTH - 1 downto 0); -- std_logic_vector for address B
         data_a   : in std_logic_vector((DATA_WIDTH-1) downto 0);
         data_b   : in std_logic_vector((DATA_WIDTH-1) downto 0);
         we_a     : in std_logic := '1';
         we_b     : in std_logic := '1';
         q_a      : out std_logic_vector((DATA_WIDTH -1) downto 0);
         q_b      : out std_logic_vector((DATA_WIDTH -1) downto 0)
      );
   end component;

   component VGA_Sync is
      port
      (
         clk_25     : in std_logic;
         reset_n    : in std_logic;
         KEY        : in std_logic_vector(2 downto 0);
         data       : in std_logic_vector(7 downto 0);
         VGA_VS     : out std_logic;
         VGA_HS     : out std_logic;
         VGA_R      : out std_logic_vector(3 downto 0);
         VGA_G      : out std_logic_vector(3 downto 0);
         VGA_B      : out std_logic_vector(3 downto 0);			                   
         adress     : out std_logic_vector(16 downto 0)
      );
   end component;

begin

   -- Instantiation of PLL component
   b2v_inst_pll: pll
      port map
      (
         inclk0 => CLOCK_50,
         c0     => outclock_pll
      );
		
   -- Instantiation of DPRAM component
   b2v_inst_DPRAM : DPRAM
      generic map (
         DATA_WIDTH => 8,
         ADDR_WIDTH => 6 
      )
      port map (
         clk_a    => outclock_pll,
         clk_b    => CLOCK_50,
         addr_a   => addr_ab(ADDR_WIDTH - 1 downto 0),
         addr_b   => addr_ab(ADDR_WIDTH - 1 downto 0),
         data_a   => data_vga_w,
         data_b   => data_vga_w,
         we_a     => write_VGA,
         we_b     => write_VGA,
         q_a      => q_ab,
         q_b      => q_ab
      );
  
   -- Instantiation of VGA_Sync component
   b2v_inst_VGA_Sync : VGA_Sync
      port map(
         clk_25      => outclock_pll,
         reset_n     => reset_n,
         KEY         => KEY,
         data        => q_ab,
         VGA_VS      => VGA_VS,
         VGA_HS      => VGA_HS,
         VGA_R       => VGA_R,
         VGA_G       => VGA_G,
         VGA_B       => VGA_B,				
         adress      => addr_ab
      );
		addr_ab <= adress_vga_w;		
  
end architecture Behavioral;
