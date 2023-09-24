# TCL File Generated by Component Editor 22.1
# Mon Aug 28 23:00:32 CEST 2023
# DO NOT MODIFY


# 
# SPI_slave "SPI_slave" v1.2
#  2023.08.28.23:00:32
# 
# 

# 
# request TCL package from ACDS 16.1
# 
package require -exact qsys 16.1


# 
# module SPI_slave
# 
set_module_property DESCRIPTION ""
set_module_property NAME SPI_slave
set_module_property VERSION 1.2
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property AUTHOR ""
set_module_property DISPLAY_NAME SPI_slave
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false


# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL SPI_slave
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE true
add_fileset_file SPI_slave.vhd VHDL PATH ../src/SPI_slave.vhd TOP_LEVEL_FILE


# 
# parameters
# 


# 
# module assignments
# 
set_module_assignment embeddedsw.dts.compatible spi_slave
set_module_assignment embeddedsw.dts.group generic-uio
set_module_assignment embeddedsw.dts.vendor biw


# 
# display items
# 


# 
# connection point avalon_master
# 
add_interface avalon_master avalon start
set_interface_property avalon_master addressUnits SYMBOLS
set_interface_property avalon_master associatedClock i_clk
set_interface_property avalon_master associatedReset i_reset
set_interface_property avalon_master bitsPerSymbol 8
set_interface_property avalon_master burstOnBurstBoundariesOnly false
set_interface_property avalon_master burstcountUnits WORDS
set_interface_property avalon_master doStreamReads false
set_interface_property avalon_master doStreamWrites false
set_interface_property avalon_master holdTime 0
set_interface_property avalon_master linewrapBursts false
set_interface_property avalon_master maximumPendingReadTransactions 0
set_interface_property avalon_master maximumPendingWriteTransactions 0
set_interface_property avalon_master readLatency 0
set_interface_property avalon_master readWaitTime 1
set_interface_property avalon_master setupTime 0
set_interface_property avalon_master timingUnits Cycles
set_interface_property avalon_master writeWaitTime 0
set_interface_property avalon_master ENABLED true
set_interface_property avalon_master EXPORT_OF ""
set_interface_property avalon_master PORT_NAME_MAP ""
set_interface_property avalon_master CMSIS_SVD_VARIABLES ""
set_interface_property avalon_master SVD_ADDRESS_GROUP ""

add_interface_port avalon_master avalon_master_address address Output 32
add_interface_port avalon_master avalon_master_read read Output 1
add_interface_port avalon_master avalon_master_write write Output 1
add_interface_port avalon_master avalon_master_writedata writedata Output 32
add_interface_port avalon_master avalon_master_readdata readdata Input 32
add_interface_port avalon_master avalon_master_waitrequest waitrequest Input 1


# 
# connection point i_clk
# 
add_interface i_clk clock end
set_interface_property i_clk clockRate 50000000
set_interface_property i_clk ENABLED true
set_interface_property i_clk EXPORT_OF ""
set_interface_property i_clk PORT_NAME_MAP ""
set_interface_property i_clk CMSIS_SVD_VARIABLES ""
set_interface_property i_clk SVD_ADDRESS_GROUP ""

add_interface_port i_clk i_clk clk Input 1


# 
# connection point i_reset
# 
add_interface i_reset reset end
set_interface_property i_reset associatedClock i_clk
set_interface_property i_reset synchronousEdges DEASSERT
set_interface_property i_reset ENABLED true
set_interface_property i_reset EXPORT_OF ""
set_interface_property i_reset PORT_NAME_MAP ""
set_interface_property i_reset CMSIS_SVD_VARIABLES ""
set_interface_property i_reset SVD_ADDRESS_GROUP ""

add_interface_port i_reset i_reset reset Input 1


