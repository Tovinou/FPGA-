LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY data_interface IS
   PORT 
      (
      reset_n     : IN  STD_LOGIC;
      clock_50    : IN  STD_LOGIC;
      acc_x       : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
      acc_y       : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
      acc_z       : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
      data_x_y_z  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)      
      );
END ENTITY data_interface;

ARCHITECTURE behavior OF data_interface IS
   SIGNAL x_valid       : STD_LOGIC := '0';
   SIGNAL y_valid       : STD_LOGIC := '0';
   SIGNAL z_valid       : STD_LOGIC := '0';
BEGIN

   PROCESS (clock_50, reset_n)
   BEGIN
      IF reset_n = '0' THEN
         x_valid <= '0';
         y_valid <= '0';
         z_valid <= '0';
         data_x_y_z <= (OTHERS => '0');
      ELSIF rising_edge(clock_50) THEN
         -- Check if acc_x is non-zero
         IF acc_x /= "0000000000000000" THEN
            x_valid <= '1';
         ELSE
            x_valid <= '0';
         END IF;

         -- Check if acc_y is non-zero
         IF acc_y /= "0000000000000000" THEN
            y_valid <= '1';
         ELSE
            y_valid <= '0';
         END IF;

         -- Check if acc_z is non-zero
         IF acc_z /= "0000000000000000" THEN
            z_valid <= '1';
         ELSE
            z_valid <= '0';
         END IF;

         -- Set data_x_y_z output based on the validity of the data
         data_x_y_z(0) <= x_valid;
         data_x_y_z(1) <= y_valid;
         data_x_y_z(2) <= z_valid;
      END IF;
   END PROCESS;

END ARCHITECTURE behavior;
