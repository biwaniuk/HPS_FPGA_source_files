

#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/types.h>
#include <linux/spi/spidev.h>


#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <string.h>
#include <pthread.h>
#include <assert.h>
#include <sys/mman.h>
#include <sys/stat.h>        
#include <sys/wait.h>

#include <pthread.h>


#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

//do sprawdzenia pamieci w fpga + odczytu rejestru z przerwaniem
#define HPS_FPGA_BRIDGE_BASE 0xC0000000
#define HW_REGS_BASE ( HPS_FPGA_BRIDGE_BASE )

#define FPGA_OCR_QSYS_ADDRESS_UP 0x0
#define DMA_TRANSFER_SRC_UP     ((uint8_t*) FPGA_OCR_vaddr)

#define HW_REGS_SPAN ( 0x40000000 )
#define HW_REGS_MASK ( HW_REGS_SPAN - 1 )

#define FPGA_SPISLAVE_QSYS_ADDRESS 0x00010000
#define FPGA_SPISLAVE_ADDRESS ((uint8_t*)0xC0000000+FPGA_SPISLAVE_QSYS_ADDRESS)

#define TRANSFER_SIZE 24

pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

pthread_cond_t cond1 = PTHREAD_COND_INITIALIZER;

//void *FPGA_SPISLAVE_vaddr_void;

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

static void pabort(const char *s)
{
	perror(s);
	abort();
}

//funkcja obslugujaca przerwanie
void *irqHandler( void *SPISLAVE_addr)
{
	pthread_mutex_lock(&lock);

	printf("watek dziala, czeka na odblokowanie\n");
  pthread_cond_wait(&cond1, &lock);
	//watek czeka az watek glowny go odblokuje

  //printf("Interrupt #%u!\n", info);
	printf("INTERRUPT CODE: %08x\n", *((uint32_t*) (SPISLAVE_addr)));
		
		uint32_t val = 0x80000000;
		*((uint32_t*) (SPISLAVE_addr)) = val; //zapis do rejestru informacji zebty zdjac przerwanie

		printf("przerwanie zdjęte.");

	pthread_mutex_unlock(&lock);


	return NULL;
}



static const char *device = "/dev/spidev0.3";
static uint8_t mode;
static uint8_t bits = 8;
static uint32_t speed = 500000;
static uint16_t delay;

//transakcja SPI
static void transfer(int fd)
{
	int ret;
	uint8_t tx[] = {
		0x00, 0x00, 0x00, 0x00, //adres poczatkowy odczytu/zapisu
		0x06, //bajt konfiguracyjny
		0x0B, //dlugosc transakcji 
		//ponizej dane testowe
		0xF8, 0xF9, 0xFA, 0xFB, 0xFE, 0xFF,
		0xF0, 0xF1, 0x11, 0x12, 0x12, 0x14, 0x15, 0x16
	};
	uint8_t rx[ARRAY_SIZE(tx)] = {
		0x00, 
	 };

	struct spi_ioc_transfer tr = {
		.tx_buf = (unsigned long)tx,
		.rx_buf = (unsigned long)rx,
		.len = 6 + 11, //6 bajtow neizbedna konfiguracja, reszta data
		.delay_usecs = delay,
		.speed_hz = speed,
		.bits_per_word = bits,
	};

	for (ret = 0; ret < ARRAY_SIZE(tx); ret++) {
		if (!(ret % 6))
			puts("");
		printf("%.2X ", rx[ret]);
	}
	puts("");

	ret = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
	if (ret < 1)
		pabort("can't send spi message");
	
	sleep(2);
	for (ret = 0; ret < ARRAY_SIZE(tx); ret++) {
		if (!(ret % 6))
			puts("");
		printf("%.2X ", rx[ret]);
	}
	puts("");
}

static void print_usage(const char *prog)
{
	printf("Usage: %s [-DsbdlHOLC3]\n", prog);
	puts("  -D --device   device to use (default /dev/spidev1.1)\n"
	     "  -s --speed    max speed (Hz)\n"
	     "  -d --delay    delay (usec)\n"
	     "  -b --bpw      bits per word \n"
	     "  -l --loop     loopback\n"
	     "  -H --cpha     clock phase\n"
	     "  -O --cpol     clock polarity\n"
	     "  -L --lsb      least significant bit first\n"
	     "  -C --cs-high  chip select active high\n"
	     "  -3 --3wire    SI/SO signals shared\n");
	exit(1);
}

static void parse_opts(int argc, char *argv[])
{
	while (1) {
		static const struct option lopts[] = {
			{ "device",  1, 0, 'D' },
			{ "speed",   1, 0, 's' },
			{ "delay",   1, 0, 'd' },
			{ "bpw",     1, 0, 'b' },
			{ "loop",    0, 0, 'l' },
			{ "cpha",    0, 0, 'H' },
			{ "cpol",    0, 0, 'O' },
			{ "lsb",     0, 0, 'L' },
			{ "cs-high", 0, 0, 'C' },
			{ "3wire",   0, 0, '3' },
			{ "no-cs",   0, 0, 'N' },
			{ "ready",   0, 0, 'R' },
			{ NULL, 0, 0, 0 },
		};
		int c;

		c = getopt_long(argc, argv, "D:s:d:b:lHOLC3NR", lopts, NULL);

		if (c == -1)
			break;

		switch (c) {
		case 'D':
			device = optarg;
			break;
		case 's':
			speed = atoi(optarg);
			break;
		case 'd':
			delay = atoi(optarg);
			break;
		case 'b':
			bits = atoi(optarg);
			break;
		case 'l':
			mode |= SPI_LOOP;
			break;
		case 'H':
			mode |= SPI_CPHA;
			break;
		case 'O':
			mode |= SPI_CPOL;
			break;
		case 'L':
			mode |= SPI_LSB_FIRST;
			break;
		case 'C':
			mode |= SPI_CS_HIGH;
			break;
		case '3':
			mode |= SPI_3WIRE;
			break;
		case 'N':
			mode |= SPI_NO_CS;
			break;
		case 'R':
			mode |= SPI_READY;
			break;
		default:
			print_usage(argv[0]);
			break;
		}
	}
}

