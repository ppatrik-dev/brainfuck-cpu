-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Patrik Prochazka <xprochp00@stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	----------------- CPU SIGNALS ------------------	

	-- PC signals
	signal pc_reg	: std_logic_vector(12 downto 0);
	signal pc_inc	: std_logic;
	signal pc_dec 	: std_logic;	
	
	-- PTR signals
	signal ptr_reg	: std_logic_vector(12 downto 0);
	signal ptr_inc	: std_logic;
    signal ptr_dec	: std_logic;	

	-- TMP signals
    signal tmp_reg	: std_logic_vector(7 downto 0);
    signal tmp_ld	: std_logic;
	
	-- CNT signals
	signal cnt_reg 	: std_logic_vector(11 downto 0);
	signal cnt_inc  : std_logic;
	signal cnt_dec  : std_logic;

	-- MX1 signals
	signal mx1_out 	: std_logic_vector(12 downto 0);
	signal mx1_sel	: std_logic;
	
	-- MX2 signals
	signal mx2_out 	: std_logic_vector(7 downto 0);
	signal mx2_sel	: std_logic_vector(1 downto 0);
	
		
	----------------- FINITE STATE MACHINE -----------------	

	-- FSM states
	type fsm_state is (
		----------------- Processor states -----------------
		sidle, sinit0, sinit1, sfetch, sdecode, snop, shalt,
		
		------------- Instruction Execute states -----------
      	sptr_inc, sptr_dec,
 
		smem_inc0, smem_inc1,
		smem_dec0, smem_dec1,

		stmp_load0, stmp_load1, stmp_store,

		smem_output0, smem_output1,		
		smem_input0, smem_input1,
		
		sloop_beg0, sloop_beg1, sloop_beg2, sloop_beg3, sloop_beg4,
		sloop_end0, sloop_end1, sloop_end2, sloop_end3, sloop_end4
	);
	
	-- FSM signals	
	signal pstate : fsm_state;
	signal nstate : fsm_state;		

