/* Very simplified WZTIM1 device driver
licensed under GPL v2
 */



#include <linux/kernel.h>
#include <linux/module.h>
#include <asm/uaccess.h>
MODULE_LICENSE("GPL v2");
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/sched.h>
#include <linux/mm.h>
#include <asm/io.h>
#include <linux/interrupt.h>
#include <linux/uaccess.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/kfifo.h>

#include <linux/init.h>
#include <linux/pci.h>
#include <linux/slab.h>
#include <linux/dma-mapping.h>
#include <linux/ioctl.h>

//#include <linux/mm.h>
#include <linux/mmu_notifier.h>
#include <linux/tracepoint.h>



#include "DMAC_app.h"


#define SUCCESS 0
#define DEVICE_NAME "DMA_Controller"

#define WR_VALUE _IOW('a','a',uint32_t*)


int irq=-1; 
unsigned long phys_addr = 0;

volatile uint32_t * fmem=NULL; //Pointer to registers area
volatile void * fdata=NULL; //Pointer to data buffer

DECLARE_KFIFO(rd_fifo,uint64_t,128);


static int tst1_open(struct inode *inode, struct file *file);
static int tst1_release(struct inode *inode, struct file *file);
ssize_t tst1_read(struct file *filp,
                  char __user *buf,size_t count, loff_t *off);
ssize_t tst1_write(struct file *filp,
                   const char __user *buf,size_t count, loff_t *off);
int tst1_mmap(struct file *filp, struct vm_area_struct *vma);
static long     etx_ioctl(struct file *file, unsigned int cmd, unsigned long arg);

uint32_t value =0;
uint32_t val;

int is_open = 0; //Flag informing if the device is open
dev_t my_dev=0;
//struct device *device1;
struct cdev * my_cdev = NULL;
static struct class *class_my_tst = NULL;

/* Queue for reading process */
DECLARE_WAIT_QUEUE_HEAD (readqueue);

static size_t size = PAGE_SIZE;
struct dma_pool *poolStruct;
dma_addr_t handle;
dma_addr_t handle2;
volatile uint32_t *kbuf = NULL;

struct platform_device *myDev = NULL;




static void output(uint32_t *akbuf, dma_addr_t handle, size_t size)
{

	printk(KERN_INFO "virtual Address = %8x, handle: = %8x , size = %d\n",akbuf, handle, size);


}

/* Interrupt service routine */
irqreturn_t tst1_irq(int irq, void * dev_id)
{
    // First we check if our device requests interrupt
    printk("<1> I'm in interrupt!\n");
    volatile uint32_t status; //Must be volatile to ensure 32-bit access!

    uint32_t mask = 0x0000001;

    volatile DMAC_Regs * regs;
    regs = (volatile DMAC_Regs *) fmem;
    status = regs->status;

    printk("<2> StatusReg: %x", status);
    if((mask & (status >> 1))) {
        //Yes, our device requests service

        //tutaj wyczyszczenie statusu, zakonczenie transakcji
        printk("<2.5> Jest interrupt, wpisuj do controla ");
        regs->control = 0x00000004; //request zdjecia interrupta w fpga
        wmb();
        printk("<3>Interrupt!! end of transfer");
        return IRQ_HANDLED;
    }
    printk("Interrupt przyszedl, ale rejest nietaki\n");
    return IRQ_NONE; //Our device does not request interrupt
};


struct file_operations Fops = {
    .owner = THIS_MODULE,
    .read=tst1_read, /* read */
    .write=tst1_write, /* write */
    .open=tst1_open,
    .release=tst1_release,  /* a.k.a. close */
    .llseek=no_llseek,
    .unlocked_ioctl = etx_ioctl,
    .mmap = tst1_mmap,
};

