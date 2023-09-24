library IEEE;
use IEEE.std_logic_1164.ALL;
use ieee.numeric_std.all;

--library work;

entity SPI_slave is
  generic(
    G_BUFFER_SIZE : integer := 8;
    G_ADDRESS_SIZE : integer := 32;
    G_CPHA : integer := 0; --to z inputu raczej
    G_CPOL : integer := 0;
    G_BIT_COUNTER_SIZE : integer := 4;
    G_BIT_COUNTER_MAX_VAL : integer := 8

  );
  port(
    i_clk : in std_logic; --fpga clock
    i_reset : in std_logic;

    --spi signals
    i_spi_clk : in std_logic; --spi clock 
    i_ss0 : in std_logic; --slave select
    i_ss1 : in std_logic; --slave select
    i_ss2 : in std_logic; --slave select
    i_ss3 : in std_logic; --slave select
    i_mosi : in std_logic;
    o_miso : out std_logic;
    o_ss_out_valid : in std_logic; --zmienic nazwe na i_
    ss_enable : out std_logic := '0';
    --
 
    --sygnaly Avalon do pamieci
    avalon_master_address : out std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
    avalon_master_writedata : out std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
    avalon_master_readdata : in std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
    avalon_master_write : out std_logic;
    avalon_master_waitrequest : in std_logic;
    avalon_master_read : out std_logic;

    --sygnaly avalon do komunikacji z HPS
    avalon_slave_address : in std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
    avalon_slave_writedata : in std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
    avalon_slave_readdata : out std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
    avalon_slave_write : in std_logic;
    avalon_slave_read : in std_logic;

    --interrupt output
    irq : out std_logic

  );
  end SPI_slave;


