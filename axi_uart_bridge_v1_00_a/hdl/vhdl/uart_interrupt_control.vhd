library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use ieee.numeric_std.all;

library UNISIM;
  use UNISIM.VComponents.all;


--------------------------- Entity declaration --------------------------------
entity uart_interrupt_control is
generic (
    C_INTR_WIDTH            : integer range 1 to 8          := 8;
    C_INTR_ADDR_0           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_1           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_2           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_3           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_4           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_5           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_6           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF";
    C_INTR_ADDR_7           : std_logic_vector(31 DOWNTO 0) := x"FFFF_FFFF"
);
port (
    aclk                    : in  std_logic;
    aresetn                 : in  std_logic;

    tx_fifo_wr_en           : out std_logic;
    tx_fifo_wr_data         : out std_logic_vector(7 downto 0);
    tx_fifo_full            : in  std_logic;

    -- fsm_uart signals --
    send_intr_proc          : out std_logic;
    send_rw_axi_proc        : in  std_logic;

    INTR_vec                : in  std_logic_vector(C_INTR_WIDTH-1 downto 0)
    );
end entity uart_interrupt_control;


----------------------- Architecture declaration ------------------------------
architecture Behavioral of uart_interrupt_control is
    constant INTR_WIDTH         : integer:= C_INTR_WIDTH;

    type   INTR_STATE_TYPE is (IDLE, ADDR_0, ADDR_1, ADDR_2, ADDR_3, ADDR_4, ADDR_5, ADDR_6, ADDR_7,
                               U_SEND_ADDR_BYTE1, U_SEND_ADDR_BYTE2, U_SEND_ADDR_BYTE3, U_SEND_ADDR_BYTE4);
    signal intr_state           : INTR_STATE_TYPE;

    signal in_intr_0            : std_logic;
    signal in_intr_1            : std_logic;
    signal in_intr_2            : std_logic;
    signal in_intr_3            : std_logic;
    signal in_intr_4            : std_logic;
    signal in_intr_5            : std_logic;
    signal in_intr_6            : std_logic;
    signal in_intr_7            : std_logic;
    
    signal d_in_intr_0          : std_logic;
    signal d_in_intr_1          : std_logic;
    signal d_in_intr_2          : std_logic;
    signal d_in_intr_3          : std_logic;
    signal d_in_intr_4          : std_logic;
    signal d_in_intr_5          : std_logic;
    signal d_in_intr_6          : std_logic;
    signal d_in_intr_7          : std_logic;
    
    signal intr_0               : std_logic:='0';
    signal intr_1               : std_logic:='0';
    signal intr_2               : std_logic:='0';
    signal intr_3               : std_logic:='0';
    signal intr_4               : std_logic:='0';
    signal intr_5               : std_logic:='0';
    signal intr_6               : std_logic:='0';
    signal intr_7               : std_logic:='0';

    signal u_s_intr_0           : std_logic:='0';
    signal u_s_intr_1           : std_logic:='0';
    signal u_s_intr_2           : std_logic:='0';
    signal u_s_intr_3           : std_logic:='0';
    signal u_s_intr_4           : std_logic:='0';
    signal u_s_intr_5           : std_logic:='0';
    signal u_s_intr_6           : std_logic:='0';
    signal u_s_intr_7           : std_logic:='0';

    signal s_int_addr_0         : std_logic;
    signal s_int_addr_1         : std_logic;
    signal s_int_addr_2         : std_logic;
    signal s_int_addr_3         : std_logic;
    signal s_int_addr_4         : std_logic;
    signal s_int_addr_5         : std_logic;
    signal s_int_addr_6         : std_logic;
    signal s_int_addr_7         : std_logic;
    
    signal INTR_TYPE            : std_logic_vector(7 downto 0):= B"00110000";

    signal tx_fifo_wr_en_i      : std_logic;
    signal send_intr_proc_i     : std_logic;
    signal tx_fifo_wr_data_i    : std_logic_vector(7 downto 0);

    signal send_addr_byte_1     : std_logic_vector(7 downto 0);
    signal send_addr_byte_2     : std_logic_vector(7 downto 0);
    signal send_addr_byte_3     : std_logic_vector(7 downto 0);
    signal send_addr_byte_4     : std_logic_vector(7 downto 0);
