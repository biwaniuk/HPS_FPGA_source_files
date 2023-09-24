
library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;



entity DMAC_top is
  generic(
    G_CNT_MAX_VAL : integer := 64;
    G_ADDRES_SIZE : integer := 32;
    G_DATA_SIZE : integer := 32;
    G_DATA_COUNTER_SIZE : integer := 16
  );
  port(
    i_clk : in std_logic;
    i_reset : in std_logic;
    
    --Avalon master signals: (write)
    avm_write_master_write : out std_logic;
    avm_write_master_address : out std_logic_vector (G_ADDRES_SIZE - 1 downto 0);
    avm_write_master_writedata : out std_logic_vector (G_DATA_SIZE - 1 downto 0);
    avm_write_master_waitrequest : in std_logic;



    --Avalon master signals: (read)
    avm_read_master_read : out std_logic;
    avm_read_master_address : out std_logic_vector (G_ADDRES_SIZE - 1 downto 0);
    avm_read_master_readdata : in std_logic_vector (G_DATA_SIZE - 1 downto 0);
    avm_read_master_waitrequest : in std_logic;



    --Avalon slave signals: (control from HPS)

    avs_csr_address : in std_logic_vector (1 downto 0);
    avs_csr_readdata : out std_logic_vector (G_DATA_SIZE - 1 downto 0);
    avs_csr_write : in std_logic;
    avs_csr_writedata : in std_logic_vector (G_DATA_SIZE - 1 downto 0); --nwm czy to wszystko


    --
    irq : out std_logic

  );
  end DMAC_top;


