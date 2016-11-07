############################################################################
< envPaths

# For deviocstats
epicsEnvSet("ENGINEER", "Andrew Gomella")
epicsEnvSet("LOCATION", "B1D521D DT-ASUSWIN102")
epicsEnvSet("STARTUP","$(TOP)/iocBoot/$(IOC)")
epicsEnvSet("ST_CMD","st.cmd")

# Change this PV according to set-up
epicsEnvSet("PREFIX", "VPFI:Qi2")
epicsEnvSet("P", "$(PREFIX)")
epicsEnvSet "CONFIG" "$(CONFIG=detector)"
epicsEnvSet "EPICS_IOC_LOG_INET" "192.168.1.102"
epicsEnvSet "EPICS_IOC_LOG_PORT" "7004"
epicsEnvSet("PORT",   "KS1")
epicsEnvSet("QSIZE",  "200")
epicsEnvSet("XSIZE",  "4908")
epicsEnvSet("YSIZE",  "3264")
epicsEnvSet("NCHANS", "2048")
epicsEnvSet("CBUFFS", "500")
epicsEnvSet("EPICS_DB_INCLUDE_PATH", "$(ADCORE)/db")
############################################################################
# Increase size of buffer for error logging from default 1256
errlogInit(20000)
############################################################################
dbLoadDatabase("$(TOP)/dbd/KsApp.dbd")
KsApp_registerRecordDeviceDriver(pdbbase) 
############################################################################
#KsCamConfig: PORT, CameraIndexNumber, maxBuffers, maxMemory, priority, stackSize
#CameraIndexNumber:
# with camera attached:
# 0 : Attached camera 
# 1 : DS-Ri2(Simulation)
# 2 : DS-Qi2(Simulation)
# without camera attached:
# 0 : DS-Ri2(Simulation)
# 1 : DS-Qi2(Simulation)
KsCamConfig("$(PORT)", 0, 200, 0, 0 , 0 )
#asynSetTraceMask("$(PORT)",0,255)
#asynSetTraceMask("$(PORT)",0,3)
############################################################################
# Load record instances
dbLoadRecords("$(ADCORE)/db/ADBase.template",   "P=$(PREFIX):,R=cam1:,PORT=$(PORT),ADDR=0,TIMEOUT=1,NDARRAY_PORT=$(PORT)")
dbLoadRecords("$(ADCORE)/db/NDFile.template",   "P=$(PREFIX):,R=cam1:,PORT=$(PORT),ADDR=0,TIMEOUT=1")

# Note that Ks.template must be loaded after NDFile.template to replace the file format correctly
dbLoadRecords("$(ADNIKONKS)/db/Ks.template","P=$(PREFIX):,R=cam1:,PORT=$(PORT),ADDR=0,TIMEOUT=1")

# Create a standard arrays plugin
NDStdArraysConfigure("Image1", 5, 0, "$(PORT)", 0, 0)
dbLoadRecords("$(ADCORE)/db/NDPluginBase.template","P=$(PREFIX):,R=image1:,PORT=Image1,ADDR=0,TIMEOUT=1,NDARRAY_PORT=$(PORT),NDARRAY_ADDR=0")
dbLoadRecords("$(ADCORE)/db/NDStdArrays.template", "P=$(PREFIX):,R=image1:,PORT=Image1,ADDR=0,TIMEOUT=1,NDARRAY_PORT=$(PORT),TYPE=Int16,FTVL=SHORT,NELEMENTS=16019712")

# Create another standard arrays plugin
NDStdArraysConfigure("Image2", 200, 0, "$(PORT)", 0, 0)
dbLoadRecords("$(ADCORE)/db/NDPluginBase.template","P=$(PREFIX):,R=image2:,PORT=Image2,ADDR=0,TIMEOUT=1,NDARRAY_PORT=$(PORT),NDARRAY_ADDR=0")
dbLoadRecords("$(ADCORE)/db/NDStdArrays.template", "P=$(PREFIX):,R=image2:,PORT=Image2,ADDR=0,TIMEOUT=1,NDARRAY_PORT=$(PORT),TYPE=Int16,FTVL=SHORT,NELEMENTS=16019712")

# Load iocAdmin records
dbLoadRecords("$(DEVIOCSTATS)/db/iocAdminSoft.db", "IOC=$(PREFIX)")

# Load records for master dark and flat acquistion and correction
dbLoadRecords("$(ADNIKONKS)/db/makeDark.db","P=$(PREFIX)")
dbLoadRecords("$(ADNIKONKS)/db/makeFlat.db","P=$(PREFIX)")
############################################################################
cd $(IPL_SUPPORT)
# Load all other plugins for area-detector
< ad_plugins.cmd
# Load save_restore.cmd
< save_restore.cmd
set_requestfile_path("$(ADNIKONKS)/KsApp/Db")
asSetFilename("$(IPL_SUPPORT)/security.acf")
############################################################################
# Start EPICS IOC
cd $(STARTUP)
iocInit()
############################################################################
# Start sequence program
seq &ADInitSettings("A=$(P)")
seq &makeDark("A=$(P)")
seq &makeFlat("A=$(P), X=VPFI:OXFORD:xray")
############################################################################
# save things every 5 seconds
create_monitor_set("auto_settings.req", 5,"P=$(PREFIX):")

# Handle autosave 'commands' contained in loaded databases
# Searches through the EPICS database for info nodes named 'autosaveFields' 
# and 'autosaveFields_pass0' and write the PV names to the files 
# 'info_settings.req' and 'info_positions.req'
makeAutosaveFiles()
create_monitor_set("info_positions.req",5,"P=$(PREFIX):")
create_monitor_set("info_settings.req",30,"P=$(PREFIX):")
############################################################################
# Start EPICS IOC log server
iocLogInit()
setIocLogDisable(0)
############################################################################
# Turn on caPutLogging:
# Log values only on change to the iocLogServer:
caPutLogInit("$(EPICS_IOC_LOG_INET):$(EPICS_IOC_LOG_PORT)",1)
caPutLogShow(2)
############################################################################
# Set Qi2 Gain to 6400
dbpf("$(PREFIX):cam1:Gain", "6400")
############################################################################
# write all the PV names to a local file
dbl > records.txt
############################################################################
# print the time our boot was finished
date
############################################################################