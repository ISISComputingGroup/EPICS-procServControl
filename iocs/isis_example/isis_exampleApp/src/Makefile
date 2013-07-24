TOP=../..

include $(TOP)/configure/CONFIG
#----------------------------------------
#  ADD MACRO DEFINITIONS AFTER THIS LINE
#=============================

#=============================
# Build the IOC application

PROD_IOC = isis_example
# isis_example.dbd will be created and installed
DBD += isis_example.dbd

# isis_example.dbd will be made up from these files:
isis_example_DBD += base.dbd
isis_example_DBD += asyn.dbd
isis_example_DBD += drvAsynIPPort.dbd
isis_example_DBD += busySupport.dbd
isis_example_DBD += procServControl.dbd

# Include dbd files from all support applications:
#isis_example_DBD += xxx.dbd

# Add all the support libraries needed by this IOC
#isis_example_LIBS += xxx

# isis_example_registerRecordDeviceDriver.cpp derives from isis_example.dbd
isis_example_SRCS += isis_example_registerRecordDeviceDriver.cpp

# Build the main IOC entry point on workstation OSs.
isis_example_SRCS_DEFAULT += isis_exampleMain.cpp
isis_example_SRCS_vxWorks += -nil-

# Add support from base/src/vxWorks if needed
#isis_example_OBJS_vxWorks += $(EPICS_BASE_BIN)/vxComLibrary
isis_example_LIBS += procServControl busy seq pv asyn

# Finally link to the EPICS Base libraries
isis_example_LIBS += $(EPICS_BASE_IOC_LIBS)

#===========================

include $(TOP)/configure/RULES
#----------------------------------------
#  ADD RULES AFTER THIS LINE