# 
# connection point SPI
# 
add_interface SPI conduit end
set_interface_property SPI associatedClock ""
set_interface_property SPI associatedReset ""
set_interface_property SPI ENABLED true
set_interface_property SPI EXPORT_OF ""
set_interface_property SPI PORT_NAME_MAP ""
set_interface_property SPI CMSIS_SVD_VARIABLES ""
set_interface_property SPI SVD_ADDRESS_GROUP ""

add_interface_port SPI o_miso rxd Output 1
add_interface_port SPI i_mosi txd Input 1
add_interface_port SPI o_ss_out_valid ssi_oe_n Input 1
add_interface_port SPI i_ss3 ss_3_n Input 1
add_interface_port SPI i_ss0 ss_0_n Input 1
add_interface_port SPI i_ss1 ss_1_n Input 1
add_interface_port SPI i_ss2 ss_2_n Input 1
add_interface_port SPI ss_enable ss_in_n Output 1


# 
# connection point i_spi_clk
# 
add_interface i_spi_clk clock end
set_interface_property i_spi_clk clockRate 50000000
set_interface_property i_spi_clk ENABLED true
set_interface_property i_spi_clk EXPORT_OF ""
set_interface_property i_spi_clk PORT_NAME_MAP ""
set_interface_property i_spi_clk CMSIS_SVD_VARIABLES ""
set_interface_property i_spi_clk SVD_ADDRESS_GROUP ""

add_interface_port i_spi_clk i_spi_clk clk Input 1


# 
# connection point irq
# 
add_interface irq interrupt end
set_interface_property irq associatedAddressablePoint ""
set_interface_property irq associatedClock i_clk
set_interface_property irq associatedReset i_reset
set_interface_property irq bridgedReceiverOffset 0
set_interface_property irq bridgesToReceiver ""
set_interface_property irq ENABLED true
set_interface_property irq EXPORT_OF ""
set_interface_property irq PORT_NAME_MAP ""
set_interface_property irq CMSIS_SVD_VARIABLES ""
set_interface_property irq SVD_ADDRESS_GROUP ""

add_interface_port irq irq irq Output 1


# 
# connection point avalon_slave
# 
add_interface avalon_slave avalon end
set_interface_property avalon_slave addressUnits WORDS
set_interface_property avalon_slave associatedClock i_clk
set_interface_property avalon_slave associatedReset i_reset
set_interface_property avalon_slave bitsPerSymbol 8
set_interface_property avalon_slave burstOnBurstBoundariesOnly false
set_interface_property avalon_slave burstcountUnits WORDS
set_interface_property avalon_slave explicitAddressSpan 0
set_interface_property avalon_slave holdTime 0
set_interface_property avalon_slave linewrapBursts false
set_interface_property avalon_slave maximumPendingReadTransactions 0
set_interface_property avalon_slave maximumPendingWriteTransactions 0
set_interface_property avalon_slave readLatency 0
set_interface_property avalon_slave readWaitTime 1
set_interface_property avalon_slave setupTime 0
set_interface_property avalon_slave timingUnits Cycles
set_interface_property avalon_slave writeWaitTime 0
set_interface_property avalon_slave ENABLED true
set_interface_property avalon_slave EXPORT_OF ""
set_interface_property avalon_slave PORT_NAME_MAP ""
set_interface_property avalon_slave CMSIS_SVD_VARIABLES ""
set_interface_property avalon_slave SVD_ADDRESS_GROUP ""

add_interface_port avalon_slave avalon_slave_address address Input 1
add_interface_port avalon_slave avalon_slave_read read Input 1
add_interface_port avalon_slave avalon_slave_readdata readdata Output 32
add_interface_port avalon_slave avalon_slave_write write Input 1
add_interface_port avalon_slave avalon_slave_writedata writedata Input 32
set_interface_assignment avalon_slave embeddedsw.configuration.isFlash 0
set_interface_assignment avalon_slave embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment avalon_slave embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment avalon_slave embeddedsw.configuration.isPrintableDevice 0