begin

	-------------------- CPU COMPONENTS --------------------	
	
	---------------- PC ----------------
	program_counter: process(RESET, CLK)
	begin
		if (RESET = '1') then
			pc_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if (pc_inc = '1') then
				pc_reg <= pc_reg + 1;
			elsif (pc_dec = '1') then
				pc_reg <= pc_reg - 1;
			end if;
		end if;			
	end process;

	
	--------------- PTR ---------------
	memory_pointer: process(RESET, CLK)
	begin
		if (RESET = '1') then
			ptr_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if (ptr_inc = '1') then
				if (ptr_reg = "1111111111111") then
					ptr_reg <= (others => '0');
				else
					ptr_reg <= ptr_reg + 1;
				end if;
			elsif (ptr_dec = '1') then
				if (ptr_reg = "0000000000000") then
					ptr_reg <= (others => '1');
				else
					ptr_reg <= ptr_reg - 1;
				end if;
			end if; 
		end if;
	end process;
	
	
	---------------- TMP ------------------
	temporary_variable: process(RESET, CLK)
	begin
		if (RESET = '1') then
			tmp_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if (tmp_ld = '1') then
				tmp_reg <= DATA_RDATA;
			end if;
		end if;
	end process;

	--------------- CNT ----------------
	bracket_counter: process(RESET, CLK)
	begin
		if (RESET = '1') then
			cnt_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if (cnt_inc = '1') then
				cnt_reg <= cnt_reg + 1;
			elsif (cnt_dec = '1') then
				cnt_reg <= cnt_reg - 1;
			end if;
		end if;
	end process;
	
	---------------------- MX1 -----------------------
	mx1_out <= pc_reg when mx1_sel = '1' else ptr_reg;
	
	-- addressing signal
	DATA_ADDR <= mx1_out;
	
	--------------- MX2 -------------
	with mx2_sel select
		mx2_out <= 
			IN_DATA when "10",
			DATA_RDATA + 1 when "01",
			DATA_RDATA - 1 when "11",
			tmp_reg when others;
	
	-- writing signal			  
	DATA_WDATA <= mx2_out;

	--------------------- FINITE STATE MACHINE ---------------------
	
	---- Present State register ---
	pstate_reg: process(RESET, CLK)
	begin
		if (RESET = '1') then
			pstate <= sidle;
		elsif rising_edge(CLK) then
			if (EN = '1') then
				pstate <= nstate;
			end if;
		end if;
	end process;

	----------------------- Next State logic ----------------------
	nstate_logic: process(pstate, EN, DATA_RDATA, IN_VLD, OUT_BUSY)
	begin
				
		---------------- INIT SIGNALS ----------------	

		-- DATA signals
		DATA_RDWR <= '0';
		DATA_EN <= '0';
	 	
		-- I/O signals
		IN_REQ <= '0';
		OUT_INV <= '0';
		OUT_WE <= '0';
		OUT_DATA <= X"00";		
		
		-- PC signals
		pc_inc <= '0';
		pc_dec <= '0';
		
		-- PTR signals
		ptr_inc <= '0';
		ptr_dec <= '0';
				
		-- TMP signals
		tmp_ld <= '0';
		
		-- CNT signals		
		cnt_inc <= '0';
		cnt_dec <= '0';
		
		-- MX1 signals
		mx1_sel <= '0';
		
		-- MX2 signals
		mx2_sel <= "00";
				
		case pstate is
			
			------------------------- IDLE ------------------------
			when sidle =>
				-- RESET=1 -> remain in idle state
				READY <= '0';
				DONE <= '0';
				nstate <= sinit0;
			
			------------------------- INIT ------------------------
			when sinit0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';
				nstate <= sinit1;

			when sinit1 =>
				ptr_inc <= '1';				
				
				-- found program-data separator -> PTR=PTR+1
				if (DATA_RDATA = X"40") then
					READY <= '1';
					nstate <= sfetch;
				else
					nstate <= sinit0;
				end if;	
				
			------------------------- FETCH ------------------------
			when sfetch =>
				-- read mem[PC]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '1';
				nstate <= sdecode;
			
			------------------------ DECODE ------------------------
			when sdecode =>
				case DATA_RDATA is
					when X"3E" => nstate <= sptr_inc; 		-- >
					when X"3C" => nstate <= sptr_dec; 	 	-- <
					
					when X"2B" => nstate <= smem_inc0;	 	-- +
					when X"2D" => nstate <= smem_dec0;	 	-- -
					
					when X"5B" => nstate <= sloop_beg0;		-- [
					when X"5D" => nstate <= sloop_end0;  	-- ]
			
					when X"24" => nstate <= stmp_load0;	 	-- $
					when X"21" => nstate <= stmp_store; 	-- !
			
					when X"2E" => nstate <= smem_output0;	-- .
					when x"2C" => nstate <= smem_input0; 	-- ,
					
					when X"40" => nstate <= shalt;		 	-- @
					
					when others => nstate <= snop;		 	-- others
				end case;

			------------------------ PTR_INC ------------------------
			when sptr_inc =>
				-- increment PTR
				pc_inc <= '1';
				ptr_inc <= '1';
				nstate <= sfetch;
			
			------------------------ PTR_DEC ------------------------
			when sptr_dec =>
				-- decrement PTR
				pc_inc <= '1';
				ptr_dec <= '1';
				nstate <= sfetch;
			
			------------------------ MEM_INC ------------------------
			when smem_inc0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';
				nstate <= smem_inc1;
				
			when smem_inc1 =>
				-- write mem[PTR]+1
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '0';
				mx2_sel <= "01";
				pc_inc <= '1';
				nstate <= sfetch;
			
			------------------------ MEM_DEC ------------------------
			when smem_dec0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';
				nstate <= smem_dec1;

			when smem_dec1 =>
				-- write mem[PTR]-1
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '0';
				mx2_sel <= "11";
				pc_inc <= '1';
				nstate <= sfetch;	
			
			------------------------ TMP_LOAD -----------------------
			when stmp_load0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';
				nstate <= stmp_load1;
			
			when stmp_load1 =>
				-- load value -> TMP=mem[PTR]
				tmp_ld <= '1';
				pc_inc <= '1';
				nstate <= sfetch;			
				
			----------------------- TMP_STORE ----------------------
			when stmp_store =>
				-- store value -> mem[PTR]=TMP
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '0';
				mx2_sel <= "00";
				pc_inc <= '1';
				nstate <= sfetch;
	
			----------------------- MEM_OUTPUT ---------------------
			when smem_output0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';
				nstate <= smem_output1; 
			
			when smem_output1 =>
				-- I/O busy -> wait
				if (OUT_BUSY = '1') then
					nstate <= smem_output0;
				
				-- enable I/O write and output data
				else
					OUT_WE <= '1';
					OUT_DATA <= DATA_RDATA;
					pc_inc <= '1';
					nstate <= sfetch;
				end if;			
			
			----------------------- MEM_INPUT ----------------------
			when smem_input0 =>
				-- request input data
				IN_REQ <= '1';
				nstate <= smem_input1;
						
			when smem_input1 =>
				-- valid input data -> mem[PTR]=data
				if (IN_VLD = '1') then
					IN_REQ <= '1';
					DATA_EN <= '1';
					DATA_RDWR <= '0';
					mx1_sel <= '0';
					mx2_sel <= "10";
					pc_inc <= '1';
					nstate <= sfetch;				
				else
					nstate <= smem_input0;
				end if;

			---------------------- LOOP_BEGIN ----------------------
			when sloop_beg0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';		
				nstate <= sloop_beg1;
			
			when sloop_beg1 =>	
				-- mem[ptr]==0 -> skip all instructions inside loop
				if (DATA_RDATA = "00000000") then
					cnt_inc <= '1';
					pc_inc <= '1';
					nstate <= sloop_beg2;
				else
					pc_inc <= '1';
					nstate <= sfetch;
				end if;

			when sloop_beg2 =>
				-- read mem[PC]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '1';
				nstate <= sloop_beg3;
			
			when sloop_beg3 =>
				-- found begin of loop -> increase CNT 
				if (DATA_RDATA = X"5B") then
					cnt_inc <= '1';
				-- found end of loop -> decrease CNT
				elsif (DATA_RDATA = X"5D") then
					cnt_dec <= '1';
				end if;		
		
				nstate <= sloop_beg4;	
				
			when sloop_beg4 =>
				-- CNT==0 -> F-D-E next instruction
				if (cnt_reg = "000000000000") then
					pc_inc <= '1';
					nstate <= sfetch;
				else
					pc_inc <= '1';
					nstate <= sloop_beg2;
				end if;				
				
			----------------------- LOOP_END ----------------------
			when sloop_end0 =>
				-- read mem[PTR]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';
				nstate <= sloop_end1;
			
			when sloop_end1 =>
				-- mem[PTR]==0 -> F-D-E next instruction
				if (DATA_RDATA = "00000000") then
					pc_inc <= '1';
					nstate <= sfetch;
				else
					cnt_inc <= '1';
					pc_dec <= '1';
					nstate <= sloop_end2;
				end if;

			when sloop_end2 =>
				-- read mem[PC]
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '1';
				nstate <= sloop_end3;
				
			when sloop_end3 =>
				-- found end of loop -> increase CNT
				if (DATA_RDATA = X"5D") then
					cnt_inc <= '1';
				-- found begin of loop -> decrease CNT
				elsif (DATA_RDATA = X"5B") then
					cnt_dec <= '1';
				end if;
				
				nstate <= sloop_end4;			

			when sloop_end4 =>
				-- CNT==0 -> F-D-E next instruction
				if (cnt_reg = "000000000000") then
					pc_inc <= '1';
					nstate <= sfetch;
				else
					pc_dec <= '1';
					nstate <= sloop_end2;
				end if;
				
			-------------------------- NOP ---------------------------
			when snop => 
				-- skip this (no)instruction -> F-D-E next instruction
				pc_inc <= '1';
				nstate <= sfetch;
			
			-------------------------- HALT -------------------------
			when shalt =>
				-- set DONE signal and processor remain in halt state
				DONE <= '1';
				nstate <= shalt;
		
		end case;

	end process;

end behavioral;
