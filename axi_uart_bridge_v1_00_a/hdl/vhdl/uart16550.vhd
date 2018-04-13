library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned."+";
use ieee.std_logic_unsigned."-";
use ieee.std_logic_unsigned.all;


library axi_uart_bridge_v1_00_a;
use axi_uart_bridge_v1_00_a.tx_fifo_block;
use axi_uart_bridge_v1_00_a.tx16550;
use axi_uart_bridge_v1_00_a.rx16550;
use axi_uart_bridge_v1_00_a.rx_fifo_block;

library proc_common_v3_00_a;
use proc_common_v3_00_a.family.all;
use proc_common_v3_00_a.family_support.all;


-------------------------------------------------------------------------------
-- Vcomponents from unisim library is used for FIFO instatiation
-- function declarations
-------------------------------------------------------------------------------
library unisim;
use unisim.Vcomponents.all;

-------------------------------------------------------------------------------
-- Entity section
-------------------------------------------------------------------------------
entity uart16550 is
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


end uart16550;

-------------------------------------------------------------------------------
-- Architecture section
-------------------------------------------------------------------------------
architecture implementation of uart16550 is

  constant C_HAS_EXTERNAL_XIN : boolean := FALSE;
  constant BAUD_REF_CLOCK : integer := C_S_AXI_CLK_FREQ_HZ;
  constant BAUD_DEFAULT   : integer := (BAUD_REF_CLOCK/(16 * C_UART_BAUD_RATE));
  constant BAUD_DEFAULT_X : std_logic_vector(15 downto 0):= CONV_STD_LOGIC_VECTOR(BAUD_DEFAULT,16); 
  constant ODDR_IO        : boolean := supported(C_FAMILY, (u_ODDR));

-------------------------------------------------------------------------------
-- internal signals and registers
-------------------------------------------------------------------------------
  signal rftl_i               : integer := C_RFTL;
  signal wls_i                : integer := C_WLS;
  signal stb_i                : integer := C_STB;
  signal Fcr                  : std_logic_vector (7 downto 0);  -- FIFO control register
  signal Lcr                  : std_logic_vector (7 downto 0);  -- line control reg
  signal baudCounter          : std_logic_vector (15 downto 0);  -- baud clock generator 
  signal baud_counter_loaded  : std_logic; 
  signal baudoutN_int_i       : std_logic;  
  signal baud_divisor_is_1    : std_logic;                                    
  signal clockDiv             : std_logic_vector (15 downto 0);
  signal tx_empty             : std_logic;  -- transmitter empty
  signal Tsre                 : std_logic;  -- transmitter shift reg empty
  signal tx_sout              : std_logic;  -- Sout from transmitter
  signal rx_sin               : std_logic;  -- Sin to receiver
  signal rx_rst               : std_logic;
  signal sys_clk_n            : std_logic;
  signal baud_int             : std_logic;
  signal baud_d0              : std_logic;
  signal baud_d1              : std_logic;
  
  -- rx_fifo signal
  signal rx_fifo_data_in      : std_logic_vector(10 downto 0);
  signal rx_fifo_rst          : std_logic;
  signal rx_fifo_data_out     : std_logic_vector(10 downto 0);
  signal rx_fifo_wr_en        : std_logic;
  signal rx_fifo_full         : std_logic;
  
  -- rx_16550 
  signal character_received   : std_logic;
  signal have_bi_in_fifo_n    : std_logic;
 
  
  -- tx_fifo_signal
  signal tx_fifo_empty_i      : std_logic;
  signal tx_fifo_rd_en_int    : std_logic;
  signal tx_fifo_rst          : std_logic;
  signal tx_fifo_data_out     : std_logic_vector(7 downto 0);
  
  
  signal Xin                  : std_logic;
  signal wls                  : std_logic_vector(1 downto 0); -- Word Length Select 
  signal stb                  : std_logic;
  signal rftl                 : std_logic_vector(1 downto 0);    
    
begin  -- implementation
  RCVR_FIFO_Trigger_Level_inst : process (rftl_i) is
    begin 
        case rftl_i is
            when 1 => rftl <= "00";
            when 4 => rftl <= "01";
            when 8 => rftl <= "10";
            when 14 => rftl <= "11";
            when others => rftl <= "00";
        end case;
    end process;
  
  
  word_length_reg_inst : process (wls_i) is
  begin
    case wls_i is
        when 8 => wls <= "11";
        when 7 => wls <= "10";
        when 6 => wls <= "01";
        when 5 => wls <= "00";
        when others => wls <= "11";
    end case;
  end process word_length_reg_inst;
  
  stop_bit_reg_inst : process (stb_i) is
  begin
    case stb_i is
        when 1 => stb <= '0';
        when 2 => stb <= '1';
        when others => stb <= '0';
    end case;
  end process stop_bit_reg_inst;

    Lcr <= "00000"& stb & wls;  -- line control register
    Fcr <= "00000001";          -- FIFO control register