architecture DMAC_top_rtl of DMAC_top is



  --
  signal writeAddress_reg : std_logic_vector(G_ADDRES_SIZE - 1 downto 0);
  signal readAddress_reg : std_logic_vector(G_ADDRES_SIZE - 1 downto 0);
  signal dmaStatus_reg : std_logic_vector(G_ADDRES_SIZE - 1 downto 0);
  signal dmaControl_reg : std_logic_vector(G_ADDRES_SIZE - 1 downto 0);

  --transferLength - first 16bit (msb) of control register
  signal transferLength : unsigned(G_DATA_SIZE/2 - 1 downto 0);

  -- fifo signals
  signal writeDataToFifo : std_logic_vector(G_DATA_SIZE - 1 downto 0);
  signal readDataFromFifo : std_logic_vector(G_DATA_SIZE - 1 downto 0);
  signal fifoFull : std_logic;
  signal fifoEmpty : std_logic;
  signal writeFifoRequest : std_logic;
  signal readFifoRequest : std_logic;

  --sygnaly pomicnicze do trzymana wartosci adresow
  signal readAddress : unsigned(G_ADDRES_SIZE - 1 downto 0) := (others => '0');
  signal writeAddress : unsigned(G_ADDRES_SIZE - 1 downto 0) := (others => '0');

  signal readWordsCounter_cnt : unsigned(G_DATA_COUNTER_SIZE - 1 downto 0);
  signal writeWordsCounter_cnt: unsigned(G_DATA_COUNTER_SIZE - 1 downto 0) := (others => '0');

  signal irq_sig : std_logic := '0';
  signal irq_request : std_logic := '0';
  signal irq_clean : std_logic := '0';
  signal runFlag : std_logic := '0';
  signal finishedBlock : std_logic := '0';

  signal startTransfer : std_logic := '0';

  --state machines
  type read_SM is (IDLE, READING,END_OF_TRANSFER,END_OF_TRANSFER_2,END_OF_TRANSFER_3);
  type write_SM is (IDLE,FIRST,CHECK,WAIT_FIFO,WAIT_FIFO_2,WRITING, END_OF_TRANSFER);
  signal readCurrentState : read_SM;
  signal writeCurrentState: write_SM;


  --to status register
  signal activeFlag : std_logic;
  signal finishedFlag : std_logic;

  signal writeEnabled : std_logic;
  signal temp_avm_write_master_waitrequest : std_logic;

	signal avm_write_master_waitrequestFF : std_logic;
	signal readFifoRequestFF : std_logic;
	signal readFifoRequestFF2 : std_logic;

	signal writeFifoRequestFF : std_logic;
	signal writeFifoRequestFF2 : std_logic;
	signal writeFifoRequestFF3 : std_logic;

  signal firstWriteFlag : std_logic := '1';




	signal tempCounter : unsigned(G_DATA_SIZE - 1 downto 0) := (others => '0');

  begin


    --fifo na dane z read do write
    fifo_buffer : entity work.ShowAheadFifo(SYN)
    port map(
      --aclr => i_reset,
      data => avm_read_master_readdata,
      rdclk => i_clk,
      rdreq => readFifoRequest,
      wrclk => i_clk,
      wrreq => writeFifoRequest,
      q => avm_write_master_writedata,
      rdempty => fifoEmpty,
      wrfull => fifoFull
    );


    --read state machine
    process (i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(i_reset = '1') then
          --reset powrot do idla
          readAddress <= (others => '0');
          readCurrentState <= IDLE;
          readWordsCounter_cnt <= (others => '0');

        else
          
          case readCurrentState is

            when IDLE =>
              if(runFlag = '1') then
                readAddress <= unsigned(readAddress_reg);
                transferLength <= unsigned(dmaControl_reg(G_DATA_SIZE - 1 downto 16));
                readCurrentState <= READING;
                readWordsCounter_cnt <= (others => '0');
              else
                readCurrentState <= IDLE;
                readWordsCounter_cnt <= (others => '0');
              end if;
            


            when READING =>
                

              if(readWordsCounter_cnt < transferLength) then

                if(avm_read_master_waitrequest = '0' and fifoFull = '0') then
                  
                  readWordsCounter_cnt <= readWordsCounter_cnt + 1;

									readAddress <= readAddress + 4;

                  readCurrentState <= READING;
              
                else
                  readWordsCounter_cnt <= readWordsCounter_cnt;
                  readAddress <= readAddress;
                  readCurrentState <= READING;

                end if;


              else
                
                readCurrentState <= END_OF_TRANSFER;

              end if;

            when END_OF_TRANSFER =>

              readCurrentState <= END_OF_TRANSFER_2;

            when END_OF_TRANSFER_2 =>
              readCurrentState <= END_OF_TRANSFER_3;

            when END_OF_TRANSFER_3 =>
              readCurrentState <= IDLE;

            when others => 
                
              readCurrentState <= IDLE;

          end case;
        end if;
      end if;
    end process;

		process(i_clk)
		begin
			if(rising_edge(i_clk)) then
				writeFifoRequestFF <= writeFifoRequest;
				writeFifoRequestFF2 <= writeFifoRequestFF;
				writeFifoRequestFF3 <= writeFifoRequestFF2;

			end if;
		end process;

    avm_read_master_read <= '1' when readCurrentState = READING and fifoFull = '0' else '0';

    writeFifoRequest <= '1' when readCurrentState = READING and fifoFull = '0' and avm_read_master_waitrequest = '0' else '0';

    avm_read_master_address <= std_logic_vector(readAddress);


    
write_FSM: process (i_clk, i_reset)
begin
	if( i_reset = '1') then
		writeCurrentState <= idle;
    writeWordsCounter_cnt <= (others => '0');

	elsif (rising_edge(i_clk)) then


		case writeCurrentState is

			when idle =>
				if runFlag = '1' then
					writeCurrentState <= WRITING;
					writeAddress <= unsigned(writeAddress_reg);
          irq_request <= '0';
          startTransfer <= '1';
          finishedFlag <= '0';
				else
					irq_request <= '0';
					writeCurrentState <= idle;
					startTransfer <= '0';
          finishedFlag <= '0';
          writeWordsCounter_cnt <= (others => '0');
				end if;

			when WRITING =>

        if fifoEmpty = '1' and readCurrentState = IDLE then
          writeCurrentState <= END_OF_TRANSFER;
          irq_request <= '1'; --info o koncu transmisji (interrupt)
          finishedFlag <= '1';
          startTransfer <= '0';

        else
          
          	if avm_write_master_waitrequest /= '1' and fifoEmpty /= '1' then
					  writeAddress <= writeAddress + 4;  
            writeCurrentState <= WRITING;

            writeWordsCounter_cnt <= writeWordsCounter_cnt + 1;

          else
            writeAddress <= writeAddress;  
            writeCurrentState <= WRITING;

            writeWordsCounter_cnt <= writeWordsCounter_cnt;

				  end if;
        end if;

          
				
      when END_OF_TRANSFER => 
        writeCurrentState <= idle;

      when others =>
          writeCurrentState <= idle;
		end case;
	end if;
end process;
  



    avm_write_master_write <= '1' when writeCurrentState = WRITING and fifoEmpty = '0'  else '0';

    avm_write_master_address <= std_logic_vector(writeAddress);
    readFifoRequest <= '1' when writeCurrentState = WRITING and fifoEmpty = '0' and avm_write_master_waitrequest = '0'  else '0';

    
   
		process(i_clk)
		begin
			if(rising_edge(i_clk)) then
				avm_write_master_waitrequestFF <= avm_write_master_waitrequest;
				readFifoRequestFF <= readFifoRequest;
				readFifoRequestFF2 <= readFifoRequestFF;
			end if;
		end process;


    process(i_clk)
		begin
			if(rising_edge(i_clk)) then
        if(readFifoRequest = '1') then
          firstWriteFlag <= '0';
        else
          firstWriteFlag <= firstWriteFlag;
        end if;

			end if;
		end process;
		



    
    process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(i_reset = '1') then
          irq_clean <= '0';
        else
          if(dmaControl_reg(2) = '1') then
            irq_clean <= '1';
          else
            irq_clean <= '0';
          end if; 
        end if;
      end if;
    end process;


    --control/status regs
    process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(i_reset = '1') then
          writeAddress_reg <= (others => '0');
          readAddress_reg <= (others => '0');
        else
          if(avs_csr_write = '1') then --to sygnal idacy z controlRega z HPS
            case avs_csr_address is
              when "10" =>
                readAddress_reg <= avs_csr_writedata (31 downto 0) ;
              when "11" =>
                writeAddress_reg <= avs_csr_writedata (31 downto 0) ;
              when "00" => --control, 
                dmaControl_reg <= avs_csr_writedata;
              when others =>
              -- 
            end case;
          end if;
        end if;
      end if;
    end process;



    process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(i_reset = '1') then
          --
          runFlag <= '0';
        else
          if(dmaControl_reg(0) = '1' and finishedBlock = '0' and dmaStatus_reg(0) = '0') then
            runFlag <= '1';
          else
            runFlag <= '0';
          end if;
        end if;
      end if;
    end process;

    activeFlag <= '0' when readCurrentState = idle and writeCurrentState = idle else '1';

    dmaStatus_reg(0) <= activeFlag;
    dmaStatus_reg(1) <= finishedBlock;

    --przestawienie flagi blokujacej ponowne pisanie
    process(i_clk)
    begin
      if(rising_edge(i_clk)) then
        if(i_reset = '1') then
          finishedBlock <= '0';
        else
          --if(irq_clean =)
          if( irq_clean = '1') then
            finishedBlock <= '0';
          elsif(startTransfer = '1') then
            finishedBlock <= '1';
          else
            finishedBlock <= finishedBlock;
          end if;
        end if;
      end if;
    end process;


    read_mux: process (avs_csr_address, dmaStatus_Reg, readAddress_reg, writeAddress_reg)
    begin
	    case avs_csr_address is
		    when "10" =>
			    avs_csr_readdata <= readAddress_reg;
		    when "11" =>
			    avs_csr_readdata <= writeAddress_reg;
		    when others =>
			    avs_csr_readdata <= dmaStatus_Reg;
	    end case;
    end process;


    proc_name: process(i_clk)
    begin
      if rising_edge(i_clk) then
        if( irq_request = '1' and irq_clean ='0') then
          irq_sig <= '1';
        elsif(irq_clean = '1') then
          irq_sig <= '0';
        end if;
      end if;
    end process;
          
    irq <= irq_sig;



        
end DMAC_top_rtl; 





