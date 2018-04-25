
-------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- Create Date:     12.04.2018
-- Design Name: 
-- Module Name:     fsm_uart_bridge
-- Project Name:    axi_uart_master
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use ieee.numeric_std.all;

library UNISIM;
  use UNISIM.VComponents.all;


--------------------------- Entity declaration --------------------------------
entity fsm_uart_bridge is
generic (
    C_AXI_RW_TIME_OUT       : integer := 500;
    C_S_AXI_CLK_FREQ_HZ     : integer := 100_000_000
    );
port (
    aclk                    : in  std_logic;
    aresetn                 : in  std_logic;

    rx_fifo_empty           : in  std_logic;
    rx_fifo_rd_en           : out std_logic;
    rx_fifo_rd_data         : in  std_logic_vector(7 downto 0);

    tx_fifo_wr_en           : out std_logic;
    tx_fifo_wr_data         : out std_logic_vector(7 downto 0);
    tx_fifo_full            : in  std_logic;

    ip2bus_mstrd_req        : out std_logic;
    ip2bus_mstwr_req        : out std_logic;
    ip2bus_mst_addr         : out std_logic_vector(31 downto 0);
	 ip2bus_mst_reset			 : out std_logic;

    bus2ip_mst_cmdack       : in  std_logic;
    bus2ip_mst_cmplt        : in  std_logic;
    bus2ip_mst_error        : in  std_logic;
    bus2ip_mstrd_src_rdy_n  : in  std_logic;
    bus2ip_mst_rearbitrate  : in  std_logic;                                           
    bus2ip_mst_cmd_timeout  : in  std_logic; 

    bus2ip_mstrd_d          : in  std_logic_vector(31 downto 0);

    ip2bus_mstwr_d          : out std_logic_vector(31 downto 0);
    bus2ip_mstwr_dst_rdy_n  : in  std_logic;

    send_rw_axi_proc        : out std_logic;
    send_intr_proc          : in  std_logic
	   );
end entity fsm_uart_bridge;


----------------------- Architecture declaration ------------------------------
architecture Behavioral of fsm_uart_bridge is
    constant min_count      : integer := 0;
    constant max_count      : integer := ((C_AXI_RW_TIME_OUT*C_S_AXI_CLK_FREQ_HZ)/1000);

    type   UART_STATE_TYPE is  (START_BYTE, U_ADDR_BYTE1, U_ADDR_BYTE2, U_ADDR_BYTE3,
                                U_ADDR_BYTE4, U_WR_DATA_BYTE1, U_WR_DATA_BYTE2, U_WR_DATA_BYTE3, 
                                U_WR_DATA_BYTE4, MST_WR, MST_RD, U_SEND_RD_DATA_BYTE1, U_SEND_RD_DATA_BYTE2,
                                U_SEND_RD_DATA_BYTE3, U_SEND_RD_DATA_BYTE4, RESPONSE, INTR_PROC, U_SEND_TR_TYPE, U_SEND_ADDR_BYTE1,
                                U_SEND_ADDR_BYTE2, U_SEND_ADDR_BYTE3,U_SEND_ADDR_BYTE4);
    signal uart_state      : UART_STATE_TYPE;

    signal time_st_out     : std_logic;
    signal time_out        : std_logic;
    
    signal w_addr_phase    : std_logic;
    signal w_data_phase    : std_logic;

    signal trx_type        : std_logic_vector(3 downto 0):= B"0010";
    signal intr_type       : std_logic_vector(3 downto 0):= B"0011";
    signal start_byte_i    : std_logic;
    signal rx_fifo_rd_en_i : std_logic:= '0';
    signal rd_rx_fifo_proc : std_logic;
    --     TRX_TYPE        --
    signal trx_req_ws      : std_logic:= '0';
    signal trx_req_wb_f    : std_logic:= '0';
    signal trx_req_wb_i    : std_logic:= '0';
    signal trx_req_rs      : std_logic:= '0';
    signal trx_req_rb_f    : std_logic:= '0';
    signal trx_req_rb_i    : std_logic:= '0';

    signal axi_rd_data     : std_logic_vector(31 downto 0);
    signal axi_addr        : std_logic_vector(31 downto 0);
    signal addr_byte2      : std_logic_vector(7 downto 0);
    signal addr_byte3      : std_logic_vector(7 downto 0);
    signal addr_byte4      : std_logic_vector(7 downto 0);
    signal last_addr_byte  : std_logic;

    signal axi_tr_len       : std_logic_vector(31 downto 0);
    signal len_byte2        : std_logic_vector(7 downto 0);
    signal len_byte3        : std_logic_vector(7 downto 0);
    signal len_byte4        : std_logic_vector(7 downto 0);
    signal last_len_byte    : std_logic;
    signal len_rdy          : std_logic;

    signal wr_tx_fifo_proc  : std_logic;
    signal axi_wr_data      : std_logic_vector(31 downto 0);
    signal wr_data_byte2    : std_logic_vector(7 downto 0);
    signal wr_data_byte3    : std_logic_vector(7 downto 0);
    signal wr_data_byte4    : std_logic_vector(7 downto 0);
    signal last_w_data_byte : std_logic;

    signal u_wr_addr        : std_logic_vector(31 downto 0);
    signal u_wr_data        : std_logic_vector(31 downto 0);

    signal master_read      : std_logic;
    signal master_write     : std_logic;
    signal fsm2uart_wr_data : std_logic_vector(7 downto 0);
    signal tx_fifo_wr_en_i  : std_logic;
    signal tx_fifo_full_n   : std_logic;
    signal tr_type_i        : std_logic_vector(7 downto 0);
    signal rx_fifo_rd_data_i   : std_logic_vector ( 7 downto 0);
    signal bus2ip_mst_cmdack_i : std_logic;
    signal bus2ip_mst_cmplt_i  : std_logic;
    signal bus2ip_mstrd_d_i    : std_logic_vector(31 downto 0);
    signal ip2bus_mstwr_req_o  : std_logic;
    signal ip2bus_mstrd_req_o  : std_logic;

    signal time_out_proc    : std_logic;
    signal top_en           : std_logic;

