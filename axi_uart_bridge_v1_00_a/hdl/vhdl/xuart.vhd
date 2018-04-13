
library ieee;
use ieee.std_logic_1164.all;

-------------------------------------------------------------------------------
-- Definition of Generics:
-- System generics
--    C_FAMILY              --  Xilinx FPGA Family
--    C_S_AXI_CLK_FREQ_HZ   --  System clock frequency driving UART lite
--                              peripheral in Hz
--                            
-- AXI generics               
--    C_S_AXI_BASEADDR      --  Base address of the core
--    C_S_AXI_HIGHADDR      --  Permits alias of address space
--                              by making greater than xFFF
--    C_S_AXI_ADDR_WIDTH    --  Width of AXI Address Bus (in bits)
--    C_S_AXI_DATA_WIDTH    --  Width of the AXI Data Bus (in bits)
--			    
-- UART 16550 generics         
--    C_IS_A_16550          --  Selection of UART for 16450 or 16550 mode
--    C_HAS_EXTERNAL_XIN    --  External XIN
--    C_HAS_EXTERNAL_RCLK   --  External RCLK
--    C_EXTERNAL_XIN_CLK_HZ --  External XIN clock frequency
-------------------------------------------------------------------------------
--
-- Definition of ports:
-- IPIC signals
--    Bus2IP_Clk          --  Bus to IP clock
--    Bus2IP_Reset        --  Bus to IP reset
--    Bus2IP_Addr         --  Bus to IP address
--    Bus2IP_RdCE         --  Bus to IP read chip enables
--    Bus2IP_WrCE         --  Bus to IP write chip enables
--    Bus2IP_Data         --  Bus to IP data
--    IP2Bus_Data         --  IP to bus data
--    IP2Bus_WrAck        --  IP to bus write acknowledge
--    IP2Bus_RdAck        --  IP to bus read acknowledge
--
-- UART16550 interface signals
--    BaudoutN            --  Transmitter Clock
--    CtsN                --  Clear To Send (active low)
--    DcdN                --  Data Carrier Detect (active low)
--    Ddis                --  Driver Disable
--    DsrN                --  Data Set Ready (active low)
--    DtrN                --  Data Terminal Ready (active low)
--    Out1N               --  User controlled output1
--    Out2N               --  User controlled output2
--    Rclk                --  Receiver 16x Clock
--    RiN                 --  Ring Indicator (active low)
--    RtsN                --  Request To Send (active low)
--    RxrdyN              --  DMA control signal
--    Sin                 --  Serial Data Input
--    Sout                --  Serial Data Output
--    Xin                 --  Baud Rate Generator reference clock
--    Xout                --  Inverted XIN
--    TxrdyN              --  DMA control signal
--    IP2INTC_Irpt        --  Interrupt signal
--    Freeze              --  Freezes UART for software debug (active high)
--    Intr                --  Uart interupt (not used)
-------------------------------------------------------------------------------
-- Entity section
-------------------------------------------------------------------------------

entity xuart is
  
  generic (
    C_RFTL                  : integer := 1; -- RCVR FIFO Trigger Level. 1 = 1 byte; 4 = 4 bytes; 8 = 8 bytes; 14 = 14 bytes 
    C_FAMILY                : string                  := "spartan6";
    C_S_AXI_CLK_FREQ_HZ     : integer                 := 100_000_000; 
    C_UART_BAUD_RATE        : integer                 := 9600;  -- BAUD RATE
    C_HAS_EXTERNAL_RCLK     : boolean                 := FALSE;
    C_WLS                   : integer range 5 to 8    := 8;     -- DATA BITS
    C_STB                   : integer range 1 to 2    := 1      -- quantity STOP BIT
    ); 

   port (
    
    -- Uart Signals
    aclk                    : in  std_logic;
    aresetn                 : in  std_logic;
    BaudoutN                : out std_logic;
    Rclk                    : in  std_logic;
    Sin                     : in  std_logic;
    Sout                    : out std_logic;
    -- transceiver signals out fifo 
    tx_fifo_aresetn         : in std_logic;     
    tx_fifo_wr_en           : in std_logic;
    tx_fifo_wr_data         : in std_logic_vector(7 downto 0);
    tx_fifo_full            : out std_logic;
    tx_fifo_empty           : out std_logic;
    
    -- received signals in fifo
    rx_fifo_aresetn        : in std_logic;
    rx_fifo_rd_en          : in std_logic;
    rx_fifo_empty          : out std_logic;
    rx_fifo_rd_data        : out std_logic_vector(7 downto 0);
    rx_fifo_timeout        : out std_logic;
    Rx_fifo_trigger        : out std_logic;
    rx_error_in_fifo       : out std_logic;
    -- uart receiver out control signals
    Framing_error           : out std_logic;  -- framing error flag
    Break_interrupt         : out std_logic
    );

end xuart;

