//Definitions of 32-bit registers


typedef struct {
  
volatile uint32_t control;
volatile  uint32_t status;
volatile  uint32_t readaddress;
volatile  uint32_t writeaddress;

}
__attribute__((aligned(4))) DMAC_Regs;
//__attribute__((packed)) WzTim1Regs;