---------------------------- Architecture body --------------------------------
begin
    send_rw_axi_proc    <= wr_tx_fifo_proc;
    bus2ip_mstrd_d_i    <= bus2ip_mstrd_d;
    bus2ip_mst_cmplt_i  <= bus2ip_mst_cmplt;
    bus2ip_mst_cmdack_i <= bus2ip_mst_cmdack;
    rx_fifo_rd_data_i   <= rx_fifo_rd_data;
    ip2bus_mstwr_req    <= ip2bus_mstwr_req_o; --master_write;
    ip2bus_mstrd_req    <= ip2bus_mstrd_req_o; --master_read;
    tx_fifo_wr_data     <= fsm2uart_wr_data; 
    tx_fifo_full_n      <= not tx_fifo_full;
    tx_fifo_wr_en_i     <= '1' when ((tx_fifo_full_n = '1') and (wr_tx_fifo_proc = '1')) else '0';
    tx_fifo_wr_en       <= tx_fifo_wr_en_i;
    ip2bus_mst_addr     <= axi_addr;
    ip2bus_mstwr_d      <= axi_wr_data;
    u_wr_addr           <= axi_addr;
    u_wr_data           <= axi_rd_data;
    rx_fifo_rd_en_i     <= '1' when ((rx_fifo_empty = '0') and (rd_rx_fifo_proc = '1')) else '0';
    rx_fifo_rd_en       <= rx_fifo_rd_en_i;
	 ip2bus_mst_reset		<= time_out;
	 
    TIME_OUT_REG_PROCESS : process (aclk, aresetn, time_st_out,time_out_proc, top_en)
    variable cnt    : integer range min_count to max_count;
    begin
      if aresetn = '0' or time_out_proc = '0' then
      cnt := 0;
      time_st_out <= '0';
      elsif aclk'event and aclk = '1' then
        if top_en = '0' then
        cnt := cnt;
        elsif  cnt = max_count then
        cnt := 0;
        time_st_out <= '1';
        else
        time_st_out <= '0';
        cnt := cnt +1;
        end if;
      end if;
     time_out <= time_st_out;
    end process TIME_OUT_REG_PROCESS;
    
    MSTWR_REQ_PROC : process(aclk, aresetn)
    begin
      if aclk'event and aclk = '1' then
        if aresetn = '0' then 
        ip2bus_mstwr_req_o <= '0';
        elsif ((master_write = '1') and (bus2ip_mst_cmdack_i = '0')) then
        ip2bus_mstwr_req_o <= '1';
        else
        ip2bus_mstwr_req_o <= '0';
        end if;
      end if;
    end process MSTWR_REQ_PROC;

    MSTRD_REQ_PROC : process(aclk, aresetn)
    begin
      if aclk'event and aclk = '1' then
        if aresetn = '0' then 
        ip2bus_mstrd_req_o <= '0';
        elsif ((master_read = '1') and (bus2ip_mst_cmdack_i = '0')) then
        ip2bus_mstrd_req_o <= '1';
        else
        ip2bus_mstrd_req_o <= '0';
        end if;
      end if;
    end process MSTRD_REQ_PROC;

    READ_START_BYTE_PROC : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            trx_req_ws       <= '0';
            trx_req_wb_f     <= '0';
            trx_req_wb_i     <= '0';
            trx_req_rs       <= '0';
            trx_req_rb_f     <= '0';
            trx_req_rb_i     <= '0';
            
            elsif (start_byte_i = '1') and (rx_fifo_rd_en_i = '1') then
                tr_type_i <= rx_fifo_rd_data_i;
                if (rx_fifo_rd_data_i = trx_type & '0' & B"000") then 
                    trx_req_rs <= '1';
                    else 
                    trx_req_rs <= '0';
                end if;
    
                if (rx_fifo_rd_data_i = trx_type & '0' & B"001") then 
                    trx_req_rb_i <= '1';
                    else 
                    trx_req_rb_i <= '0';
                end if;
    
                if (rx_fifo_rd_data_i = trx_type & '0' & B"010") then 
                    trx_req_rb_f <= '1';
                    else 
                    trx_req_rb_f <= '0';
                end if;
    
                if (rx_fifo_rd_data_i = trx_type & '0' & B"100") then 
                    trx_req_ws <= '1';
                    else 
                    trx_req_ws <= '0';
                end if;
    
                if (rx_fifo_rd_data_i = trx_type & '0' & B"101") then 
                    trx_req_wb_i <= '1';
                    else 
                    trx_req_wb_i <= '0';
                end if;
    
                if (rx_fifo_rd_data_i = trx_type & '0' & B"110") then 
                    trx_req_wb_f <= '1';
                    else 
                    trx_req_wb_f <= '0';
                end if;
            end if;
        end if; 
    end process READ_START_BYTE_PROC;