architecture SPI_slave_rtl of SPI_slave is

  signal i_spi_clkFF : std_logic;

  signal TxBitCounter_cnt : unsigned(G_BIT_COUNTER_SIZE - 1 downto 0) := (others => '0');
  signal RxBitCounter_cnt : unsigned(G_BIT_COUNTER_SIZE - 1 downto 0) := (others => '0');
 
  signal tx_buffer_reg : std_logic_vector(G_BUFFER_SIZE - 1 downto 0) := (others => '0');
  signal rx_buffer_reg : std_logic_vector(G_BUFFER_SIZE - 1 downto 0) := (others => '0');

  signal rx_buffer_out : std_logic_vector(G_BUFFER_SIZE - 1 downto 0) := (others => '0');

  signal rec_SPI_buffer : std_logic_vector(G_BUFFER_SIZE - 1 downto 0) := (others => '0');

  signal endOfTx : std_logic := '0';
  signal endOfRx : std_logic := '0';

  signal endOfTxFF : std_logic := '0';
  signal endOfTxEnable : std_logic := '0';

  signal o_ss_out_valid_reg : std_logic := '1';

  signal TempData_cnt : unsigned(G_BUFFER_SIZE - 1 downto 0) := x"10";

  signal miso : std_logic := '0';

  signal TargetAddress_reg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal TransferSetup_reg : std_logic_vector(G_BUFFER_SIZE - 1 downto 0) := (others => '0');
  signal TransferLength_reg : std_logic_vector(G_BUFFER_SIZE - 1 downto 0) := (others => '0');

  signal avm_writedata : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal avm_writeaddress : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal avm_write : std_logic;

  signal avm_memory_address_reg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');

  signal avm_memory_writedata_reg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal avm_memory_readdata_reg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal avm_memory_write_reg : std_logic := '0';
  signal avm_memory_read_reg : std_logic := '0';

  signal avm_memory_write_regFF3 : std_logic := '0';
  signal avm_memory_write_regFF2 : std_logic := '0';

  signal avm_memory_writedata_outReg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0'); 
  signal avm_memory_address_outReg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');

  signal addressSettedFlag : std_logic := '0';
  signal ControlSettedFlag : std_logic := '0';

  signal AddressPlaceCounter_cnt : unsigned(2 downto 0) := (others => '0');
  signal placeCounter_cnt : unsigned(2 downto 0) := (others => '0');
  signal spiDataCounter : unsigned(8 - 1 downto 0) := (others => '0');
  signal dataPlace : unsigned(2 downto 0) := (others => '0');
  signal ShiftCounter_cnt : unsigned(2 downto 0) := (others => '0');

  signal ss_enable_flag : std_logic := '0';
  signal firstTransactionFlag : std_logic := '1';

  type FSM is (IDLE, ADDRESS_SET, LENGTH_SET, CHECK_SETUP, READ_MEMORY_0, READ_MEMORY_0_WAIT, READ_MEMORY_1, READ_MEMORY_2, READ_MEMORY_3, END_READ, END_WRITE_TRANSFER, END_WRITE, WRITE_MEMORY);
  signal currentState : FSM;
  
  signal irq_reg : std_logic := '0';
  signal irq_out : std_logic := '0';
  signal irq_clean : std_logic:= '0';
  signal clearFlag : std_logic := '0';


  signal InterruptControl : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal InterruptControl_reg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  signal writeControl : std_logic := '0';

  signal endOfTransmission : std_logic := '0';

  begin

    avalon_slave_readdata <= InterruptControl;

    --transmitowanie (miso)
    process(i_clk)
      begin
      if(rising_edge(i_clk)) then
        if(i_reset ='1') then
          --
          TxBitCounter_cnt <= (others => '0');
          endOfTx <= '0';
        else
          if(i_ss3 = '0') then

            if(TxBitCounter_cnt < G_BIT_COUNTER_MAX_VAL) then

              if(i_spi_clk = '1' and i_spi_clkFF = '0') then

                TxBitCounter_cnt <= TxBitCounter_cnt + 1;
                endOfTx <= '0';
              else
                miso <= tx_buffer_reg( 7 - to_integer(TxBitCounter_cnt));
                TxBitCounter_cnt <= TxBitCounter_cnt;
                endOfTx <= '0';

              end if;
            else
              TxBitCounter_cnt <= (others => '0');
              endOfTx <= '1';
            end if;
          else
            TxBitCounter_cnt <= TxBitCounter_cnt;
            endOfTx <= '0';
          end if;
        end if;
      end if;
    end process;

    o_miso <= miso;

    --odbieranie (mosi)
    process(i_clk)
      begin
        if(rising_edge(i_clk)) then
          if(i_reset ='1') then
            --
            RxBitCounter_cnt <= (others => '0');
            endOfRx <= '0';
          else
            
              if(i_ss3 = '0') then
                if(RxBitCounter_cnt < G_BIT_COUNTER_MAX_VAL) then
                  if(i_spi_clk = '1' and i_spi_clkFF = '0') then
                    rx_buffer_reg <= rx_buffer_reg(G_BUFFER_SIZE - 1 - 1 downto 0) & i_mosi;
                    RxBitCounter_cnt <= RxBitCounter_cnt + 1;
                    endOfRx <= '0';
                  else
                    RxBitCounter_cnt <= RxBitCounter_cnt;
                    endOfRx <= '0';
                    rx_buffer_reg <= rx_buffer_reg;

                  end if;
                else

                  RxBitCounter_cnt <= (others => '0');
                  endOfRx <= '1';

                end if;

              else 
                RxBitCounter_cnt <= RxBitCounter_cnt;
                rx_buffer_reg <= rx_buffer_reg;
                endOfRx <= '0';

            end if;
          end if;
        end if;
      end process;


      
-------------------------------------
-------------------------------------
 --jedno przejscie FSM = 1 transakcja
