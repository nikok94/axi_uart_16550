-------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- Create Date:     22.03.2018
-- Design Name: 
-- Module Name:     infrastructure_module
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use ieee.numeric_std.all;
library axi_uart_bridge_v1_00_a;
use axi_uart_bridge_v1_00_a.xuart;
use axi_uart_bridge_v1_00_a.axi_master_lite;
use axi_uart_bridge_v1_00_a.fsm_uart_bridge;

library UNISIM;
  use UNISIM.VComponents.all;


--------------------------- Entity declaration --------------------------------
entity axi_uart_bridge is
    generic (
    C_M_AXI_LITE_ADDR_WIDTH : INTEGER range 32 to 32 := 32;  
    C_M_AXI_LITE_DATA_WIDTH : INTEGER range 32 to 32 := 32;  

    C_FAMILY                : string                  := "spartan6";
    C_RFTL                  : integer                 := 8;   
    C_S_AXI_CLK_FREQ_HZ     : integer                 := 100_000_000;
    C_UART_BAUD_RATE        : integer                 := 9600;
    C_HAS_EXTERNAL_RCLK     : integer range 0 to 1    := 0;
    C_WLS                   : integer range 5 to 8    := 8;
    C_STB                   : integer range 1 to 2    := 1 
    ); 

   port (
    
    -- Uart Signals
    aclk                    : in  std_logic;
    aresetn                 : in  std_logic;
    BaudoutN                : out std_logic;
    Rclk                    : in  std_logic;
    Sin                     : in  std_logic;
    Sout                    : out std_logic;
    -- Axi Lite Master
    M_AXI_ARREADY           : in  std_logic;
    M_AXI_ARVALID           : out std_logic;
    M_AXI_ARADDR            : out std_logic_vector(C_M_AXI_LITE_ADDR_WIDTH-1 downto 0);
    M_AXI_ARPROT            : out std_logic_vector(2 downto 0);
    M_AXI_RREADY            : out std_logic;
    M_AXI_RVALID            : in  std_logic;
    M_AXI_RDATA             : in  std_logic_vector(C_M_AXI_LITE_DATA_WIDTH-1 downto 0) ; 
    M_AXI_RRESP             : in  std_logic_vector(1 downto 0);
                                                                            
    M_AXI_AWREADY           : in  std_logic;
    M_AXI_AWVALID           : out std_logic;
    M_AXI_AWADDR            : out std_logic_vector(C_M_AXI_LITE_ADDR_WIDTH-1 downto 0);
    M_AXI_AWPROT            : out std_logic_vector(2 downto 0);
                                                                    
    M_AXI_WREADY            : in  std_logic;
    M_AXI_WVALID            : out std_logic;
    M_AXI_WDATA             : out std_logic_vector(C_M_AXI_LITE_DATA_WIDTH-1 downto 0);
    M_AXI_WSTRB             : out std_logic_vector((C_M_AXI_LITE_DATA_WIDTH/8)-1 downto 0);
    M_AXI_BREADY            : out std_logic;
    M_AXI_BVALID            : in  std_logic;
    M_AXI_BRESP             : in  std_logic_vector(1 downto 0)        
    
    );

end entity axi_uart_bridge;


----------------------- Architecture declaration ------------------------------
architecture Behavioral of axi_uart_bridge is

    signal  tx_fifo_wr_en           : std_logic;
    signal  tx_fifo_wr_data         : std_logic_vector(7 downto 0);
    signal  tx_fifo_full            : std_logic;
    signal  tx_fifo_empty           : std_logic;
    signal  rx_fifo_rd_en           : std_logic;
    signal  rx_fifo_empty           : std_logic;
    signal  rx_fifo_rd_data         : std_logic_vector(7 downto 0);
    signal  ip2bus_mstrd_req		: std_logic;
    signal  ip2bus_mstwr_req		: std_logic;
    signal  ip2bus_mst_addr			: std_logic_vector(31 downto 0);
 
    signal  bus2ip_mst_cmdack		: std_logic;
    signal  bus2ip_mst_cmplt		: std_logic;
    signal  bus2ip_mst_error		: std_logic;
    signal  bus2ip_mstrd_src_rdy_n	: std_logic;
    signal  bus2ip_mst_rearbitrate	: std_logic;                                           
    signal  bus2ip_mst_cmd_timeout	: std_logic; 
  
    signal  bus2ip_mstrd_d			: std_logic_vector(31 downto 0);
    signal  ip2bus_mstwr_d			: std_logic_vector(31 downto 0);
    signal  bus2ip_mstwr_dst_rdy_n	: std_logic;
                         
    signal md_error                   : std_logic                           ;-- Discrete Out         
    