-------------------------------------------------------------------------------
-- Sin/Sout loop back
-------------------------------------------------------------------------------  
  rx_sin    <= Sin;
  Xin       <= '1';
------------------------------------------------------------------------------- 
  clockDiv <= BAUD_DEFAULT_X;

-------------------------------------------------------------------------------  
-- PROCESS: BAUD_COUNT
-- purpose: counts the baud sample based on the value from DLL and DLM
-------------------------------------------------------------------------------
  BAUD_COUNT : process (Sys_clk) is
  begin  -- process baudCount
    if Sys_clk'EVENT and Sys_clk = '1' then  -- rising clock edge
      if Rst = '1' then         -- asynchronous reset (active high)
        --baudCounter         <= "0000000000000000";
        baudCounter         <= clockDiv;
        baud_counter_loaded <= '0';
      elsif Xin = '1' then
        if baudCounter = "0000000000000001" then
          baudCounter         <= clockDiv;
          baud_counter_loaded <= '1';
        else
          baudCounter         <= baudCounter - "0000000000000001";
          baud_counter_loaded <= '0';
        end if;
      end if;
    end if;
  end process BAUD_COUNT;

-------------------------------------------------------------------------------  
-- PROCESS: BAUDRATE_GENERATOR
-- purpose: generate BaudoutN clock
-------------------------------------------------------------------------------
  BAUDRATE_GENERATOR : process (Sys_clk) is
  begin  -- process baudRateGenerator
    if Sys_clk'EVENT and Sys_clk = '1' then  -- rising clock edge
      if (Xin = '1' and baudCounter = "0000000000000001") then
        baudoutN_int_i <= '0';
      else
        baudoutN_int_i <= '1';
      end if;
    end if;
  end process BAUDRATE_GENERATOR;

  -- Check if baud divisor value is '1'
  baud_divisor_is_1 <= '1' when clockDiv = "0000000000000001" else
                       '0';

  -- Generating inverted clock
  sys_clk_n <= not Sys_clk;

-------------------------------------------------------------------------------
-- NO_EXTERNAL_XIN : External XIN is not present.
-- Added for Baud generator to accept value 0x01 as a devisor
-- For Divisor value = 1, BaudoutN_int is same as sys_clk.
-------------------------------------------------------------------------------
  NO_EXTERNAL_XIN : if C_HAS_EXTERNAL_XIN /= TRUE generate

     baud_int  <= '0' when baud_divisor_is_1 = '1' else
                  baudoutN_int_i;

-------------------------------------------------------------------------------  
-- PROCESS: BAUD Divisor=1 check 
-- purpose: Check if baud divisor value is '1'
-------------------------------------------------------------------------------
--  BAUD_DIVISOR : process (Sys_clk) is
--  begin  -- process baudRateGenerator
--    if Sys_clk'EVENT and Sys_clk = '1' then  -- rising clock edge
--      baud_d0 <= baudoutN_int_i and not baud_divisor_is_1;
--      baud_d1 <= baudoutN_int_i or baud_divisor_is_1;
--    end if;
--  end process BAUD_DIVISOR;

     -- BaoudoutN Logic
     baud_d0 <= baudoutN_int_i and not baud_divisor_is_1;
     baud_d1 <= baudoutN_int_i or baud_divisor_is_1;

     -- Generate BaudoutN using ODDR
            ODDR_GEN : if ODDR_IO = TRUE generate

             BAUD_FF: ODDR
               port map (
                 Q   => BaudoutN,      --[out]
                 C   => Sys_clk,       --[in]
                 CE  => '1',           --[in]
                 D1  => baud_d0,       --[in]
                 D2  => baud_d1,       --[in]
                 S   => '0',           --[in]
                 R   => Rst);          --[in]

         end generate ODDR_GEN;
         

   -- Generate BaudoutN using ODDR2
        ODDR2_GEN : if ODDR_IO /= TRUE generate

                  BAUD_FF: ODDR2
                    port map (
                      Q   => BaudoutN,      --[out]
                      C0  => Sys_clk,       --[in]
                      C1  => sys_clk_n,     --[in]
                      CE  => '1',           --[in]
                      D0  => baud_d0,       --[in]
                      D1  => baud_d1,       --[in]
                      S   => '0',           --[in]
                      R   => Rst);          --[in]

        end generate ODDR2_GEN;
 
  end generate NO_EXTERNAL_XIN;

  BaudoutN_int <= baud_int;