process(i_clk)
  variable TempData_reg : std_logic_vector(G_ADDRESS_SIZE - 1 downto 0) := (others => '0');
  begin
    if(rising_edge(i_clk)) then
      if(i_reset = '1') then
        --
        --
      else

        case currentState is

          when IDLE =>
          --odebranie  


            if(endOfRx = '1' and irq_out = '0') then

              InterruptControl_reg <= x"00000000";
              writeControl <= '1';
              irq_reg <= '0'; 


              TargetAddress_reg <= TargetAddress_reg(G_ADDRESS_SIZE - G_BUFFER_SIZE -1 downto 0) & rx_buffer_reg(G_BUFFER_SIZE - 1 downto 0);
              AddressPlaceCounter_cnt <= AddressPlaceCounter_cnt + 1;
              currentState <= ADDRESS_SET;

            else
              avm_memory_write_reg <= '0';
              avm_memory_read_reg <= '0';
              TargetAddress_reg <= (others => '0');
              TransferSetup_reg <= (others => '0');
              ss_enable_flag <= '0';
              firstTransactionFlag <= '1';
              tx_buffer_reg <= (others => '0');

              avm_memory_writedata_reg <= (others => '0');
              avm_memory_writedata_outReg <= (others => '0');
              avm_memory_readdata_reg <= (others => '0');
              avm_memory_address_reg <= (others => '0');
              avm_memory_address_outReg <= (others => '0');
              spiDataCounter <= (others => '0');
 
              writeControl <= '0';
              irq_reg <= '0';            

              currentState <= IDLE;
            end if;
          
          when ADDRESS_SET =>

            writeControl <= '0';


            if(endOfRx = '1') then

              if(AddressPlaceCounter_cnt <= 3) then

                TargetAddress_reg <= TargetAddress_reg(G_ADDRESS_SIZE - G_BUFFER_SIZE -1 downto 0) & rx_buffer_reg(G_BUFFER_SIZE - 1 downto 0);

                AddressPlaceCounter_cnt <= AddressPlaceCounter_cnt + 1;
                currentState <= ADDRESS_SET;
              else

                TransferSetup_reg <= rx_buffer_reg(G_BUFFER_SIZE - 1 downto 0);

                TargetAddress_reg <= TargetAddress_reg;
                AddressPlaceCounter_cnt <= (others => '0');
                currentState <= LENGTH_SET;
              end if;

            end if;

          when LENGTH_SET =>
            
            if(endOfRx = '1') then
              if(to_integer(unsigned(rx_buffer_reg(G_BUFFER_SIZE - 1 downto 0))) = 0) then --zerowa dlugosc, transfer nie dojdzie do skutku
                irq_reg <= '1';
                InterruptControl_reg <= x"000000F5";
                writeControl <= '1';
                currentState <= IDLE;
              else
                TransferLength_reg <= rx_buffer_reg(G_BUFFER_SIZE - 1 downto 0);
                currentState <= CHECK_SETUP;
              end if;
            else
              currentState <= LENGTH_SET;
            end if;
              

          when CHECK_SETUP =>
              
            if(TransferSetup_reg(0) = '1' and TransferSetup_reg(1) = '0') then--
              currentState <= READ_MEMORY_0;
              avm_memory_address_reg <= TargetAddress_reg;
            elsif(TransferSetup_reg(1) = '1' and TransferSetup_reg(0) = '0') then
              currentState <= WRITE_MEMORY;
              avm_memory_address_reg <= TargetAddress_reg;
            else 
              currentState <= IDLE;
              irq_reg <= '1';
              writeControl <= '1';
              InterruptControl_reg <= x"000000F2";
            end if;
          
          when READ_MEMORY_0 => --wystawienie read requestu na stan wysoki

              avm_memory_read_reg <= '1';
              avm_memory_address_outReg <= avm_memory_address_reg;
              currentState <= READ_MEMORY_0_WAIT;


          
          when READ_MEMORY_0_WAIT => --czekanie az odczytane zostana dane spod podnego adesu i bedzie mozna podac je na SPI

            avm_memory_read_reg <= '0';
            currentState <= READ_MEMORY_1;

            
          when READ_MEMORY_1 => --wpisanie do rejestru danej odczytanej z pamieci
            
            avm_memory_readdata_reg <= avalon_master_readdata;
            avm_memory_read_reg <= '0';
            currentState <= READ_MEMORY_3;
            ss_enable_flag <= '1';

          when READ_MEMORY_2 => 


            currentState <= READ_MEMORY_3;


          when READ_MEMORY_3 => 

          if(o_ss_out_valid = '0') then -- master zakonczyl czytanie, a slave dalej chce cos nadawac

            if(placeCounter_cnt < 4) then
              if(endOfTx = '1' or firstTransactionFlag = '1') then

                if(spiDataCounter < unsigned(TransferLength_reg)) then

                  

                    tx_buffer_reg <= avm_memory_readdata_reg(G_ADDRESS_SIZE - 3 * G_BUFFER_SIZE - 1 downto 0);--jakas czesc rejestru
                    avm_memory_readdata_reg <= x"00" & avm_memory_readdata_reg(G_ADDRESS_SIZE - 1 downto G_BUFFER_SIZE);

                    avm_memory_read_reg <= '0';
                    placeCounter_cnt <= placeCounter_cnt + 1;
                    firstTransactionFlag <= '0';
                    spiDataCounter <= spiDataCounter + 1;

                else
                  currentState <= END_READ;
                  spiDataCounter <= (others => '0');
                  placeCounter_cnt <= (others => '0');
                  ss_enable_flag <= '0';

                end if;

              else
                tx_buffer_reg <= tx_buffer_reg;
                avm_memory_readdata_reg <= avm_memory_readdata_reg;
                placeCounter_cnt <= placeCounter_cnt;
                avm_memory_read_reg <= '0';

              end if;
            else --rejestr przeczytany i wyslany SPI (mozna czytac nastepny)

              if(spiDataCounter < unsigned(TransferLength_reg)) then

                placeCounter_cnt <= (others => '0');
                currentState <= READ_MEMORY_0;

                if(TransferSetup_reg(2) = '1' and TransferSetup_reg(3) = '0') then --address idzie w gore
                  avm_memory_address_reg <= std_logic_vector(unsigned(avm_memory_address_reg) + 4);
                elsif(TransferSetup_reg(3) = '1' and TransferSetup_reg(2) = '0') then
                  avm_memory_address_reg <= std_logic_vector(unsigned(avm_memory_address_reg) - 4);
                else
                  avm_memory_address_reg <= avm_memory_address_reg;
                  irq_reg <= '1';
                  InterruptControl_reg <= x"000000F3";
                  writeControl <= '1';
                  currentState <= IDLE;

                end if;
              else
                placeCounter_cnt <= (others => '0');
                currentState <= END_READ;


              end if;

            end if;

          else

            currentState <= IDLE;
            irq_reg <= '1';
            InterruptControl_reg <= x"000000FB";
            writeControl <= '1';

          end if;

          --przypadek, gdy slave juz skonczyl czytac, a master jeszcze pisze
          when END_READ => --czekanie na sygnal zakonczenia pisania z mastera, jezeli przed tym sygnalem zmieni sie zegar to rzucane jest przerwanie
            if(o_ss_out_valid = '1') then
              currentState <= IDLE;
              irq_reg <= '1';
              InterruptControl_reg <= x"000000F1";
              writeControl <= '1';

            else
              if(i_spi_clk = '1' and i_spi_clkFF = '0') then
                currentState <= IDLE;
                irq_reg <= '1';
                InterruptControl_reg <= x"000000FA";
                writeControl <= '1';

              else
                currentState <= END_READ;
              end if;
            end if;


          when WRITE_MEMORY =>

          if(o_ss_out_valid = '0') then

            if(placeCounter_cnt < 4) then
              if(endOfRx = '1') then

                if(spiDataCounter < unsigned(TransferLength_reg)) then

                    avm_memory_writedata_reg <= avm_memory_writedata_reg(G_ADDRESS_SIZE - G_BUFFER_SIZE - 1 downto 0) & rx_buffer_reg(G_BUFFER_SIZE - 1 downto 0);
                    placeCounter_cnt <= placeCounter_cnt + 1;
                    avm_memory_write_reg <= '0';
                    currentState <= WRITE_MEMORY;
                    spiDataCounter <= spiDataCounter + 1;
                                
                else
                  currentState <= END_WRITE_TRANSFER;
                  dataPlace <= 4 - placeCounter_cnt;
                  TempData_reg := avm_memory_writedata_reg;
                  spiDataCounter <= (others => '0');
                  placeCounter_cnt <= (others => '0');

                end if;
              else
            --jezeli caly rejestr juz wpisany to przekazujemy go na wyjscie

                if(spiDataCounter < unsigned(TransferLength_reg)) then

                  avm_memory_writedata_reg <= avm_memory_writedata_reg;
                  placeCounter_cnt <= placeCounter_cnt;
                  avm_memory_write_reg <= '0';
                  currentState <= WRITE_MEMORY;
                  spiDataCounter <= spiDataCounter;



                else
                  currentState <= END_WRITE_TRANSFER;
                  avm_memory_writedata_outReg <= avm_memory_writedata_reg; --piszemy na wyjscie gotowe dane do rejestru, potem to jest wpisywane do pamieci asynchronicznie
                  avm_memory_address_outReg <= avm_memory_address_Reg;

                  spiDataCounter <= (others => '0');
                  placeCounter_cnt <= (others => '0');

                end if;
              end if;

            else --if placeCounter_cnt >= C_MAX_VAL_COUNTER_REG_DATA

              placeCounter_cnt <= (others => '0');
              avm_memory_writedata_outReg <= avm_memory_writedata_reg; --piszemy na wyjscie gotowe dane do rejestru, potem to jest wpisywane do pamieci asynchronicznie
              avm_memory_writedata_reg <= (others => '0');
              avm_memory_address_outReg <= avm_memory_address_Reg;
              avm_memory_write_reg <= '1';
              currentState <= WRITE_MEMORY; 
              spiDataCounter <= spiDataCounter;
              if(TransferSetup_reg(2) = '1') then --address idzie w gore
                avm_memory_address_reg <= std_logic_vector(unsigned(avm_memory_address_reg) + 4);
              elsif(TransferSetup_reg(3) = '0') then
                avm_memory_address_reg <= std_logic_vector(unsigned(avm_memory_address_reg) - 4);
              else
              avm_memory_address_reg <= avm_memory_address_reg;
              irq_reg <= '1';
              InterruptControl_reg <= x"000000F3";
              writeControl <= '1';
              currentState <= IDLE;

              end if;

            end if;

          else

            currentState <= IDLE;
            irq_reg <= '1';
            InterruptControl_reg <= x"000000FB";
            writeControl <= '1';



          end if;

          when END_WRITE_TRANSFER => --przypadek, gdy slave juz wszystkie dane odebral, a master jeszcze nadaje

                  avm_memory_writedata_outReg <= avm_memory_writedata_Reg;
                  avm_memory_write_reg <= '1';
                  currentState <= END_WRITE;

          when END_WRITE =>

            if(o_ss_out_valid = '1') then
              currentState <= IDLE;
              irq_reg <= '1';
              InterruptControl_reg <= x"000000F1";
              writeControl <= '1';
              avm_memory_write_reg <= '0';

            else
              if(i_spi_clk = '1' and i_spi_clkFF = '0') then
                currentState <= IDLE;
                irq_reg <= '1';
                InterruptControl_reg <= x"000000FA";
                writeControl <= '1';
                avm_memory_write_reg <= '0';
              else
                currentState <= END_WRITE;
                avm_memory_write_reg <= '0';
              end if;
            end if;

                      


          when others => 
            currentState <= IDLE;

        end case;
      end if;
    end if;
  end process;


  process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(irq_reg = '1' and irq_clean = '0') then
          irq_out <= '1';
        elsif(irq_clean = '1') then
          irq_out <= '0';
        else
          irq_out <= irq_out;
        end if;
      end if;
    end process;

  irq <= irq_out;

  process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(InterruptControl(G_ADDRESS_SIZE - 1) = '1') then
          irq_clean <= '1';

        else
          irq_clean <= '0';
        end if;
      end if;
    end process;

  process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        avalon_master_write <= avm_memory_write_reg;
        avalon_master_read <= avm_memory_read_reg;
      end if;
    end process;


  avalon_master_address <= avm_memory_address_outReg;

  avalon_master_writedata <= avm_memory_writedata_outReg;
 

    process(i_clk)
      begin
        if(rising_edge(i_clk)) then
          if(avalon_slave_write = '1' and writeControl = '0') then
            InterruptControl <= avalon_slave_writedata;
          elsif(writeControl = '1') then
            InterruptControl <= InterruptControl_reg;
          else
            InterruptControl <= InterruptControl;
          end if;

        end if;
      end process;
            

    --testowy licznik do wpisania i wyslania do HPSa
    process(i_clk)
      begin
        if(rising_edge(i_clk)) then
          if(endOfTxEnable = '1') then
            TempData_cnt <= TempData_cnt + 1;
          else
            TempData_cnt <= TempData_cnt;
          end if;
        end if;
      end process;    

      --detekcja zbocza narastajacego tx zeby inkrementowac licznik tylko o 1
    process(i_clk)
      begin
        if(rising_edge(i_clk)) then
          if(endOfTxFF /= endOfTx) then
            endOfTxEnable <= '1';
            endOfTxFF <= endOfTx;
          else
            endOfTxEnable <= '0';
            endOfTxFF <= endOfTx;
          end if;
        end if;
      end process;

    process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        i_spi_clkFF <= i_spi_clk;
      end if;
    end process;



    process(i_clk)
      begin
        if(rising_edge(i_clk)) then
          if(ss_enable_flag = '1') then
            ss_enable <= '1';
          else
            ss_enable <= '0';
          end if;
        end if;
      end process;


          
    

end SPI_slave_rtl;
