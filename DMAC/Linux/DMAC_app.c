#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <pthread.h>
#include <assert.h>
#include <sys/mman.h>
#include <sys/stat.h> 
#include <sys/types.h>
#include <sys/wait.h>
#include <fcntl.h>
#include "DMAC_app.h"
#include <linux/ioctl.h>


struct sched_param sp;

#define DMA_TRANSFER_SIZE 	512 //bytes
#define WR_VALUE _IOW('a','a',uint32_t*)


#define HPS_FPGA_BRIDGE_BASE 0xC0000000
#define HW_REGS_BASE ( HPS_FPGA_BRIDGE_BASE )
#define HW_REGS_SPAN ( 0x40000000 )
#define HW_REGS_MASK ( HW_REGS_SPAN - 1 )

//Address of the On-Chip RAM in the FPGA, as seen by processor
#define FPGA_OCR_QSYS_ADDRESS_UP 0x0
#define FPGA_OCR_ADDRESS_UP ((uint8_t*)0xC0000000+FPGA_OCR_QSYS_ADDRESS_UP)
//Address of the On-Chip RAM in the FPGA, as seen by DMAC
#define k 0x0
//Address of the HPS-OCR, as seen by both processor and FPGA-DMAC
#define HPS_OCR_ADDRESS 0xFFFF0000
#define DMA_TRANSFER_SRC_UP     ((uint8_t*) FPGA_OCR_vaddr)
#define DMA_TRANSFER_DST_UP     ((uint8_t*) HPS_OCR_vaddr)


//funkcja testowa do wyswietlania zawartosci pamieci
void printbuff(uint8_t* buff, int size)
{
  int i;
  printf("[");
  for (i=0; i<size; i++)
  {
    printf("%u",buff[i]);
    if (i<(size-1)) printf(",");
  }
  printf("]");
  printf("\n");
}

int main(int argc, char *argv[])
{
    int i;
    char line[200];


    uint8_t userspaceBuffer[512]; 
    uint8_t tempBuffer[512];

    //wypelnienie bufora w przestrzeni uzytkownika danymi
    for (i=0; i<512;i++)
    {
     userspaceBuffer[i] = i + 10;
     tempBuffer[i] = 0;
    }

    printf("USERSPACEBUFFER before transmission: \n");
    for (i=0; i<512;i++)
    {
     printf("%d, ",userspaceBuffer[i]);
     if(i%20 == 0)
     {
      printf("\n");
     }
    }


    //otwarcie dostepu do pamieci w FPGA, zmapowanie obszaru pamieci
    void *virtual_base;
    int fd;
    if( ( fd = open( "/dev/mem", ( O_RDWR | O_SYNC ) ) ) == -1 ) {
	  printf( "ERROR: could not open \"/dev/mem\"...\n" );
	  return( 1 );
    }
    //mmap from 0xC0000000 to 0xFFFFFFFF (1GB): FPGA and HPS peripherals
    virtual_base = mmap( NULL, HW_REGS_SPAN, ( PROT_READ | PROT_WRITE ),
    MAP_SHARED, fd, HW_REGS_BASE );
    
    if( virtual_base == MAP_FAILED ) {
	  printf( "ERROR: mmap() failed...\n" );
	  close( fd );
	  return( 1 );
    }

// //zmapowana pamiec FPGA_OCR i HPS-OCR widziana przez procesor

    void *FPGA_OCR_vaddr_void = virtual_base
    + ((unsigned long)(FPGA_OCR_QSYS_ADDRESS_UP) & (unsigned long)( HW_REGS_MASK ));
    uint8_t* FPGA_OCR_vaddr = (uint8_t *) FPGA_OCR_vaddr_void;

    void *HPS_OCR_vaddr_void = virtual_base
    + ((unsigned long)(HPS_OCR_ADDRESS-HPS_FPGA_BRIDGE_BASE) &
    (unsigned long)( HW_REGS_MASK ));
    uint8_t* HPS_OCR_vaddr = (uint8_t *) HPS_OCR_vaddr_void;
  printf("virtualbase = %x\n\n",FPGA_OCR_vaddr );


  uint8_t* fpga_ocr_ptr = FPGA_OCR_vaddr;
  uint8_t* hps_ocr_ptr = HPS_OCR_vaddr;

//   //Reset FPGA-OCR
  fpga_ocr_ptr = FPGA_OCR_vaddr;
  for (i=0; i<DMA_TRANSFER_SIZE; i++)
  {
    *fpga_ocr_ptr = 0;
    if (*fpga_ocr_ptr != 0)
    {
      printf ("Error when resetting FPGA On-Chip RAM in Byte %d\n", i);
      return 0;
    }
    fpga_ocr_ptr++;
  }
  printf("Reset FPGA On-Chip RAM OK\n");

  //Reset HPS-OCR
  hps_ocr_ptr = HPS_OCR_vaddr;
  for (i=0; i<DMA_TRANSFER_SIZE; i++)
  {
    *hps_ocr_ptr = 0;
    if (*hps_ocr_ptr != 0)
    {
      printf ("Error when resetting On-Chip RAM in Byte %d\n", i);
      return 0;
    }
    hps_ocr_ptr++;
  }
  printf("Reset On-Chip RAM OK\n");


//wypelnienie pamieci 0xC0000000 danymi testownymi
 for (i=0; i<DMA_TRANSFER_SIZE;i++) DMA_TRANSFER_SRC_UP[i] = (uint8_t)i;



  //////////////////////////////////////////////////
  /////////////////////////////////////////////////

    int fd2;
    fd2=open("/dev/my_tim0",O_RDWR);

    //rozmiar tablicy w Bajtach
    int data_size = sizeof(userspaceBuffer);// / sizeof(userspaceBuffer[0]);

    //wpisanie danych z przestrzeni uzytkownika do bufora w przestrzeni jadra
    assert(write(fd2,&userspaceBuffer,data_size)==8);

    sleep(1);


    //ustalenie zawartosci rejestru control 
    uint32_t DMAC_Config = 0x00800001;

    printf("Zapisano konfig, start transmisji DMA\n\n");
    //wyslanie rejestru control do jadra komenda ioctl
    ioctl(fd2, WR_VALUE, (int32_t*) &DMAC_Config); 

    sleep(1);


    //odczyt zawartosci bufora z jadra 
    read(fd2,&tempBuffer,data_size);

    printf("tempBuffer after transmission: \n");
    for (i=0; i<512;i++)
    {
     printf("%x, ",tempBuffer[i]);
          if(i%20 == 0)
     {
      printf("\n");
     }

    }

    close(fd2);



    //wyswietlaenie pamieci
    printf("\nFPGA mem After transmission: \n");
    printbuff(DMA_TRANSFER_SRC_UP, DMA_TRANSFER_SIZE);


    printf("\nHPS mem After transmission: \n");
    printbuff(DMA_TRANSFER_DST_UP, DMA_TRANSFER_SIZE);


	// // --------------clean up our memory mapping and exit -----------------//
	if( munmap( virtual_base, HW_REGS_SPAN ) != 0 ) {
		printf( "ERROR: munmap() failed...\n" );
		close( fd );
		return( 1 );
	}

	return(0);

}


