import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset_dut(dut):
    """
    Apply reset via the SW(9) input.
    In ping_pong_game.vhdl:
       reset  <= not SW(9);
       resetn <= SW(9);
    To assert reset (active high for game logic), we need SW(9)=0.
    To release reset, we need SW(9)=1.
    """
    # Assert reset (SW[9] = 0)
    # We keep other switches 0 initially
    dut.SW.value = 0
    await ClockCycles(dut.MAX10_CLK1_50, 10)
    
    # Release reset (SW[9] = 1)
    # We keep other switches 0 for now (buttons released if active low logic in top?)
    # Top logic: btnl <= not SW(8).
    # If SW(8)=0 -> btnl=1 (pressed).
    # If SW(8)=1 -> btnl=0 (released).
    # So we want SW[8:5] = 1111 (0xF) to have buttons RELEASED.
    # SW[9] = 1 (Reset released).
    # SW[9:5] = 11111 = 0x1F.
    # So default state should be 0x3E0 (bits 9,8,7,6,5 high).
    # Wait, 9,8,7,6,5.
    # Bit 9: Reset (1=Run)
    # Bit 8: BtnL (1=Released)
    # Bit 7: BtnR (1=Released)
    # Bit 6: BtnUp (1=Released)
    # Bit 5: BtnDown (1=Released)
    # Mask: (1<<9)|(1<<8)|(1<<7)|(1<<6)|(1<<5) = 512+256+128+64+32 = 992 = 0x3E0.
    
    dut.SW.value = 0x3E0 
    await ClockCycles(dut.MAX10_CLK1_50, 10)

async def press_button(dut, btn_index):
    """
    Press a button mapped to SW[btn_index].
    Logic: btn <= not SW(index).
    Pressed (1) => SW(index) = 0.
    Released (0) => SW(index) = 1.
    """
    # Press (Clear bit)
    current_sw = int(dut.SW.value)
    dut.SW.value = current_sw & ~(1 << btn_index)
    await ClockCycles(dut.MAX10_CLK1_50, 20) # Wait for debounce (fast due to generic)
    
    # Release (Set bit)
    current_sw = int(dut.SW.value)
    dut.SW.value = current_sw | (1 << btn_index)
    await ClockCycles(dut.MAX10_CLK1_50, 20)

# Button mappings
BTN_L_IDX = 8
BTN_R_IDX = 7
BTN_UP_IDX = 6
BTN_DOWN_IDX = 5


# ---------------------------------------------------------------------------
# Test 1 – Reset / initial state
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_game_init(dut):
    """Verify that after reset, the game is in Menu mode."""
    cocotb.start_soon(Clock(dut.MAX10_CLK1_50, 20, unit="ns").start())
    await reset_dut(dut)
    
    # Check internal game_mode signal
    # Access strategy: try direct access (works if flat/visible), else hierarchical
    try:
        mode = dut.game_mode.value
    except AttributeError:
        # Try hierarchical if declared in top
        mode = dut.game_state_mgr.game_mode.value

    cocotb.log.info(f"Initial game_mode: {mode}")
    assert int(mode) == 0, f"Expected game_mode=0 (Menu), got {int(mode)}"
    
    # Verify scores are 0
    try:
        s1 = int(dut.user1_score.value)
        s2 = int(dut.user2_score.value)
        assert s1 == 0 and s2 == 0, f"Scores should be 0, got {s1}-{s2}"
    except AttributeError:
        pass


# ---------------------------------------------------------------------------
# Test 2 – Menu Navigation
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_menu_navigation(dut):
    """Test navigation using Buttons (SW inputs)."""
    cocotb.start_soon(Clock(dut.MAX10_CLK1_50, 20, unit="ns").start())
    await reset_dut(dut)

    # 1. Menu -> Tournament (BtnDown / SW5)
    await press_button(dut, BTN_DOWN_IDX)
    
    # Check mode = 1
    try:
        mode = int(dut.game_mode.value)
    except AttributeError:
        mode = int(dut.game_state_mgr.game_mode.value)
        
    assert mode == 1, f"Expected game_mode=1 (Tournament), got {mode}"
    
    # Reset to Menu
    await reset_dut(dut)
    
    # 2. Menu -> Practice (BtnL / SW8)
    await press_button(dut, BTN_L_IDX)
    
    try:
        mode = int(dut.game_mode.value)
    except AttributeError:
        mode = int(dut.game_state_mgr.game_mode.value)
        
    assert mode == 2, f"Expected game_mode=2 (Practice), got {mode}"


# ---------------------------------------------------------------------------
# Test 3 – Difficulty Change
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_difficulty_change(dut):
    """BtnUp cycles difficulty 1->2->3->0->1..."""
    cocotb.start_soon(Clock(dut.MAX10_CLK1_50, 20, unit="ns").start())
    await reset_dut(dut)

    # Initial difficulty should be 1
    try:
        diff = int(dut.difficulty.value)
    except AttributeError:
        diff = int(dut.game_state_mgr.difficulty.value)
        
    assert diff == 1, f"Initial difficulty should be 1, got {diff}"
    
    # Cycle through
    expected_seq = [2, 3, 0, 1]
    for expected in expected_seq:
        await press_button(dut, BTN_UP_IDX)
        try:
            diff = int(dut.difficulty.value)
        except AttributeError:
            diff = int(dut.game_state_mgr.difficulty.value)
        assert diff == expected, f"Expected difficulty {expected}, got {diff}"