begin
   
    xuart_inst : entity axi_uart_bridge_v1_00_a.xuart
    
        generic map (
           C_FAMILY                => C_FAMILY,
           C_RFTL                  => C_RFTL,
           C_S_AXI_CLK_FREQ_HZ     => C_S_AXI_CLK_FREQ_HZ,
           C_UART_BAUD_RATE        => C_UART_BAUD_RATE,
           C_HAS_EXTERNAL_RCLK     => C_HAS_EXTERNAL_RCLK /= 0,
           C_WLS                   => C_WLS,
           C_STB                   => C_STB
           ) 
       
          port map (
		
		-- Uart Signals
		aclk                     => aclk,
		aresetn                  => aresetn,
		BaudoutN                 => BaudoutN,
		Rclk                     => Rclk,
		Sin                      => Sin,
		Sout                     => Sout,
		-- transceiver signals out fifo 
		tx_fifo_aresetn          => aresetn,     
		tx_fifo_wr_en            => tx_fifo_wr_en,
		tx_fifo_wr_data          => tx_fifo_wr_data,
		tx_fifo_full             => tx_fifo_full,
		tx_fifo_empty            => tx_fifo_empty,
		
		-- received signals in fifo
		rx_fifo_aresetn          => aresetn,
		rx_fifo_rd_en            => rx_fifo_rd_en,
		rx_fifo_empty            => rx_fifo_empty,
		rx_fifo_rd_data          => rx_fifo_rd_data,
		rx_fifo_timeout          => open,
		Rx_fifo_trigger          => open,
		rx_error_in_fifo         => open,
		-- uart receiver out control signals
		Framing_error            => open,  -- framing error flag
		Break_interrupt          => open  -- break interrupt flag
	
		);     
    FSM_inst : entity axi_uart_bridge_v1_00_a.fsm_uart_bridge
       
    port map (
    	aclk					=> aclk,
    	aresetn					=> aresetn,
    
    	rx_fifo_empty			=> rx_fifo_empty,
    	rx_fifo_rd_en			=> rx_fifo_rd_en,
    	rx_fifo_rd_data			=> rx_fifo_rd_data,
    
    	tx_fifo_wr_en			=> tx_fifo_wr_en,
    	tx_fifo_wr_data			=> tx_fifo_wr_data,
    	tx_fifo_full			=> tx_fifo_full,
    	
    	ip2bus_mstrd_req	    => ip2bus_mstrd_req,
    	ip2bus_mstwr_req	    => ip2bus_mstwr_req,
    	ip2bus_mst_addr		    => ip2bus_mst_addr,	
    
    	bus2ip_mst_cmdack	    => bus2ip_mst_cmdack,
    	bus2ip_mst_cmplt		=> bus2ip_mst_cmplt,	
    	bus2ip_mst_error		=> bus2ip_mst_error,	
    	bus2ip_mstrd_src_rdy_n	=> bus2ip_mstrd_src_rdy_n,
    	bus2ip_mst_rearbitrate	=> bus2ip_mst_rearbitrate,                                         
    	bus2ip_mst_cmd_timeout	=> bus2ip_mst_cmd_timeout,
    
    	bus2ip_mstrd_d			=> bus2ip_mstrd_d,
    	
    	ip2bus_mstwr_d			=> ip2bus_mstwr_d,			
    	bus2ip_mstwr_dst_rdy_n	=> bus2ip_mstwr_dst_rdy_n
    	);   

   axi_master_inst : entity axi_uart_bridge_v1_00_a.axi_master_lite 
   generic map (  
     C_M_AXI_LITE_ADDR_WIDTH => C_M_AXI_LITE_ADDR_WIDTH,
     C_M_AXI_LITE_DATA_WIDTH => C_M_AXI_LITE_DATA_WIDTH,
     C_FAMILY                => C_FAMILY
     )
   port map (
     m_axi_lite_aclk            =>  aclk,
     m_axi_lite_aresetn         =>  aresetn,
     md_error                   =>  md_error               ,
     m_axi_lite_arready         =>  M_AXI_ARREADY     ,
     m_axi_lite_arvalid         =>  M_AXI_ARVALID     ,
     m_axi_lite_araddr          =>  M_AXI_ARADDR      ,
     m_axi_lite_arprot          =>  M_AXI_ARPROT      ,
     m_axi_lite_rready          =>  M_AXI_RREADY      ,
     m_axi_lite_rvalid          =>  M_AXI_RVALID      ,
     m_axi_lite_rdata           =>  M_AXI_RDATA       ,
     m_axi_lite_rresp           =>  M_AXI_RRESP       ,
     m_axi_lite_awready         =>  M_AXI_AWREADY     ,
     m_axi_lite_awvalid         =>  M_AXI_AWVALID     ,
     m_axi_lite_awaddr          =>  M_AXI_AWADDR      ,
     m_axi_lite_awprot          =>  M_AXI_AWPROT      ,
     m_axi_lite_wready          =>  M_AXI_WREADY      ,
     m_axi_lite_wvalid          =>  M_AXI_WVALID      ,
     m_axi_lite_wdata           =>  M_AXI_WDATA       ,
     m_axi_lite_wstrb           =>  M_AXI_WSTRB       ,
     m_axi_lite_bready          =>  M_AXI_BREADY      ,
     m_axi_lite_bvalid          =>  M_AXI_BVALID      ,
     m_axi_lite_bresp           =>  M_AXI_BRESP       ,
     
     ip2bus_mstrd_req           =>  ip2bus_mstrd_req       ,
     ip2bus_mstwr_req           =>  ip2bus_mstwr_req       ,
     ip2bus_mst_addr            =>  ip2bus_mst_addr        ,
     ip2bus_mst_be              =>  "1111"          ,
     ip2bus_mst_lock            =>  '0',
     ip2bus_mst_reset           =>  '0',
     
     bus2ip_mst_cmdack          =>  bus2ip_mst_cmdack      ,
     bus2ip_mst_cmplt           =>  bus2ip_mst_cmplt       ,
     bus2ip_mst_error           =>  bus2ip_mst_error       ,
     bus2ip_mst_rearbitrate     =>  bus2ip_mst_rearbitrate ,
     bus2ip_mst_cmd_timeout     =>  bus2ip_mst_cmd_timeout ,
     bus2ip_mstrd_d             =>  bus2ip_mstrd_d         ,
     bus2ip_mstrd_src_rdy_n     =>  bus2ip_mstrd_src_rdy_n ,
     ip2bus_mstwr_d             =>  ip2bus_mstwr_d         ,
     bus2ip_mstwr_dst_rdy_n     =>  bus2ip_mstwr_dst_rdy_n                          
     ); 
  
end Behavioral;
-------------------------------------------------------------------------------