---------------------------- Architecture body --------------------------------
begin
    tx_fifo_wr_data <= tx_fifo_wr_data_i;
    tx_fifo_wr_en   <= tx_fifo_wr_en_i;
    send_intr_proc  <= send_intr_proc_i;
    tx_fifo_wr_en_i <= '1' when ((send_intr_proc_i and not send_rw_axi_proc) = '1' and tx_fifo_full = '0') else '0';

    in_intr_0 <= INTR_vec(0); --when (INTR_WIDTH >= 1) else '0';
    in_intr_1 <= INTR_vec(1); --when (INTR_WIDTH >= 2) else '0';
    in_intr_2 <= INTR_vec(2); --when (INTR_WIDTH >= 3) else '0';
    in_intr_3 <= INTR_vec(3); --when (INTR_WIDTH >= 4) else '0';
    in_intr_4 <= INTR_vec(4); --when (INTR_WIDTH >= 5) else '0';
    in_intr_5 <= INTR_vec(5); --when (INTR_WIDTH >= 6) else '0';
    in_intr_6 <= INTR_vec(6); --when (INTR_WIDTH >= 7) else '0';
    in_intr_7 <= INTR_vec(7); --when (INTR_WIDTH  = 8) else '0';

    DELAY_INTR_PROC_0 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_0 <= '0';
            else
            d_in_intr_0 <= in_intr_0;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_1 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_1 <= '0';
            else
            d_in_intr_1 <= in_intr_1;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_2 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_2 <= '0';
            else
            d_in_intr_2 <= in_intr_2;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_3 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_3 <= '0';
            else
            d_in_intr_3 <= in_intr_3;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_4 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_4 <= '0';
            else
            d_in_intr_4 <= in_intr_4;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_5 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_5 <= '0';
            else
            d_in_intr_5 <= in_intr_5;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_6 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_6 <= '0';
            else
            d_in_intr_6 <= in_intr_6;
            end if;
        end if;
    end process;
    
    DELAY_INTR_PROC_7 : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            d_in_intr_7 <= '0';
            else
            d_in_intr_7 <= in_intr_7;
            end if;
        end if;
    end process;
    
    INTR_0_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_0 = '1' and tx_fifo_wr_en_i = '1') then
            intr_0 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_0 and in_intr_0) = '1' then
            intr_0 <= '1';
            end if;
        end if;
    end process INTR_0_PROC;

    INTR_1_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_1 = '1' and tx_fifo_wr_en_i = '1') then
            intr_1 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_1 and in_intr_1) = '1' then
            intr_1 <= '1';
            end if;
        end if;
    end process INTR_1_PROC;

    INTR_2_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_2 = '1' and tx_fifo_wr_en_i = '1') then
            intr_2 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_2 and in_intr_2) = '1' then
            intr_2 <= '1';
            end if;
        end if;
    end process INTR_2_PROC;

    INTR_3_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_3 = '1' and tx_fifo_wr_en_i = '1') then
            intr_3 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_3 and in_intr_3) = '1' then
            intr_3 <= '1';
            end if;
        end if;
    end process INTR_3_PROC;

    INTR_4_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_4 = '1' and tx_fifo_wr_en_i = '1') then
            intr_4 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_4 and in_intr_4) = '1' then
            intr_4 <= '1';
            end if;
        end if;
    end process INTR_4_PROC;

    INTR_5_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_5 = '1' and tx_fifo_wr_en_i = '1') then
            intr_5 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_5 and in_intr_5) = '1' then
            intr_5 <= '1';
            end if;
        end if;
    end process INTR_5_PROC;

    INTR_6_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_6 = '1' and tx_fifo_wr_en_i = '1') then
            intr_6 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_6 and in_intr_6) = '1' then
            intr_6 <= '1';
            end if;
        end if;
    end process INTR_6_PROC;

    INTR_7_PROC : process (aclk, aresetn)
    begin
        if aresetn = '0' or (u_s_intr_7 = '1' and tx_fifo_wr_en_i = '1') then
            intr_7 <= '0';
            elsif aclk'event and aclk = '1' then
            if (not d_in_intr_7 and in_intr_7) = '1' then
            intr_7 <= '1';
            end if;
        end if;
    end process INTR_7_PROC;


