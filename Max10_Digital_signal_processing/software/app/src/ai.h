#ifndef AI_H
#define AI_H

/* Run one bounded inference window from the ADC FIFO. */
int ai_run_once(unsigned int *output_class);

/* Run continuous inference and expose the class on the LED PIO. */
void ai_demo_forever(void);

#endif