# ---------------------------------------------------------------------------
# Test 4 – Game Flow (Integration)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_game_flow(dut):
    """Start game, let ball move, verify someone scores."""
    cocotb.start_soon(Clock(dut.MAX10_CLK1_50, 20, units="ns").start())
    await reset_dut(dut)

    # Start Tournament
    await press_button(dut, BTN_DOWN_IDX)

    # 2. Start Game
    # In game_state_manager: if mode=1/2, btnl or btnr starts the game.
    # We use BTN_R (SW7) to start.
    await press_button(dut, BTN_R_IDX)
    
    # Confirm game started
    try:
        started = int(dut.game_started.value)
    except AttributeError:
        started = int(dut.game_state_mgr.game_started.value)
    assert started == 1, "Game should be started"
    
    # With freq=1000, ball moves fast.
    # We wait for score change.
    # Ball needs ~10 steps * (freq * speed_factor) cycles.
    # At diff 1, speed is 750 cycles/step. Total ~7500 cycles to cross.
    # We allow 50000 cycles to be safe.
    
    score_changed = False
    for _ in range(5000): # 5000 * 10 cycles = 50000 cycles
        s1 = int(dut.user1_score.value)
        s2 = int(dut.user2_score.value)
        if s1 > 0 or s2 > 0:
            score_changed = True
            cocotb.log.info(f"Score detected! {s1}-{s2}")
            break
        await ClockCycles(dut.MAX10_CLK1_50, 10)
        
    assert score_changed, "Ball did not score within timeout!"
    
    # Verify round over or continue
    # If score < winning score, game continues
    # With freq=1000, round pause might be short too?
    # PAUSE_TIME = freq = 1000 cycles.
    # So after score, it waits 1000 cycles.
    
    # Wait for pause to finish (approx 1000 cycles)
    await ClockCycles(dut.MAX10_CLK1_50, 1500)
    
    # Ball should be moving again
    # We can check internal ball position if we want, but score check is good enough.


# ---------------------------------------------------------------------------
# Test 5 – Match Win (Integration)
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_match_win(dut):
    """Simulate a full match until one player wins."""
    cocotb.start_soon(Clock(dut.MAX10_CLK1_50, 20, units="ns").start())
    await reset_dut(dut)

    # 1. Start Tournament
    await press_button(dut, BTN_DOWN_IDX) # Mode 1

    # 2. Start Game
    await press_button(dut, BTN_R_IDX)
    
    # We will let User 1 win (or whoever scores first by default).
    # If we don't press buttons, does the same player always win?
    # Ball starts at 9 (Right), moves Left.
    # Hits 0 (Left). User 1 (Left Player) scores? (Based on previous analysis)
    # Let's see who scores in the loop.
    
    # We need to win 3 rounds.
    # Each round needs 4 points.
    # Total 12 points.
    
    match_over = False
    
    # Timeout safety
    # With alternating wins, we might play 5 rounds.
    # Each round might go to 3-3 then 4-3 (7 points).
    # Total ~35 points.
    # Each point ~9000 cycles.
    # Total ~315,000 cycles.
    # Set to 600,000 to be safe.
    for _ in range(60000): # 600,000 cycles
        # Check match over signal
        try:
            mo = int(dut.match_over.value)
        except AttributeError:
            mo = int(dut.game_state_mgr.match_over.value)
            
        if mo == 1:
            match_over = True
            cocotb.log.info("Match Over detected!")
            break
            
        # Check if game is paused (waiting for serve)
        # We need to press a button to serve after a point.
        # Ball resets to pos 9, so we need BTN_L (SW8) to serve.
        # But wait for PAUSE_TIME (1000 cycles).
        try:
            paused = int(dut.game_paused.value)
        except AttributeError:
            paused = int(dut.game_state_mgr.game_paused.value)
            
        if paused == 1:
              # Wait a bit then press serve
              # Check ball position to decide which button to press
              try:
                  bpos = int(dut.ball_position.value)
              except AttributeError:
                  bpos = int(dut.ball_engine.ball_position.value)
                  
              if _ % 200 == 0: # Every 2000 cycles
                  if bpos == 0:
                      cocotb.log.info("Game paused at Left (0), serving with BTN_R...")
                      await press_button(dut, BTN_R_IDX)
                  elif bpos == 9:
                      cocotb.log.info("Game paused at Right (9), serving with BTN_L...")
                      await press_button(dut, BTN_L_IDX)
                  else:
                      cocotb.log.info(f"Game paused at {bpos}, waiting...")
             
         # Optional: Log scores occasionally
        if _ % 1000 == 0:
            s1 = int(dut.user1_score.value)
            s2 = int(dut.user2_score.value)
            r1 = int(dut.user1_rounds.value)
            r2 = int(dut.user2_rounds.value)
            cocotb.log.info(f"Status: S {s1}-{s2}, R {r1}-{r2}, Paused={paused}")
            
        await ClockCycles(dut.MAX10_CLK1_50, 10)
        
    assert match_over, "Match did not finish within timeout!"
    
    # Verify someone has 3 rounds (or sufficient logic)
    r1 = int(dut.user1_rounds.value)
    r2 = int(dut.user2_rounds.value)
    assert r1 >= 3 or r2 >= 3, f"Expected winner with >= 3 rounds, got {r1}-{r2}"