static long etx_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{

    uint32_t bb = 0;
         switch(cmd) {

                case WR_VALUE:

                            bb = __copy_from_user(&val ,arg,4);
                            if(bb)
                            {
                                printk("blad w kopiowaniu: %d\n", bb);
                            }
                                                
                            volatile DMAC_Regs * regs;

                            regs = (volatile DMAC_Regs *) fmem;
                            printk("bufor skopiowany\n");
                            regs->writeaddress = 0xC0000000;
                            wmb();
                            printk("writeadress wpisany\n");

                            regs->readaddress = handle;
                            wmb();
                            printk("readAddress wpisany\n");

                            
                            regs->control = val;
                            printk("value: %x\n\n",val);
                            wmb();
                            printk("control odpalony (dma GO powinno byc wpisane)\n");
                        pr_info("Value = %d\n", value);
                        break;
                default:
                        pr_info("Default\n");
                        break;
        }
        return 0;
}

/* Cleanup resources */
int tst1_remove( struct platform_device * pdev )
{
    if(my_dev && class_my_tst) {
        device_destroy(class_my_tst,my_dev);
    }
    if(fdata) free_pages((unsigned long)fdata,2);

    if(my_cdev) cdev_del(my_cdev);
    my_cdev=NULL;
    unregister_chrdev_region(my_dev, 1);
    if(class_my_tst) {
        class_destroy(class_my_tst);
        class_my_tst=NULL;
    }
    return SUCCESS;
}


static int tst1_open(struct inode *inode,
                     struct file *file)
{
    int res=0;
    volatile DMAC_Regs * regs;
    if(is_open) return -EBUSY; 
    regs = (volatile DMAC_Regs *) fmem;

    res=request_irq(irq,tst1_irq,IRQF_NO_THREAD,DEVICE_NAME,fmem);
    if(res) {
        printk (KERN_INFO "wzab_tst1: I can't connect irq %i error: %d\n", irq,res);
        irq = -1;
    }

    //wpisanie 0 do DONE bitu w COntrol registerze(ogolnie zerowanie statusu)
    printk (KERN_INFO "zerowanie statusu \n");
    regs->status = 0;
    wmb();
    regs->control = 0;
    wmb();

    return SUCCESS;
}

static int tst1_release(struct inode *inode,
                        struct file *file)
{
    volatile DMAC_Regs * regs;
    regs = (volatile DMAC_Regs *) fmem;
#ifdef DEBUG
    printk ("<1>device_release(%p,%p)\n", inode, file);
#endif

    
    if(irq>=0) free_irq(irq,fmem); //Free interrupt



    is_open=0;
    return SUCCESS;
}

ssize_t tst1_read(struct file *filp,
                  char __user *buf,size_t count, loff_t *off)
{

    if(_copy_to_user(buf,kbuf,count)) return -EFAULT;

    return 8;
}

ssize_t tst1_write(struct file *filp,
                   const char __user *buf,size_t count, loff_t *off)
{

    volatile DMAC_Regs * regs;


    uint32_t aa = 0;
    aa = __copy_from_user(kbuf,buf,count);
    if(aa)
     {
        printk("blad w kopiowaniu: %d\n", aa);
     }


    return 8;
}


void tst1_vma_open (struct vm_area_struct * area)
{  }

void tst1_vma_close (struct vm_area_struct * area)
{  }

static struct vm_operations_struct tst1_vm_ops = {
    .open=tst1_vma_open,
    .close=tst1_vma_close,
};

int tst1_mmap(struct file *filp,
              struct vm_area_struct *vma)
{
    // unsigned long off = vma->vm_pgoff << PAGE_SHIFT;
    // //Mapping of registers
    // unsigned long physical = phys_addr;
    // unsigned long vsize = vma->vm_end - vma->vm_start;
    // unsigned long psize = 0x1000; //One page is enough
    // //printk("<1>start mmap of registers\n");
    // if(vsize>psize)
    //     return -EINVAL;
    // vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
    // remap_pfn_range(vma,vma->vm_start, physical >> PAGE_SHIFT, vsize, vma->vm_page_prot);
    // if (vma->vm_ops)
    //     return -EINVAL; //It should never happen
    // vma->vm_ops = &tst1_vm_ops;
    // tst1_vma_open(vma); //This time no open(vma) was called
    // //printk("<1>mmap of registers succeeded!\n");