-------------------------------------------------------------------------------
-- EXTERNAL_XIN : External XIN is used.
-- Added for Baud generator to accept value 0x01 as a devisor
-- For Divisor value = 1, BaudoutN_int is same as XIN.
-------------------------------------------------------------------------------
   EXTERNAL_XIN : if C_HAS_EXTERNAL_XIN = TRUE generate

      baud_int <= not Xin when baud_divisor_is_1 = '1' else
                      baudoutN_int_i;

      BaudoutN <= baud_int;

   end generate EXTERNAL_XIN;



-------------------------------------------------------------------------------
-- receiver instantiation
-------------------------------------------------------------------------------  
  rx16550_1 : entity axi_uart_bridge_v1_00_a.rx16550
    port map (
      Sys_clk            => Sys_clk,
      Rclk               => Rclk,
      Rst                => rst,
      Lcr                => Lcr,
      Rbr                => open,
      Fcr_0              => fcr(0),
      Sin                => rx_sin,
      Parity_error       => parity_error,
      Framing_error      => framing_error,
      Break_interrupt    => break_interrupt,
      Data_ready         => open,
      Rx_fifo_data_in    => rx_fifo_data_in,
      Character_received => character_received,
      Have_bi_in_fifo_n  => have_bi_in_fifo_n);
      
---------------------------------------------------------------------------
-- receiver fifo instantiation
---------------------------------------------------------------------------
    rx_fifo_rst <= not rx_fifo_aresetn;
    rx_fifo_rd_data <= rx_fifo_data_out(7 downto 0);
    rx_fifo_wr_en <= (Fcr(0) and (character_received and (not rx_fifo_full) and have_bi_in_fifo_n ));
    
    rx_fifo_block_1 : entity axi_uart_bridge_v1_00_a.rx_fifo_block
       generic map (
        C_FAMILY           =>  C_FAMILY )
       port map (
        Sys_clk            => Sys_clk,
        Rclk               => Rclk,
        Rst                => Rst,
        Rx_fifo_data_in    => rx_fifo_data_in,
        Rx_fifo_wr_en      => rx_fifo_wr_en,
        Rx_fifo_data_out   => rx_fifo_data_out,
        Rx_fifo_rd_en      => rx_fifo_rd_en,
        Rx_fifo_rst        => rx_fifo_rst,
        Rx_fifo_empty      => rx_fifo_empty,
        Fcr                => Fcr,
        Rx_fifo_timeout    => rx_fifo_timeout,
        Rx_fifo_trigger    => rx_fifo_trigger,
        Rx_fifo_full       => rx_fifo_full,
        Rx_error_in_fifo   => rx_error_in_fifo);
  
-------------------------------------------------------------------------------
-- transmitter instantiation
-------------------------------------------------------------------------------


  tx16550_1 : entity axi_uart_bridge_v1_00_a.tx16550
    port map (
      Sys_clk          => Sys_clk,
      Rst              => Rst,
      BaudoutN         => baud_int,
      Lcr              => Lcr,
      Thr              => (others=>'1'),
      Tx_empty         => open,
      Start_tx         => tx_fifo_empty_i,
      Sout             => Sout,
      Tsr_loaded       => open,
      Tx_fifo_rd_en    => tx_fifo_rd_en_int,
      Fcr_0            => fcr(0),
      Tx_fifo_data_out => tx_fifo_data_out);

    tx_fifo_empty <= tx_fifo_empty_i;
    ---------------------------------------------------------------------------
    -- transmitter fifo instantiation
    ---------------------------------------------------------------------------
    tx_fifo_rst <= not tx_fifo_aresetn;
    
    tx_fifo_block_1 : entity axi_uart_bridge_v1_00_a.tx_fifo_block
     generic map (
        C_FAMILY         => C_FAMILY )
      port map (
        Tx_fifo_data_in  => tx_fifo_wr_data,
        Tx_fifo_wr_en    => tx_fifo_wr_en,
        Tx_fifo_data_out => tx_fifo_data_out,
        Tx_fifo_clk      => Sys_clk,
        Tx_fifo_rd_en    => tx_fifo_rd_en_int,
        Tx_fifo_rst      => tx_fifo_rst,
        Tx_fifo_empty    => tx_fifo_empty_i,
        Tx_fifo_full     => tx_fifo_full);

  
   
        
end implementation;