-------------------------------------------------------------------------------
-- Architecture section
-------------------------------------------------------------------------------
architecture imp of xuart is
	component uart16550 is
  generic (
    C_RFTL                  : integer := 1; -- RCVR FIFO Trigger Level. 1 = 1 byte; 4 = 4 bytes; 8 = 8 bytes; 14 = 14 bytes                                                      
    C_WLS                   : integer range 5 to 8 := 8;
    C_STB                   : integer range 1 to 2 := 1;
    C_UART_BAUD_RATE        : integer  := 9600;
    C_S_AXI_CLK_FREQ_HZ     : integer  := 100_000_000; -- AXI Clock Frequency
    C_FAMILY                : string   := "spartan6"); -- XILINX FPGA family
  port (
    sys_clk                 : in  std_logic;  
    rst                     : in  std_logic;
    Sout                    : out std_logic;   -- serial output
    BaudoutN                : out std_logic;   -- baud clock output
    BaudoutN_int            : out std_logic;   -- baud internal clock 
    Sin                     : in  std_logic;   -- serial in
    Rclk                    : in  std_logic;  -- receiver clock (16 x baud rate)
    -- AXI stream slave
    tx_fifo_aresetn         : in std_logic;     
    tx_fifo_wr_en           : in std_logic;
    tx_fifo_wr_data         : in std_logic_vector(7 downto 0);
    tx_fifo_full            : out std_logic;
    tx_fifo_empty           : out std_logic;
    
    -- received signals in fifo
    rx_fifo_aresetn        : in std_logic;
    rx_fifo_rd_en          : in std_logic;
    rx_fifo_empty          : out std_logic;
    rx_fifo_rd_data        : out std_logic_vector(7 downto 0);
    rx_fifo_timeout        : out std_logic;
    Rx_fifo_trigger        : out std_logic;
    rx_error_in_fifo       : out std_logic;
    -- uart receiver out control signals
    Parity_error            : out std_logic;  -- parity error flag
    Framing_error           : out std_logic;  -- framing error flag
    Break_interrupt         : out std_logic  -- break interrupt flag
      );  


end component uart16550;


  -----------------------------------------------------------------------------
    -- Signal and Type Declarations
  -----------------------------------------------------------------------------
  signal baudoutN_int     : std_logic;
  signal rclk_int         : std_logic;
  signal uart_rst         : std_logic;
  -----------------------------------------------------------------------------
    -- Begin Architecture
  -----------------------------------------------------------------------------
    
  begin
      uart_rst <= not aresetn;
  -----------------------------------------------------------------------------
  -- Component Instantiations
  -----------------------------------------------------------------------------

  -----------------------------------------------------------------------------
    -- Entity UART instantiation
  -----------------------------------------------------------------------------
       
   UART16550_I_1 : uart16550
    generic map (
      C_RFTL                => C_RFTL,
      C_WLS                 => C_WLS,
      C_STB                 => C_STB,
      C_UART_BAUD_RATE      => C_UART_BAUD_RATE,
      C_FAMILY              => C_FAMILY,
      C_S_AXI_CLK_FREQ_HZ   => C_S_AXI_CLK_FREQ_HZ
      )
    port map (
        sys_clk                 => aclk,  
        rst                     => uart_rst,
        Sout                    => Sout,
        BaudoutN                => BaudoutN,   
        BaudoutN_int            => BaudoutN_int,   -- baud internal clock 
        Sin                     => Sin,            -- serial in
        Rclk                    => rclk_int,  -- receiver clock (16 x baud rate)
        -- AXI stream slave
        tx_fifo_aresetn         => tx_fifo_aresetn ,
        tx_fifo_wr_en           => tx_fifo_wr_en   ,
        tx_fifo_wr_data         => tx_fifo_wr_data ,
        tx_fifo_full            => tx_fifo_full    ,
        tx_fifo_empty           => tx_fifo_empty   ,
        
        -- received signals in fifo
        rx_fifo_aresetn         => rx_fifo_aresetn  ,
        rx_fifo_rd_en           => rx_fifo_rd_en    ,
        rx_fifo_empty           => rx_fifo_empty    ,
        rx_fifo_rd_data         => rx_fifo_rd_data  ,
        rx_fifo_timeout         => rx_fifo_timeout  ,
        Rx_fifo_trigger         => Rx_fifo_trigger  ,
        rx_error_in_fifo        => rx_error_in_fifo ,
        -- uart receiver out control signals
        Parity_error            => open,
        Framing_error           => Framing_error     ,
        Break_interrupt         => Break_interrupt  
     );

  -----------------------------------------------------------------------------
  -- GENERATING_EXTERNAL_RCLK : Synchronize Rclk clock with system clock if 
  -- external receive clock is selected.
  -----------------------------------------------------------------------------
  GENERATING_EXTERNAL_RCLK : if C_HAS_EXTERNAL_RCLK = TRUE generate

    signal rclk_d1 : std_logic;
    signal rclk_d2 : std_logic;

  begin
  
    ---------------------------------------------------------------------------
     -- purpose: detects rising edge of Rclk
     -- type   : sequential
     -- inputs : Bus2IP_Clk, Rclk
    ---------------------------------------------------------------------------
    RCLK_RISING_EDGE : process (aclk) is
      begin  -- process RCLK_RISING_EDGE
        if aclk'event and aclk = '1' then  -- rising clock edge
          rclk_d1 <= Rclk;
          rclk_d2 <= rclk_d1;
      end if;
    end process RCLK_RISING_EDGE;
    
    rclk_int <= rclk_d1 and (not rclk_d2) and (aresetn);
  end generate GENERATING_EXTERNAL_RCLK;

  -----------------------------------------------------------------------------
  -- NOT_GENERATING_EXTERNAL_RCLK : If external receive clock is not available,
  -- use baudoutN_int as a receive clock
  -----------------------------------------------------------------------------
  NOT_GENERATING_EXTERNAL_RCLK : if C_HAS_EXTERNAL_RCLK /= TRUE generate
  begin
    rclk_int <= not baudoutN_int;
  end generate NOT_GENERATING_EXTERNAL_RCLK;

end imp;