    return 0;
}


static int tst1_probe(struct platform_device * pdev)
{
    int res = 0;
    struct resource * resptr = NULL;


    irq = platform_get_irq(pdev,0);
    if(irq<0) {
        printk(KERN_ERR "Error reading the IRQ number: %d.\n",irq);
        res=irq;
        goto err1;
    }
    printk(KERN_ALERT "Connected IRQ=%d\n",irq);
    resptr = platform_get_resource(pdev,IORESOURCE_MEM,0);
    if(resptr==0) {
        printk(KERN_ERR "Error reading the register addresses.\n");
        res=-EINVAL;
        goto err1;
    }

    phys_addr = resptr->start;
    dev_info(&pdev->dev,"Connected registers at %lx\n",phys_addr);
    class_my_tst = class_create(THIS_MODULE, "my_tim_class");
    if (IS_ERR(class_my_tst)) {
        dev_err (&pdev->dev,"Error creating my_tst class.\n");
        res=PTR_ERR(class_my_tst);
        goto err1;
    }



    /* Alocate device number */
    res=alloc_chrdev_region(&my_dev, 0, 1, DEVICE_NAME);
    if(res) {
        dev_err (&pdev->dev,"Alocation of the device number for %s failed\n",
                DEVICE_NAME);
        goto err1;
    };
    my_cdev = cdev_alloc( );
    if(my_cdev == NULL) {
        dev_err (&pdev->dev,"Allocation of cdev for %s failed\n",
                DEVICE_NAME);
        goto err1;
    }
    my_cdev->ops = &Fops;
    my_cdev->owner = THIS_MODULE;
    /* Add character device */
    res=cdev_add(my_cdev, my_dev, 1);
    if(res) {
        dev_err (&pdev->dev,"Registration of the device number for %s failed\n",
                DEVICE_NAME);
        goto err1;
    };


    /* Create pointer needed to access registers */
    fmem = devm_ioremap_resource(&pdev->dev,resptr); 
    if(IS_ERR(fmem)) {
        dev_err (&pdev->dev,"Mapping of memory for %s registers failed\n",
                DEVICE_NAME);
        res= -ENOMEM;
        goto err1;
    }

    res = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
	if (res < 0)
    {
        printk("set_mask_koherent_err: %d\n" ,res);
		goto err1;
    }
    printk(KERN_INFO "Loading DMA allocation test module\n");
	kbuf = dma_alloc_coherent(&pdev->dev, size, &handle, GFP_KERNEL);

    if(!kbuf)
    {
        printk("blad alokacji \n");
        goto err1;
    }
    printk("dmaMem allocated\n");


    output(kbuf, handle, size);


    device_create(class_my_tst,NULL,my_dev,NULL,"my_tim%d",MINOR(my_dev));
    dev_info(&pdev->dev,"%s The major device number is %d.\n",
            "Successful registration.",
            MAJOR(my_dev));


    myDev = pdev;

    return 0;
err1:    
    tst1_remove(pdev);
    dma_free_coherent(&pdev->dev, size, kbuf, handle);
    return res;
}



static struct of_device_id dmac_driv_ids[] = {
    {
        .compatible = "dma_controller" //musi byc zgodne z compatible w .sopcinfo z quartusa
    },
    {},
};
struct platform_driver my_driver = {
    .driver = {
        .name = "drv_DMAC",
        .of_match_table = dmac_driv_ids,
    },
    .probe = tst1_probe,
    .remove = tst1_remove,
};

static int my_init(void)
{
    

    int ret = platform_driver_register(&my_driver);
    if (ret < 0) {
        printk(KERN_ERR "Failed to register my platform driver: %d\n",ret);
        return ret;
    }


    printk(KERN_ALERT "DMAC_REGISTRED\n");
    return 0;
}
static void my_exit(void)
{
    dma_free_coherent(&myDev->dev, size, kbuf, handle);
    platform_driver_unregister(&my_driver);
    printk(KERN_ALERT "DMAC_UNREGISTRED\n");
}

module_init(my_init);
module_exit(my_exit);

