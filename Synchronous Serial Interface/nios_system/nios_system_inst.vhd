	component nios_system is
		port (
			clk_clk          : in  std_logic := 'X'; -- clk
			reset_reset_n    : in  std_logic := 'X'; -- reset_n
			ssi_clk_ssi_clk  : out std_logic;        -- ssi_clk
			ssi_clk_ssi_data : in  std_logic := 'X'  -- ssi_data
		);
	end component nios_system;

	u0 : component nios_system
		port map (
			clk_clk          => CONNECTED_TO_clk_clk,          --     clk.clk
			reset_reset_n    => CONNECTED_TO_reset_reset_n,    --   reset.reset_n
			ssi_clk_ssi_clk  => CONNECTED_TO_ssi_clk_ssi_clk,  -- ssi_clk.ssi_clk
			ssi_clk_ssi_data => CONNECTED_TO_ssi_clk_ssi_data  --        .ssi_data
		);

