--  
-- Copyright (c) 2018 Allmine Inc
-- OrphanedGland (wilhelm.klink@gmail.com)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity luffa512_ce is
port (
  clk                                   : in std_logic;
  clk_en                                : in std_logic;
  reset                                 : in std_logic;
  start                                 : in std_logic;
  pause                                 : in std_logic;
  data_in                               : in std_logic_vector(511 downto 0);
  hash                                  : out std_logic_vector(511 downto 0);
  hash_new                              : out std_logic;
  hash_almost_new                       : out std_logic;
  busy_n                                : out std_logic
);
end entity luffa512_ce;

architecture luffa512_ce_rtl of luffa512_ce is
  
  alias slv is std_logic_vector;
  
  component luffa512_mi_ce is
  port (
    clk                                 : in std_logic;
    clk_en                              : in std_logic;
    reset                               : in std_logic;
    start                               : in std_logic;
    d_in                                : in std_logic_vector(255 downto 0);
    x_in                                : in std_logic_vector(1279 downto 0);
    x_out                               : out std_logic_vector(1279 downto 0);
    x_new                               : out std_logic
  );
  end component luffa512_mi_ce;
  
  component luffa512_p_ce is
  port (
    clk                                 : in std_logic;
    clk_en                              : in std_logic;
    reset                               : in std_logic;
    start                               : in std_logic;
    x_in                                : in std_logic_vector(1279 downto 0);
    x_out                               : out std_logic_vector(1279 downto 0);
    x_new                               : out std_logic
  );
  end component luffa512_p_ce;
  
  subtype word64 is slv(63 downto 0);
  subtype word32 is slv(31 downto 0);
  subtype uword64 is unsigned(63 downto 0);
  subtype uword32 is unsigned(31 downto 0);
  type luffa512_state is (IDLE, MI1, P1, MI2, P2, MI3, P3, MI4, P4, MI5, P5, FINISH);
                        
  constant zeros64 : word64 := (others => '0');
  constant zeros32 : word32 := (others => '0');
    
  function endian_swap64(x: word64) return word64 is
  begin
    return word64(x(7 downto 0)   & x(15 downto 8)  & x(23 downto 16) & x(31 downto 24) &
                  x(39 downto 32) & x(47 downto 40) & x(55 downto 48) & x(63 downto 56));
  end endian_swap64;

  function endian_swap32(x: word32) return word32 is
  begin
    return word32(x(7 downto 0)   & x(15 downto 8)  & x(23 downto 16) & x(31 downto 24));
  end endian_swap32;
  
  function shr64(x: word64; n: natural) return word64 is
  begin
    return word64(zeros64(n-1 downto 0) & x(x'high downto n));
  end shr64;
  
  function shr32(x: word32; n: natural) return word32 is
  begin
    return word32(zeros32(n-1 downto 0) & x(x'high downto n));
  end shr32;
  
  function shl64(x: word64; n: natural) return word64 is
  begin
    return word64(x(x'high-n downto 0) & zeros64(x'high downto x'length-n));
  end shl64;

  function shl32(x: word32; n: natural) return word32 is
  begin
    return word32(x(x'high-n downto 0) & zeros32(x'high downto x'length-n));
  end shl32;
  
  function rotr64(x: word64; n: natural) return word64 is
  begin
    return word64(x(n-1 downto 0) & x(x'high downto n));
  end rotr64;
  
  function rotr32(x: word32; n: natural) return word32 is
  begin
    return word32(x(n-1 downto 0) & x(x'high downto n));
  end rotr32;
  
  function rotl64(x: word64; n: natural) return word64 is
  begin
    return word64(x(x'high-n downto 0) & x(x'high downto x'length-n));
  end rotl64;
  
  function rotl32(x: word32; n: natural) return word32 is
  begin
    return word32(x(x'high-n downto 0) & x(x'high downto x'length-n));
  end rotl32;

  type word64_array8 is array(0 to 7) of word64;
  type word64_array4 is array(0 to 3) of word64;
  type word64_array2 is array(0 to 1) of word64;
  type word32_array40 is array(0 to 39) of word32;
  type word32_array16 is array(0 to 15) of word32;
  type word32_array8 is array(0 to 7) of word32;
  type word32_array4 is array(0 to 3) of word32;
  type word32_array2 is array(0 to 1) of word32;
  
  function mix_word64(x: word64_array2) return word64_array2 is
    variable x2                         : word64_array2;
  begin
    x2(0)                               := x(0);
    x2(1)                               := x(0) xor x(1);
    x2(0)(31 downto 0)                  := rotl32(x2(0)(31 downto 0),2) xor x2(1)(31 downto 0);
    x2(1)(31 downto 0)                  := rotl32(x2(1)(31 downto 0),14) xor x2(0)(31 downto 0);
    x2(0)(31 downto 0)                  := rotl32(x2(0)(31 downto 0),10) xor x2(1)(31 downto 0);
    x2(1)(31 downto 0)                  := rotl32(x2(1)(31 downto 0),1);
    x2(0)(63 downto 32)                 := rotl32(x2(0)(63 downto 32),2) xor x2(1)(63 downto 32);
    x2(1)(63 downto 32)                 := rotl32(x2(1)(63 downto 32),14) xor x2(0)(63 downto 32);
    x2(0)(63 downto 32)                 := rotl32(x2(0)(63 downto 32),10) xor x2(1)(63 downto 32);
    x2(1)(63 downto 32)                 := rotl32(x2(1)(63 downto 32),1);
    return x2;
  end mix_word64;
  
  function mix_word32(x: word32_array2) return word32_array2 is
    variable x2                         : word32_array2;
  begin
    x2(0)                               := x(0);
    x2(1)                               := x(0) xor x(1);
    x2(0)                               := rotl32(x2(0),2) xor x2(1);
    x2(1)                               := rotl32(x2(1),14) xor x2(0);
    x2(0)                               := rotl32(x2(0),10) xor x2(1);
    x2(1)                               := rotl32(x2(1),1);
    return x2;
  end mix_word32;
  
  function sub_crumb64(x: word64_array4) return word64_array4 is
    variable x2                         : word64_array4;
    variable t                          : word64;
  begin
    t                                   := x(0);
    x2(0)                               := x(0) or x(1);
    x2(2)                               := x(2) xor x(3);
    x2(1)                               := not x(1);
    x2(0)                               := x2(0) xor x(3);
    x2(3)                               := x(3) and t;
    x2(1)                               := x2(1) xor x2(3);
    x2(3)                               := x2(3) xor x2(2);
    x2(2)                               := x2(2) and x2(0);
    x2(0)                               := not x2(0);
    x2(2)                               := x2(2) xor x2(1);
    x2(1)                               := x2(1) or x2(3);
    t                                   := t xor x2(1);
    x2(3)                               := x2(3) xor x2(2);
    x2(2)                               := x2(2) and x2(1);
    x2(1)                               := x2(1) xor x2(0);
    x2(0)                               := t;
    return x2;
  end sub_crumb64;
  
  function sub_crumb32(x: word32_array4) return word32_array4 is
    variable x2                         : word32_array4;
    variable t                          : word32;
  begin
    t                                   := x(0);
    x2(0)                               := x(0) or x(1);
    x2(2)                               := x(2) xor x(3);
    x2(1)                               := not x(1);
    x2(0)                               := x2(0) xor x(3);
    x2(3)                               := x(3) and t;
    x2(1)                               := x2(1) xor x2(3);
    x2(3)                               := x2(3) xor x2(2);
    x2(2)                               := x2(2) and x2(0);
    x2(0)                               := not x2(0);
    x2(2)                               := x2(2) xor x2(1);
    x2(1)                               := x2(1) or x2(3);
    t                                   := t xor x2(1);
    x2(3)                               := x2(3) xor x2(2);
    x2(2)                               := x2(2) and x2(1);
    x2(1)                               := x2(1) xor x2(0);
    x2(0)                               := t;
    return x2;
  end sub_crumb32;
    
  function tweak(x: word32_array40) return word32_array40 is
    variable x2                         : word32_array40;
  begin
    x2                                  := x;
    x2(12)                              := rotl32(x2(12),1);
    x2(13)                              := rotl32(x2(13),1);
    x2(14)                              := rotl32(x2(14),1);
    x2(15)                              := rotl32(x2(15),1);
    x2(20)                              := rotl32(x2(20),2);
    x2(21)                              := rotl32(x2(21),2);
    x2(22)                              := rotl32(x2(22),2);
    x2(23)                              := rotl32(x2(23),2);
    x2(28)                              := rotl32(x2(28),3);
    x2(29)                              := rotl32(x2(29),3);
    x2(30)                              := rotl32(x2(30),3);
    x2(31)                              := rotl32(x2(31),3);
    x2(36)                              := rotl32(x2(36),4);
    x2(37)                              := rotl32(x2(37),4);
    x2(38)                              := rotl32(x2(38),4);
    x2(39)                              := rotl32(x2(39),4);
    return x2;
  end tweak;
  
  constant RCW010                       : word64_array8 := (X"b6de10ed303994a6", X"70f47aaec0e65299",
                                                            X"0707a3d46cc33a12", X"1c1e8f51dc56983e",
                                                            X"707a3d451e00108f", X"aeb285627800423d",
                                                            X"baca15898f5b7882", X"40a46f3e96e1db12");
  constant RCW014                       : word64_array8 := (X"01685f3de0337818", X"05a17cf4441ba90d",
                                                            X"bd09caca7f34d442", X"f4272b289389217f",
                                                            X"144ae5cce5a8bce6", X"faa7ae2b5274baf4",
                                                            X"2e48f1c126889ba7", X"b923c7049a226e9d");
  constant RCW230                       : word64_array8 := (X"b213afa5fc20d9d2", X"c84ebe9534552e25",
                                                            X"4e608a227ad8818f", X"56d858fe8438764a",
                                                            X"343b138fbb6de032", X"d0ec4e3dedb780c8",
                                                            X"2ceb4882d9847356", X"b3ad2208a2c78434");
  constant RCW234                       : word64_array8 := (X"e028c9bfe25e72c1", X"44756f91e623bb72",
                                                            X"7e8fce325c58a4a4", X"956548be1e38e2e7",
                                                            X"fe191be278e38b9d", X"3cb226e527586719",
                                                            X"5944a28e36eda57f", X"a1c4c355703aace7");
  constant RC40                         : word32_array8 := (X"f0d2e9e3",X"ac11d7fa",
                                                            X"1bcb66f2",X"6f2d9bc9",
                                                            X"78602649",X"8edae952",
                                                            X"3b6ba548",X"edae9520");
  constant RC44                         : word32_array8 := (X"5090d577",X"2d1925ab",
                                                            X"b46496ac",X"d1925ab0",
                                                            X"29131ab6",X"0fc053c3",
                                                            X"3f014f0c",X"fc053c31");

  function p(x: word32_array40) return word32_array40 is
    variable x2                         : word32_array40;
    variable w                          : word64_array8;
  begin
    x2                                  := tweak(x);
    for i in 0 to 7 loop
      w(i)                              := x2(8+i) & x2(i);
    end loop;
    for i in 0 to 7 loop
      (w(0),w(1),w(2),w(3))             := sub_crumb64((w(0),w(1),w(2),w(3)));
      (w(5),w(6),w(7),w(4))             := sub_crumb64((w(5),w(6),w(7),w(4)));
      (w(0),w(4))                       := mix_word64((w(0),w(4)));
      (w(1),w(5))                       := mix_word64((w(1),w(5)));
      (w(2),w(6))                       := mix_word64((w(2),w(6)));
      (w(3),w(7))                       := mix_word64((w(3),w(7)));
      w(0)                              := w(0) xor RCW010(i);
      w(4)                              := w(4) xor RCW014(i);
    end loop;    
    for i in 0 to 7 loop
      x2(i)                             := w(i)(31 downto 0);
      x2(8+i)                           := w(i)(63 downto 32);
    end loop;
    for i in 0 to 7 loop
      w(i)                              := x2(24+i) & x2(16+i);
    end loop;
    for i in 0 to 7 loop
      (w(0),w(1),w(2),w(3))             := sub_crumb64((w(0),w(1),w(2),w(3)));
      (w(5),w(6),w(7),w(4))             := sub_crumb64((w(5),w(6),w(7),w(4)));
      (w(0),w(4))                       := mix_word64((w(0),w(4)));
      (w(1),w(5))                       := mix_word64((w(1),w(5)));
      (w(2),w(6))                       := mix_word64((w(2),w(6)));
      (w(3),w(7))                       := mix_word64((w(3),w(7)));
      w(0)                              := w(0) xor RCW230(i);
      w(4)                              := w(4) xor RCW234(i);
    end loop;
    for i in 0 to 7 loop
      x2(16+i)                          := w(i)(31 downto 0);
      x2(24+i)                          := w(i)(63 downto 32);
    end loop;
    for i in 0 to 7 loop
      (x2(32),x2(33),x2(34),x2(35))     := sub_crumb32((x2(32),x2(33),x2(34),x2(35)));
      (x2(37),x2(38),x2(39),x2(36))     := sub_crumb32((x2(37),x2(38),x2(39),x2(36)));
      (x2(32),x2(36))                   := mix_word32((x2(32),x2(36)));
      (x2(33),x2(37))                   := mix_word32((x2(33),x2(37)));
      (x2(34),x2(38))                   := mix_word32((x2(34),x2(38)));
      (x2(35),x2(39))                   := mix_word32((x2(35),x2(39)));
      x2(32)                            := x2(32) xor RC40(i);
      x2(36)                            := x2(36) xor RC44(i);
    end loop;
    return x2;
  end p;
  
  constant IV                           : word32_array40 := (X"6d251e69", X"44b051e0",
                                                             X"4eaa6fb4", X"dbf78465",
                                                             X"6e292011", X"90152df4",
                                                             X"ee058139", X"def610bb",
                                                             X"c3b44b95", X"d9d2f256",
                                                             X"70eee9a0", X"de099fa3",
                                                             X"5d9b0557", X"8fc944b3",
                                                             X"cf1ccf0e", X"746cd581",
                                                             X"f7efc89d", X"5dba5781",
                                                             X"04016ce5", X"ad659c05",
                                                             X"0306194f", X"666d1836",
                                                             X"24aa230a", X"8b264ae7",
                                                             X"858075d5", X"36d79cce",
                                                             X"e571f7d7", X"204b1f67",
                                                             X"35870c6a", X"57e9e923",
                                                             X"14bcb808", X"7cde72ce",
                                                             X"6c68e9be", X"5ec41e22",
                                                             X"c825b7c7", X"affb4363",
                                                             X"f5df3999", X"0fc688f1",
                                                             X"b07224cc", X"03e86cea");
  constant PADDING                      : word32_array8 := (X"00000000",X"00000000",
                                                            X"00000000",X"00000000",
                                                            X"00000000",X"00000000",
                                                            X"00000000",X"00000080");
  constant ZEROS_WORD32_ARRAY8          : word32_array8 := (others => zeros32);
  signal luffa512_state_next            : luffa512_state;
  signal data_in_array                  : word32_array16;
  signal mi_start                       : std_logic;
  signal mi_d_in                        : slv(255 downto 0);
  signal mi_d_in_array                  : word32_array8;
  signal mi_x_in                        : slv(1279 downto 0);
  signal mi_x_in_array                  : word32_array40;
  signal mi_x_out                       : slv(1279 downto 0);
  signal mi_x_out_array                 : word32_array40;
  signal mi_x_new                       : std_logic;
  signal p_start                        : std_logic;  
  signal p_x_in                         : slv(1279 downto 0);
  signal p_x_in_array                   : word32_array40;
  signal p_x_out                        : slv(1279 downto 0);
  signal p_x_out_array                  : word32_array40;
  signal p_x_new                        : std_logic;
  signal x                              : word32_array40;
  signal h                              : word32_array40;
  signal done                           : std_logic;
  signal almost_done                    : std_logic;
  
  signal q_luffa512_state               : luffa512_state;
  signal q_x                            : word32_array40;
  signal q_h                            : word32_array40;
  
begin

  hash_new                              <= done;
  hash_almost_new                       <= almost_done;
  
  output_mapping : for i in 0 to 15 generate
    hash((i+1)*32-1 downto i*32)        <= q_h(i);
  end generate output_mapping;
  
  input_mapping : for i in 0 to 15 generate
    data_in_array(i)                    <= data_in((i+1)*32-1 downto i*32);
  end generate input_mapping;
  
  array8_mapping : for i in 0 to 7 generate
      mi_d_in((i+1)*32-1 downto i*32)   <= mi_d_in_array(i);
  end generate array8_mapping;
  
  array40_mapping : for i in 0 to 39 generate
    mi_x_in((i+1)*32-1 downto i*32)     <= mi_x_in_array(i);
    mi_x_out_array(i)                   <= mi_x_out((i+1)*32-1 downto i*32);
    p_x_in((i+1)*32-1 downto i*32)      <= p_x_in_array(i);
    p_x_out_array(i)                    <= p_x_out((i+1)*32-1 downto i*32);    
  end generate array40_mapping;
  
  luffa512_mi_inst : luffa512_mi_ce
  port map (
    clk                                 => clk,
    clk_en                              => clk_en,
    reset                               => reset,
    start                               => mi_start,
    d_in                                => mi_d_in,
    x_in                                => mi_x_in,
    x_out                               => mi_x_out,
    x_new                               => mi_x_new
  );

  luffa512_p_inst : luffa512_p_ce
  port map (
    clk                                 => clk,
    clk_en                              => clk_en,
    reset                               => reset,
    start                               => p_start,
    x_in                                => p_x_in,
    x_out                               => p_x_out,
    x_new                               => p_x_new
  );
  
  luffa512_proc : process(q_luffa512_state, q_x, q_h, start, data_in_array, mi_x_new, mi_x_out_array, p_x_new, pause)
  begin
    luffa512_state_next                 <= q_luffa512_state;
    busy_n                              <= '0';
    mi_d_in_array                       <= ZEROS_WORD32_ARRAY8;
    mi_x_in_array                       <= q_x;
    mi_start                            <= '0';
    p_x_in_array                        <= q_x;
    p_start                             <= '0';
    x                                   <= q_x;
    h                                   <= q_h;
    almost_done                         <= '0';
    done                                <= '0';
    case q_luffa512_state is
    when IDLE =>
      busy_n                            <= '1';
      if start = '1' then
        busy_n                          <= '0';
        mi_d_in_array                   <= (data_in_array(7),data_in_array(6),data_in_array(5),data_in_array(4),data_in_array(3),data_in_array(2),data_in_array(1),data_in_array(0));
        mi_x_in_array                   <= IV;
        mi_start                        <= '1';
        luffa512_state_next             <= MI1;
      end if;
    when MI1 =>
      mi_d_in_array                     <= (data_in_array(7),data_in_array(6),data_in_array(5),data_in_array(4),data_in_array(3),data_in_array(2),data_in_array(1),data_in_array(0));
      mi_x_in_array                     <= IV;
      if mi_x_new = '1' then
        x                               <= mi_x_out_array;
        p_x_in_array                    <= mi_x_out_array;
        p_start                         <= '1';
        luffa512_state_next             <= P1;
      end if;
    when P1 =>
      if p_x_new = '1' then
        x                               <= p_x_out_array;
        mi_d_in_array                   <= (data_in_array(15),data_in_array(14),data_in_array(13),data_in_array(12),data_in_array(11),data_in_array(10),data_in_array(9),data_in_array(8));
        mi_x_in_array                   <= p_x_out_array;
        mi_start                        <= '1';
        luffa512_state_next             <= MI2;
      end if;
    when MI2 =>
      mi_d_in_array                     <= (data_in_array(15),data_in_array(14),data_in_array(13),data_in_array(12),data_in_array(11),data_in_array(10),data_in_array(9),data_in_array(8));
      mi_x_in_array                     <= q_x;
      if mi_x_new = '1' then
        x                               <= mi_x_out_array;
        p_x_in_array                    <= mi_x_out_array;
        p_start                         <= '1';
        luffa512_state_next             <= P2;
      end if;
    when P2 =>
      if p_x_new = '1' then
        x                               <= p_x_out_array;
        mi_d_in_array                   <= PADDING;
        mi_x_in_array                   <= p_x_out_array;
        mi_start                        <= '1';
        luffa512_state_next             <= MI3;
      end if;
    when MI3 =>
      mi_d_in_array                     <= PADDING;
      mi_x_in_array                     <= q_x;
      if mi_x_new = '1' then
        x                               <= mi_x_out_array;
        p_x_in_array                    <= mi_x_out_array;
        p_start                         <= '1';
        luffa512_state_next             <= P3;
      end if;
    when P3 =>
      if p_x_new = '1' then
        x                               <= p_x_out_array;
        mi_d_in_array                   <= ZEROS_WORD32_ARRAY8;  
        mi_x_in_array                   <= p_x_out_array; 
        mi_start                        <= '1';
        luffa512_state_next             <= MI4;
      end if;    
    when MI4 =>
      mi_d_in_array                     <= ZEROS_WORD32_ARRAY8;
      mi_x_in_array                     <= q_x;
      if mi_x_new = '1' then
        x                               <= mi_x_out_array;
        p_x_in_array                    <= mi_x_out_array;
        p_start                         <= '1';
        luffa512_state_next             <= P4;
      end if;
    when P4 =>
      if p_x_new = '1' then
        x                               <= p_x_out_array;
        mi_d_in_array                   <= ZEROS_WORD32_ARRAY8;
        mi_x_in_array                   <= p_x_out_array;
        mi_start                        <= '1';
        for i in 0 to 7 loop
          h(i)                          <= endian_swap32(p_x_out_array(i) xor p_x_out_array(8+i) xor p_x_out_array(16+i) xor
                                                         p_x_out_array(24+i) xor p_x_out_array(32+i));
        end loop;
        luffa512_state_next             <= MI5;
      end if;
    when MI5 =>
      mi_d_in_array                     <= ZEROS_WORD32_ARRAY8;
      mi_x_in_array                     <= q_x;
      if mi_x_new = '1' then
        x                               <= mi_x_out_array;
        p_x_in_array                    <= mi_x_out_array;
        p_start                         <= '1';
        luffa512_state_next             <= P5;
      end if;
    when P5 =>
      if p_x_new = '1' then
        x                               <= p_x_out_array;  
        for i in 0 to 7 loop
          h(8+i)                        <= endian_swap32(p_x_out_array(i) xor p_x_out_array(8+i) xor p_x_out_array(16+i) xor
                                                         p_x_out_array(24+i) xor p_x_out_array(32+i));
        end loop;
        almost_done                     <= '1';
        luffa512_state_next             <= FINISH;
      end if;
    when FINISH =>
      done                              <= '1';
      if pause = '0' then
        luffa512_state_next             <= IDLE;
      end if;
    end case;
  end process luffa512_proc;
  
  registers : process(clk, reset) is
  begin
    if reset = '1' then
      q_luffa512_state                  <= IDLE;
    elsif rising_edge(clk) then
      if clk_en = '1' then
        q_luffa512_state                <= luffa512_state_next;
        q_x                             <= x;
        q_h                             <= h;
      end if;
    end if;
  end process registers;
  
end architecture luffa512_ce_rtl;