--    intr_0 <= '1' when (not d_in_intr_0 and in_intr_0) = '1' else '0'
--                  when s_int_addr_0 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_1 <= '1' when (not d_in_intr_1 and in_intr_1) = '1' else '0'
--                  when s_int_addr_1 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_2 <= '1' when (not d_in_intr_2 and in_intr_2) = '1' else '0'
--                  when s_int_addr_2 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_3 <= '1' when (not d_in_intr_3 and in_intr_3) = '1' else '0'
--                  when s_int_addr_3 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_4 <= '1' when (not d_in_intr_4 and in_intr_4) = '1' else '0'
--                  when s_int_addr_4 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_5 <= '1' when (not d_in_intr_5 and in_intr_5) = '1' else '0'
--                  when s_int_addr_5 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_6 <= '1' when (not d_in_intr_6 and in_intr_6) = '1' else '0'
--                  when s_int_addr_6 = '1' and tx_fifo_wr_en_i = '1';
--                  
--    intr_7 <= '1' when (not d_in_intr_7 and in_intr_7) = '1' else '0'
--                  when s_int_addr_7 = '1' and tx_fifo_wr_en_i = '1';

    s_int_addr_0 <= '1' when (intr_0 ='1') else '0';
    s_int_addr_1 <= '1' when (s_int_addr_0 = '0' and s_int_addr_0 = '0' and intr_1 = '1') else '0';
    s_int_addr_2 <= '1' when (s_int_addr_0 = '0' and s_int_addr_1 = '0' and intr_2 = '1') else '0';
    s_int_addr_3 <= '1' when (s_int_addr_0 = '0' and s_int_addr_2 = '0' and intr_3 = '1') else '0';
    s_int_addr_4 <= '1' when (s_int_addr_0 = '0' and s_int_addr_3 = '0' and intr_4 = '1') else '0';
    s_int_addr_5 <= '1' when (s_int_addr_0 = '0' and s_int_addr_4 = '0' and intr_5 = '1') else '0';
    s_int_addr_6 <= '1' when (s_int_addr_0 = '0' and s_int_addr_5 = '0' and intr_6 = '1') else '0';
    s_int_addr_7 <= '1' when (s_int_addr_0 = '0' and s_int_addr_6 = '0' and intr_7 = '1') else '0';