-------------------------------------------------------------------------------    
--                           UART_STATE_PROCESS                              --
-------------------------------------------------------------------------------    
    UART_STATE_PROCESS  : process (aclk, aresetn, time_out)
    begin 
        if aresetn = '0' then
            uart_state  <= START_BYTE;
            elsif (aclk'event and aclk = '1') then
                case uart_state is
                when START_BYTE => 
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_ADDR_BYTE1;
                    else 
                    uart_state <= START_BYTE;
                    end if;
                when U_ADDR_BYTE1 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_ADDR_BYTE2;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_ADDR_BYTE1;
                    end if;
                when U_ADDR_BYTE2 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_ADDR_BYTE3;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_ADDR_BYTE2;
                    end if;
                when U_ADDR_BYTE3 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_ADDR_BYTE4;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_ADDR_BYTE3;
                    end if;
                when U_ADDR_BYTE4 =>
                    if ((rx_fifo_rd_en_i = '1') and trx_req_rs = '1') then
                    uart_state <= MST_RD;
                    elsif ((rx_fifo_rd_en_i = '1') and trx_req_ws = '1') then
                    uart_state <= U_WR_DATA_BYTE1;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_ADDR_BYTE4;
                    end if;
                when U_WR_DATA_BYTE1 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_WR_DATA_BYTE2;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_WR_DATA_BYTE1;
                    end if;
                when U_WR_DATA_BYTE2 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_WR_DATA_BYTE3;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_WR_DATA_BYTE2;
                    end if;
                when U_WR_DATA_BYTE3 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= U_WR_DATA_BYTE4;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_WR_DATA_BYTE3;
                    end if;
                when U_WR_DATA_BYTE4 =>
                    if (rx_fifo_rd_en_i = '1') then
                    uart_state <= MST_WR;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_WR_DATA_BYTE4;
                    end if;
                when MST_WR =>
                    if bus2ip_mst_cmdack_i = '1' then
                    uart_state <= RESPONSE;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= MST_WR;
                    end if;
                when MST_RD => 
                    if bus2ip_mst_cmdack_i = '1' then
                    uart_state <= RESPONSE;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= MST_RD;
                    end if;
                when RESPONSE => 
                    if (bus2ip_mst_cmplt_i = '1') then
                    if ((send_intr_proc and not wr_tx_fifo_proc) = '1') then
                    uart_state <= INTR_PROC;
                    else
                    uart_state <= U_SEND_TR_TYPE;
                    end if;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else 
                    uart_state <= RESPONSE;
                    end if;
                when INTR_PROC =>
                    if ((send_intr_proc and not wr_tx_fifo_proc) = '0') then
                    uart_state <= U_SEND_TR_TYPE;
                    else
                    uart_state <= INTR_PROC;
                    end if;
                when U_SEND_TR_TYPE => 
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_ADDR_BYTE1;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_TR_TYPE;
                    end if;
                when U_SEND_ADDR_BYTE1 => 
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_ADDR_BYTE2;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_ADDR_BYTE1;
                    end if;
                when U_SEND_ADDR_BYTE2 => 
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_ADDR_BYTE3;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_ADDR_BYTE2;
                    end if;
                when U_SEND_ADDR_BYTE3 => 
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_ADDR_BYTE4;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_ADDR_BYTE3;
                    end if;
                when U_SEND_ADDR_BYTE4 => 
                    if (tx_fifo_wr_en_i = '1' and trx_req_ws = '1') then
                    uart_state <= START_BYTE;
                    elsif (tx_fifo_wr_en_i = '1' and trx_req_rs = '1') then
                    uart_state <= U_SEND_RD_DATA_BYTE1;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_ADDR_BYTE4;
                    end if;
                when U_SEND_RD_DATA_BYTE1 =>
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_RD_DATA_BYTE2;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_RD_DATA_BYTE1;
                    end if;
                when U_SEND_RD_DATA_BYTE2 =>
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_RD_DATA_BYTE3;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_RD_DATA_BYTE2;
                    end if;
                when U_SEND_RD_DATA_BYTE3 =>
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= U_SEND_RD_DATA_BYTE4;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_RD_DATA_BYTE3;
                    end if;
                when U_SEND_RD_DATA_BYTE4 =>
                    if (tx_fifo_wr_en_i = '1') then
                    uart_state <= START_BYTE;
                    elsif time_out = '1' then
                    uart_state <= START_BYTE;
                    else
                    uart_state <= U_SEND_RD_DATA_BYTE4;
                    end if;
                when others =>
                    uart_state <= START_BYTE;
                end case;
        end if;
    end process;
------------------------------------------------------------------------------------
--    axi address read from uart 
------------------------------------------------------------------------------------
    ADDR_REG_PROCESS : process(aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            axi_addr    <=(others => '0');
            addr_byte2    <=(others => '0');
            addr_byte3    <=(others => '0');
            addr_byte4    <=(others => '0');
            elsif (((rx_fifo_rd_en_i = '1') and (w_addr_phase = '1')) and (last_addr_byte ='0')) then
            addr_byte2    <= rx_fifo_rd_data_i;
            addr_byte3    <= addr_byte2;
            addr_byte4    <= addr_byte3;
            elsif ((rx_fifo_rd_en_i = '1') and (last_addr_byte ='1')) then
            axi_addr(31 downto 0) <= (rx_fifo_rd_data_i & addr_byte2 & addr_byte3 & addr_byte4);
            else 
            axi_addr(31 downto 0) <= axi_addr(31 downto 0);
            end if;
        end if;
    end process ADDR_REG_PROCESS;

-----------------------------------------------------------------------------------
--    axi data read from uart
-----------------------------------------------------------------------------------    
    DATA_REG_PROCESS : process(aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then
            axi_wr_data    <=(others => '0'); 
            wr_data_byte2    <=(others => '0');
            wr_data_byte3    <=(others => '0');
            wr_data_byte4    <=(others => '0');
            elsif (((rx_fifo_rd_en_i = '1') and (w_data_phase = '1')) and (last_w_data_byte ='0')) then
            wr_data_byte2    <= rx_fifo_rd_data_i;
            wr_data_byte3    <= wr_data_byte2;
            wr_data_byte4    <= wr_data_byte3;
            elsif ((rx_fifo_rd_en_i = '1') and (last_w_data_byte ='1')) then 
            axi_wr_data(31 downto 0) <= (rx_fifo_rd_data_i & wr_data_byte2 & wr_data_byte3 & wr_data_byte4);
            else 
            axi_wr_data(31 downto 0) <=axi_wr_data(31 downto 0);
            end if;
        end if;
    end process DATA_REG_PROCESS;

----------------------------------------------------------------------------------
--    read data from axi
----------------------------------------------------------------------------------
    RES_RD_DATA_PROCESS : process (aclk, aresetn)
    begin
        if aclk'event and aclk = '1' then
            if aresetn = '0' then 
            axi_rd_data <= (others => '0');
            elsif (bus2ip_mst_cmplt_i = '1') then
            axi_rd_data <= bus2ip_mstrd_d_i;
            else
            axi_rd_data <= axi_rd_data;
            end if;
        end if;
    end process RES_RD_DATA_PROCESS;

---------------------------------------------------------------------------------
--    state handler
---------------------------------------------------------------------------------

    UART_PROCESS : process (uart_state) is
    begin
    case uart_state is
        when START_BYTE =>
                time_out_proc       <= '0';
                top_en              <= '0';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '1';
                rd_rx_fifo_proc     <= '1';
        when U_ADDR_BYTE1 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                
        when U_ADDR_BYTE2 => 
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when U_ADDR_BYTE3 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when U_ADDR_BYTE4 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '1';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when U_WR_DATA_BYTE1 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when U_WR_DATA_BYTE2 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when U_WR_DATA_BYTE3 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when U_WR_DATA_BYTE4 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '1';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '1';
        when MST_WR =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '1';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when MST_RD =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '1';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_RD_DATA_BYTE1 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_rd_data(7 downto 0);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_RD_DATA_BYTE2 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_rd_data(15 downto 8);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_RD_DATA_BYTE3 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_rd_data(23 downto 16);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_RD_DATA_BYTE4 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_rd_data(31 downto 24);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '1';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when RESPONSE =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when INTR_PROC =>
                time_out_proc       <= '1';
                top_en              <= '0';
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_TR_TYPE =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= tr_type_i;
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_ADDR_BYTE1 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_addr(7 downto 0);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_ADDR_BYTE2 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_addr(15 downto 8);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_ADDR_BYTE3 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_addr(23 downto 16);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when U_SEND_ADDR_BYTE4 =>
                time_out_proc       <= '1';
                top_en              <= '1';
                fsm2uart_wr_data    <= axi_addr(31 downto 24);
                wr_tx_fifo_proc     <= '1';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '1';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '0';
                rd_rx_fifo_proc     <= '0';
        when others =>
                fsm2uart_wr_data    <= (others => '0');
                wr_tx_fifo_proc     <= '0';
                last_w_data_byte    <= '0';
                last_addr_byte      <= '0';
                w_addr_phase        <= '0';
                w_data_phase        <= '0';
                master_write        <= '0';
                master_read         <= '0';
                start_byte_i        <= '1';
                rd_rx_fifo_proc     <= '1';
                
    end case;
    end process UART_PROCESS;
end Behavioral;
-------------------------------------------------------------------------------