int main(int argc, char *argv[])
{
	int ret = 0;
	int fd;
	int i;
	
	int fd3 = open("/dev/uio0", O_RDWR);
    if (fd3 < 0) {
      perror("open");
      exit(EXIT_FAILURE);
    }
	
	
	void *virtual_base;
    int fd2;
    if( ( fd2 = open( "/dev/mem", ( O_RDWR | O_SYNC ) ) ) == -1 ) {
	  printf( "ERROR: could not open \"/dev/mem\"...\n" );
	  return( 1 );
    }
    //mmap from 0xC0000000 to 0xFFFFFFFF (1GB): FPGA and HPS peripherals
    virtual_base = mmap( NULL, HW_REGS_SPAN, ( PROT_READ | PROT_WRITE ),
    MAP_SHARED, fd2, HW_REGS_BASE );
    
    
        if( virtual_base == MAP_FAILED ) {
	  printf( "ERROR: mmap() failed...\n" );
	  close( fd2 );
	  return( 1 );
    }
    
        void *FPGA_OCR_vaddr_void = virtual_base
    + ((unsigned long)(FPGA_OCR_QSYS_ADDRESS_UP) & (unsigned long)( HW_REGS_MASK ));
    uint8_t* FPGA_OCR_vaddr = (uint8_t *) FPGA_OCR_vaddr_void;
    

		void *FPGA_SPISLAVE_vaddr_void = virtual_base + ((unsigned long)(FPGA_SPISLAVE_QSYS_ADDRESS));
    


    //check fpga ocr
  uint8_t* fpga_ocr_ptr = FPGA_OCR_vaddr;

  
        //Reset FPGA-OCR
  fpga_ocr_ptr = FPGA_OCR_vaddr;
  for (i=0; i<TRANSFER_SIZE; i++)
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
    
    
		//wpisanie do pamieci FPGA danych testowych
    for (i=0; i<TRANSFER_SIZE;i++) DMA_TRANSFER_SRC_UP[i] = (uint8_t)(i);
    
    
  printf("Pamiec FPGA przed transferem SPI");
  printbuff(DMA_TRANSFER_SRC_UP, TRANSFER_SIZE);
    
    ///////////////////////////////
    //////////////////////////////
    
	parse_opts(argc, argv);

	fd = open(device, O_RDWR);
	if (fd < 0)
		pabort("can't open device");

	/*
	 * spi mode
	 */
	ret = ioctl(fd, SPI_IOC_WR_MODE, &mode);
	if (ret == -1)
		pabort("can't set spi mode");

	ret = ioctl(fd, SPI_IOC_RD_MODE, &mode);
	if (ret == -1)
		pabort("can't get spi mode");

	/*
	 * bits per word
	 */
	ret = ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits);
	if (ret == -1)
		pabort("can't set bits per word");

	ret = ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &bits);
	if (ret == -1)
		pabort("can't get bits per word");

	/*
	 * max speed hz
	 */
	ret = ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);
	if (ret == -1)
		pabort("can't set max speed hz");

	ret = ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed);
	if (ret == -1)
		pabort("can't get max speed hz");

	printf("spi mode: %d\n", mode);
	printf("bits per word: %d\n", bits);
	printf("max speed: %d Hz (%d KHz)\n", speed, speed/1000);


	uint32_t info = 1; /* unmask */

        ssize_t nb = write(fd3, &info, sizeof(info));
        if (nb != (ssize_t)sizeof(info)) {
            perror("write");
            close(fd3);
            exit(EXIT_FAILURE);
        }


	pthread_t tid1;
	pthread_create(&tid1, NULL, irqHandler, FPGA_SPISLAVE_vaddr_void);

	transfer(fd);
	

	

	close(fd);
	
	////////////////////////////////////
	////////////////////////////////////


	
	
	  printf("Pamiec po transferze SPI ");
  printbuff(DMA_TRANSFER_SRC_UP, TRANSFER_SIZE);
  
          /* Wait for interrupt */
        nb = read(fd3, &info, sizeof(info));
        if (nb == (ssize_t)sizeof(info)) {
							pthread_cond_signal(&cond1);
            /* Do something in response to the interrupt. */
            printf("Interrupt #%u!\n", info);
        }
  
		sleep(1);
  	if( munmap( virtual_base, HW_REGS_SPAN ) != 0 ) {
		printf( "ERROR: munmap() failed...\n" );
		close( fd2 );
		return( 1 );
	}

	close( fd2 );

	return 0;
}