-----------------------------------------------------------------------------
--                          INTR_STATE_PROCESS                             --
-----------------------------------------------------------------------------
    INTR_STATE_PROC : process (aclk,aresetn)
    begin
        if aresetn = '0' then 
           intr_state <= IDLE;
           elsif (aclk'event and aclk = '1') then
              case intr_state is
                when IDLE => 
                  if s_int_addr_0 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_0;
                  elsif s_int_addr_1 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_1;
                  elsif s_int_addr_2 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_2;
                  elsif s_int_addr_3 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_3;
                  elsif s_int_addr_4 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_4;
                  elsif s_int_addr_5 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_5;
                  elsif s_int_addr_6 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_6;
                  elsif s_int_addr_7 = '1' and send_rw_axi_proc = '0' then
                  intr_state <= ADDR_7;
                  else
                  intr_state <= IDLE;
                  end if;
                when ADDR_0 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_0;
                  end if;
                when ADDR_1 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_1;
                  end if;
                when ADDR_2 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_2;
                  end if;
                when ADDR_3 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_3;
                  end if;
                when ADDR_4 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_4;
                  end if;
                when ADDR_5 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_5;
                  end if;
                when ADDR_6 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_6;
                  end if;
                when ADDR_7 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE1;
                  else 
                  intr_state <= ADDR_7;
                  end if;
                when U_SEND_ADDR_BYTE1 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE2;
                  else 
                  intr_state <= U_SEND_ADDR_BYTE1;
                  end if;
                when U_SEND_ADDR_BYTE2 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE3;
                  else 
                  intr_state <= U_SEND_ADDR_BYTE2;
                  end if;
                when U_SEND_ADDR_BYTE3 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= U_SEND_ADDR_BYTE4;
                  else 
                  intr_state <= U_SEND_ADDR_BYTE3;
                  end if;
                when U_SEND_ADDR_BYTE4 =>
                  if tx_fifo_wr_en_i = '1' then
                  intr_state <= IDLE;
                  else 
                  intr_state <= U_SEND_ADDR_BYTE4;
                  end if;
                when others =>
                  intr_state <= IDLE;
              end case;
			end if;
    end process INTR_STATE_PROC;

    SEND_INTR_PROCESS : process (intr_state)
    begin
      case intr_state is
        when IDLE => 
          send_intr_proc_i <= '0';
          u_s_intr_0 <= '0';
          u_s_intr_1 <= '0';
          u_s_intr_2 <= '0';
          u_s_intr_3 <= '0';
          u_s_intr_4 <= '0';
          u_s_intr_5 <= '0';
          u_s_intr_6 <= '0';
          u_s_intr_7 <= '0';
        when ADDR_0 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_0 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_0(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_0(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_0(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_0(31 downto 24);
        when ADDR_1 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_1 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_1(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_1(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_1(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_1(31 downto 24);
        when ADDR_2 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_2 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_2(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_2(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_2(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_2(31 downto 24);
        when ADDR_3 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_3 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_3(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_3(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_3(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_3(31 downto 24);
        when ADDR_4 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_4 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_4(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_4(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_4(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_4(31 downto 24);
        when ADDR_5 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_5 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_5(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_5(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_5(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_5(31 downto 24);
        when ADDR_6 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_6 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_6(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_6(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_6(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_6(31 downto 24);
        when ADDR_7 =>
          tx_fifo_wr_data_i <= INTR_TYPE;
          u_s_intr_7 <= '1';
          send_intr_proc_i <= '1';
          send_addr_byte_1 <= C_INTR_ADDR_7(7 downto 0);
          send_addr_byte_2 <= C_INTR_ADDR_7(15 downto 8);
          send_addr_byte_3 <= C_INTR_ADDR_7(23 downto 16);
          send_addr_byte_4 <= C_INTR_ADDR_7(31 downto 24);
        when U_SEND_ADDR_BYTE1 =>
          u_s_intr_0 <= '0';
          u_s_intr_1 <= '0';
          u_s_intr_2 <= '0';
          u_s_intr_3 <= '0';
          u_s_intr_4 <= '0';
          u_s_intr_5 <= '0';
          u_s_intr_6 <= '0';
          u_s_intr_7 <= '0';
          tx_fifo_wr_data_i <= send_addr_byte_1;
          send_intr_proc_i <= '1';
        when U_SEND_ADDR_BYTE2 =>
          tx_fifo_wr_data_i <= send_addr_byte_2;
          send_intr_proc_i <= '1';
        when U_SEND_ADDR_BYTE3 =>
          tx_fifo_wr_data_i <= send_addr_byte_3;
          send_intr_proc_i <= '1';
        when U_SEND_ADDR_BYTE4 =>
          tx_fifo_wr_data_i <= send_addr_byte_4;
          send_intr_proc_i <= '1';
      end case;
    end process SEND_INTR_PROCESS;
end Behavioral;
-------------------------------------------------------------------------------