# Ping Pong Game - User Guide (DE10-Lite)

This guide explains how to play the Ping Pong Game on the Terasic DE10-Lite FPGA board.

## Controls & Interfaces

| Component | Function | Description |
| :--- | :--- | :--- |
| **SW[9]** | **Reset** | `0` = Reset (System Halted), `1` = Run (Game Active). **Must be UP to play.** |
| **SW[8]** | **Left Button** | Player 1 Paddle / Navigate Left / Select Practice Mode. (Active Low logic: `0`=Pressed) |
| **SW[7]** | **Right Button** | Player 2 Paddle / Start Game / Navigate Right. (Active Low logic: `0`=Pressed) |
| **SW[6]** | **Up Button** | Change Difficulty Level. (Active Low logic: `0`=Pressed) |
| **SW[5]** | **Down Button** | Select Tournament Mode. (Active Low logic: `0`=Pressed) |
| **LEDR[9..0]** | **Ball Position** | Shows the ball moving back and forth. `LEDR[9]` is Left edge, `LEDR[0]` is Right edge. |
| **HEX0, HEX2** | **Scoreboard** | Shows current score. `HEX0` = Player 1, `HEX2` = Player 2 (Animated). |
| **VGA Output** | **Game Display** | Connect a VGA monitor to see the visual game field, scores, and ball. |

---

## How to Play

### 1. Power Up & Reset
1. Connect the DE10-Lite board to power.
2. Flip **SW[9]** to the **UP (1)** position. This releases the reset and starts the system.
3. The system starts in **Menu Mode**.

### 2. Select Game Mode
*   **Tournament Mode**: Press **SW[5] (Down)**.
    *   Competitive match mode. First to win 3 rounds wins the match.
*   **Practice Mode**: Press **SW[8] (Left)**.
    *   Endless practice.

### 3. Set Difficulty (Optional)
*   In Menu Mode, press **SW[6] (Up)** to cycle through difficulty levels.
*   Level 1 (Slow) -> Level 2 (Medium) -> Level 3 (Fast).

### 4. Start Game
*   Once a mode is selected, press **SW[7] (Right)** or **SW[8] (Left)** to serve the ball and start.

### 5. Gameplay
*   **The Ball**: Represented by the lit LED moving across `LEDR[9]` down to `LEDR[0]`.
*   **Player 1 (Left)**: Watch `LEDR[9]`. When the ball reaches the left edge, press **SW[8] (Left)** to hit it back.
*   **Player 2 (Right)**: Watch `LEDR[0]`. When the ball reaches the right edge, press **SW[7] (Right)** to hit it back.
*   **Timing**:
    *   **Perfect Hit**: Hit exactly when the ball is at the edge.
    *   **Early/Late Hit**: You miss, and the opponent scores a point.

### 6. Scoring & Winning
*   **Point**: If a player misses, the opponent gets a point (shown on HEX display).
*   **Round**: First to 3 points wins the round.
*   **Match**: First to win 2 rounds wins the match (Tournament Mode).
*   **Reset**: Flip **SW[9]** DOWN then UP to restart everything at any time.

---

## Note on Switches vs. Buttons

The code uses **Switches (SW)** as buttons because the DE10-Lite only has 2 physical pushbuttons (`KEY0`, `KEY1`), which isn't enough for Up/Down/Left/Right inputs required by the game.

*   **To "Press" a button**: Flip the switch DOWN, then immediately flip it back UP.
*   **Example**: To hit the ball, flick **SW[8]** down and up quickly.

This control scheme is defined in lines 83-86 of `ping_pong_game.vhdl`:

```vhdl
btnl <= not SW(8); -- Logic 1 when SW(8) is 0 (Down)
```
