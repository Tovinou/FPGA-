#include <Arduino.h>

/*
 * SSI (Synchronous Serial Interface) Slave Emulator for ESP32
 * 
 * Hardware: ESP32-WROOM-32D (30-pin DevKit)
 * Framework: Arduino
 * 
 * Wiring to DE10-Lite FPGA:
 *   FPGA GPIO_0_0 (SSI_CLK)   -> ESP32 GPIO 4
 *   FPGA GPIO_0_1 (SSI_DATA)  -> ESP32 GPIO 5
 *   FPGA GND                  -> ESP32 GND
 * 
 * Behavior:
 *   The FPGA (Master) outputs a 500 kHz clock burst.
 *   SSI protocol expects the Slave (ESP32) to shift out 1 bit of DATA
 *   on the FALLING edge of the clock.
 *   The FPGA samples that DATA on the RISING edge of the clock.
 * 
 *   Because 500 kHz (2 us period) is quite fast for a simple Arduino
 *   digitalRead/Write loop, we use direct register access and a 
 *   tight ISR (Interrupt Service Routine) attached to the clock pin.
 */

// Pin definitions
const int PIN_SSI_CLK = 4;
const int PIN_SSI_DATA = 5;

// Direct GPIO register masks for ESP32 (GPIO 0-31)
const uint32_t DATA_PIN_MASK = (1UL << PIN_SSI_DATA);

// The 25-bit value we want to send to the FPGA.
// Example: 0x1A2B3C4 (25 bits: 1 1010 0010 1011 0011 1100 0100)
// The FPGA testbench expects MSB first.
volatile uint32_t current_position = 0x1A2B3C4; 

// Internal state for the ISR
volatile uint32_t shift_register = 0;
volatile int bit_counter = 0;
volatile bool frame_active = false;

// ISR must be in IRAM for speed
void IRAM_ATTR ssi_clk_isr() {
  // This ISR fires on the FALLING edge of SSI_CLK
  
  if (!frame_active) {
    // First falling edge: load the shift register
    shift_register = current_position;
    bit_counter = 25; // Sending 25 bits
    frame_active = true;
  }
  
  if (bit_counter > 0) {
    // Output the Most Significant Bit (bit 24)
    if (shift_register & 0x1000000) {
      // Set DATA pin HIGH
      GPIO.out_w1ts = DATA_PIN_MASK;
    } else {
      // Set DATA pin LOW
      GPIO.out_w1tc = DATA_PIN_MASK;
    }
    
    // Shift left for the next clock cycle
    shift_register <<= 1;
    bit_counter--;
  } else {
    // Out of bits, drive LOW (or HIGH depending on your SSI idle state preference)
    GPIO.out_w1tc = DATA_PIN_MASK;
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("ESP32 SSI Slave Emulator Started");
  
  // Configure pins
  pinMode(PIN_SSI_CLK, INPUT_PULLUP);
  pinMode(PIN_SSI_DATA, OUTPUT);
  digitalWrite(PIN_SSI_DATA, LOW); // Default idle state
  
  // Attach interrupt to the SSI Clock pin (falling edge)
  attachInterrupt(digitalPinToInterrupt(PIN_SSI_CLK), ssi_clk_isr, FALLING);
}

void loop() {
  // The main loop just monitors for the end of a frame to reset the state,
  // and occasionally changes the position value to simulate movement.
  
  // If clock is HIGH (idle) and we finished a frame, reset for the next one
  if (digitalRead(PIN_SSI_CLK) == HIGH && frame_active && bit_counter == 0) {
    // Small delay to ensure the FPGA has finished its sampling
    delayMicroseconds(10); 
    frame_active = false;
    
    // Optional: Increment the position slowly so you can see it change on the FPGA displays
    // current_position = (current_position + 1) & 0x1FFFFFF; // Keep it 25-bit
  }
  
  // Print current value every second
  static unsigned long last_print = 0;
  if (millis() - last_print > 1000) {
    Serial.printf("Emulating SSI Position: 0x%07X\n", current_position);
    last_print = millis();
  }
}
